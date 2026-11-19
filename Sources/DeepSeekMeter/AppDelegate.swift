import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let model: AppModel
    private let demo: Bool
    private var widgetPanel: WidgetPanel?
    private var cardPanel: CardPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private var hoverWork: DispatchWorkItem?
    private var dismissalTimer: Timer?
    private var outsideTicks = 0
    private var widgetHidden = false

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    init(demo: Bool = false) {
        self.demo = demo
        self.model = AppModel(preview: demo)
        super.init()
    }

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        migrateWidgetHeight()
        buildPanels()
        buildStatusItem()
        installHotKey()
        observeWorkspace()

        if ProcessInfo.processInfo.environment["DSB_TEST_KEYCHAIN"] == "1" {
            NSLog("[DeepSeekMeter] secret store test: \(SecretStore.selfTest()) at \(SecretStore.fileURL.path)")
        }

        if !demo {
            model.start()
            if !model.hasKey {
                showOnboarding()
            }
        }
        NSLog("[DeepSeekMeter] launched, key=\(model.hasKey ? "yes" : "no"), size=\(Prefs.shared.widgetHeight)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// LSUIElement 的 App 默认没有主菜单，⌘C/⌘V/⌘A 就没有响应者。
    /// 这里挂一个最小菜单（菜单栏不显示，但快捷键会走 NSApp.mainMenu）。
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 DeepSeek Meter",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 DeepSeek Meter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 DeepSeek Meter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = main
        if ProcessInfo.processInfo.environment["DSB_TEST_MENU"] == "1" {
            let edit = main.items.first { $0.submenu?.title == "编辑" }?.submenu
            let paste = edit?.items.first { $0.title == "粘贴" }
            NSLog("[DeepSeekMeter] menu: edit=\(edit != nil) pasteKey=\(paste?.keyEquivalent ?? "nil") items=\(edit?.items.count ?? 0)")
        }
    }

    // MARK: 面板

    /// 旧版本存的是 44/50/56，新尺寸是 31/35/39（整体缩 30%）
    private func migrateWidgetHeight() {
        let allowed: [CGFloat] = [31, 35, 39]
        if !allowed.contains(Prefs.shared.widgetHeight) {
            Prefs.shared.widgetHeight = 35
        }
    }

    private func buildPanels() {
        let widget = WidgetPanel(model: model, size: Prefs.shared.widgetHeight)
        widget.events.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        widget.events.onClick = { [weak self] in self?.widgetClicked() }
        widget.events.onDoubleClick = { [weak self] in self?.openSettings() }
        widget.events.onRightClick = { [weak self] event in self?.showContextMenu(event) }
        widget.events.onDragBegan = { [weak self] in
            guard let self else { return }
            self.model.dragging = true
            self.hideCard()
        }
        widget.events.onDragEnded = { [weak self] in
            guard let self else { return }
            self.model.dragging = false
            self.snapWidget()
            Prefs.shared.widgetOrigin = widget.frame.origin
        }
        widgetPanel = widget

        let card = CardPanel(model: model,
                             onSettings: { [weak self] in self?.openSettings() },
                             onRefresh: { [weak self] in Task { await self?.model.refresh() } },
                             onOpenPlatform: { Self.openPlatform() })
        cardPanel = card

        placeWidgetAtStartup()
        widget.orderFrontRegardless()
        applyCollectionBehavior()
    }

    private func placeWidgetAtStartup() {
        guard let widget = widgetPanel else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = widget.frame.size
        var origin = Prefs.shared.widgetOrigin
            ?? NSPoint(x: visible.maxX - size.width - 96, y: visible.minY + 120)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        widget.setFrameOrigin(origin)
    }

    private func applyCollectionBehavior() {
        guard let widget = widgetPanel else { return }
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if !Prefs.shared.hideInFullscreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        widget.collectionBehavior = behavior
    }

    // MARK: 自检（无法注入鼠标事件时用代码走一遍交互）

    func selfTest() {
        guard let widget = widgetPanel, let card = cardPanel else { return }
        let screen = widget.screen ?? NSScreen.main ?? NSScreen.screens[0]
        model.hovering = true
        model.cardPinned = true
        model.cardVisible = true
        card.present(widgetFrame: widget.widgetFrame, screen: screen, animated: false)
        startDismissalTimer()
        scheduleRefit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSLog("[DeepSeekMeter] selftest pinned cardH=\(card.frame.height) visible=\(card.isVisible) alpha=\(card.alphaValue)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSLog("[DeepSeekMeter] selftest settings visible=\(self.settingsWindow?.isVisible ?? false) h=\(self.settingsWindow?.frame.height ?? 0)")
            }
        }
    }

    // MARK: 悬停 / 点击

    private func hoverChanged(_ inside: Bool) {
        model.hovering = inside
        hoverWork?.cancel()
        guard inside else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.hovering, !self.widgetHidden else { return }
            self.showCard(animated: true)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func widgetClicked() {
        if model.cardPinned {
            model.cardPinned = false
            hideCard()
        } else {
            model.cardPinned = true
            showCard(animated: true)
            scheduleRefit()
        }
    }

    private func showCard(animated: Bool) {
        guard let widget = widgetPanel, let card = cardPanel else { return }
        let screen = widget.screen ?? NSScreen.main ?? NSScreen.screens[0]
        card.present(widgetFrame: widget.widgetFrame, screen: screen, animated: animated)
        model.cardVisible = true
        startDismissalTimer()
        scheduleRefit()
    }

    /// SwiftUI 的高度变化比窗口晚一拍，这里补两次测量，避免固定态多出的一行被裁掉
    private func scheduleRefit() {
        guard let widget = widgetPanel, let card = cardPanel, model.cardVisible else { return }
        let screen = widget.screen ?? NSScreen.main ?? NSScreen.screens[0]
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.cardVisible else { return }
            card.refit(widgetFrame: widget.widgetFrame, screen: screen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, self.model.cardVisible else { return }
                card.refit(widgetFrame: widget.widgetFrame, screen: screen)
            }
        }
    }

    private func hideCard() {
        guard model.cardVisible || model.cardPinned else { return }
        model.cardPinned = false
        model.cardVisible = false
        cardPanel?.dismiss()
        stopDismissalTimer()
    }

    private func startDismissalTimer() {
        guard dismissalTimer == nil else { return }
        outsideTicks = 0
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickDismissal() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissalTimer = timer
    }

    private func stopDismissalTimer() {
        dismissalTimer?.invalidate()
        dismissalTimer = nil
        outsideTicks = 0
    }

    private func tickDismissal() {
        guard model.cardVisible, let widget = widgetPanel, let card = cardPanel else { return }
        let point = NSEvent.mouseLocation
        let inWidget = widget.frame.insetBy(dx: -6, dy: -6).contains(point)
        let inCard = card.frame.insetBy(dx: -10, dy: -10).contains(point)
        if inWidget || inCard {
            outsideTicks = 0
        } else {
            outsideTicks += 1
        }
        if outsideTicks > 6 && !model.cardPinned {
            hideCard()
        }
    }

    // MARK: 拖动吸附

    private func snapWidget() {
        guard let widget = widgetPanel else { return }
        let screen = widget.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var frame = widget.frame
        let margin: CGFloat = 12
        let leftGap = abs(frame.minX - visible.minX)
        let rightGap = abs(visible.maxX - frame.maxX)
        if min(leftGap, rightGap) < 48 {
            frame.origin.x = leftGap < rightGap ? visible.minX + margin : visible.maxX - frame.width - margin
        }
        frame.origin.y = min(max(frame.origin.y, visible.minY + margin), visible.maxY - frame.height - margin)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            widget.animator().setFrameOrigin(frame.origin)
        }
    }

    // MARK: 菜单

    private func showContextMenu(_ event: NSEvent) {
        guard let view = widgetPanel?.contentView else { return }
        let menu = NSMenu()
        menu.addItem(item("刷新余额", #selector(menuRefresh), "r"))
        menu.addItem(item(model.cardPinned ? "取消固定" : "固定卡片", #selector(menuPin), "p"))
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(menuSettings), ","))
        menu.addItem(item("打开 DeepSeek 平台", #selector(menuPlatform), ""))
        menu.addItem(.separator())
        menu.addItem(item("隐藏挂件", #selector(menuHide), "h"))
        menu.addItem(item("退出 DeepSeek Meter", #selector(menuQuit), "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuRefresh() { Task { await model.refresh() } }
    @objc private func menuPin() { widgetClicked() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuPlatform() { Self.openPlatform() }
    @objc private func menuHide() { toggleWidget() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func buildStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "DeepSeek Meter")
            button.image?.isTemplate = true
            button.toolTip = "DeepSeek 余额"
        }
        let menu = NSMenu()
        let show = NSMenuItem(title: "显示挂件", action: #selector(statusToggle), keyEquivalent: "")
        show.target = self
        show.state = .on
        menu.addItem(show)
        let refresh = NSMenuItem(title: "刷新余额", action: #selector(statusRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let settings = NSMenuItem(title: "设置…", action: #selector(statusSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 DeepSeek Meter", action: #selector(statusQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        status.menu = menu
        statusItem = status
    }

    @objc private func statusToggle() { toggleWidget() }
    @objc private func statusRefresh() { Task { await model.refresh() } }
    @objc private func statusSettings() { openSettings() }
    @objc private func statusQuit() { NSApp.terminate(nil) }

    private func toggleWidget() {
        widgetHidden.toggle()
        if widgetHidden {
            hideCard()
            widgetPanel?.orderOut(nil)
        } else {
            widgetPanel?.orderFrontRegardless()
        }
        statusItem?.menu?.item(at: 0)?.state = widgetHidden ? .off : .on
    }

    // MARK: 设置 / 引导

    private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, onChange: { [weak self] in self?.applyPrefs() })
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "DeepSeek Meter 设置"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        model.settingsOpen = true
    }

    private func showOnboarding() {
        let view = OnboardingView(model: model,
                                  onDone: { [weak self] in
                                      self?.onboardingWindow?.close()
                                      self?.onboardingWindow = nil
                                      Task { await self?.model.refresh() }
                                  },
                                  onQuit: { NSApp.terminate(nil) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 268),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "DeepSeek Meter"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            model.settingsOpen = false
        }
    }

    private func applyPrefs() {
        guard let widget = widgetPanel else { return }
        widget.applySize(Prefs.shared.widgetHeight)
        Prefs.shared.widgetOrigin = widget.frame.origin
        applyCollectionBehavior()
        model.applyPrefsChange()
        if model.cardVisible {
            if let card = cardPanel {
                let screen = widget.screen ?? NSScreen.main ?? NSScreen.screens[0]
                card.refit(widgetFrame: widget.widgetFrame, screen: screen)
            }
        }
    }

    // MARK: 工作区

    private func observeWorkspace() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let widget = self.widgetPanel else { return }
                if self.widgetHidden { return }
                self.clampToScreen(widget)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let widget = self.widgetPanel else { return }
                self.clampToScreen(widget)
                self.hideCard()
            }
        }
    }

    private func clampToScreen(_ widget: WidgetPanel) {
        guard let screen = widget.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = widget.frame
        frame.origin.x = min(max(frame.minX, visible.minX + 4), visible.maxX - frame.width - 4)
        frame.origin.y = min(max(frame.minY, visible.minY + 4), visible.maxY - frame.height - 4)
        if frame.origin != widget.frame.origin {
            widget.setFrameOrigin(frame.origin)
            Prefs.shared.widgetOrigin = frame.origin
        }
    }

    // MARK: 快捷键 ⌥⌘H

    private func installHotKey() {
        var hotKeyID = EventHotKeyID(signature: OSType(0x4453424C), id: 1)
        let modifiers = UInt32(cmdKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_H), modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.toggleWidget()
            }
            return noErr
        }, 1, &eventType, selfPtr, &hotKeyHandler)
    }

    // MARK: 工具

    static func openPlatform() {
        if let url = URL(string: "https://platform.deepseek.com/usage") {
            NSWorkspace.shared.open(url)
        }
    }
}
