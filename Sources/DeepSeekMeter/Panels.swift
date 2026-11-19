import AppKit
import SwiftUI

// MARK: - 无边框浮窗

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        animationBehavior = .utilityWindow
    }
}

// MARK: - 首次点击即响应（非激活窗口里的按钮）

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 球的鼠标事件容器

final class WidgetContainerView: NSView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var tracking: NSTrackingArea?
    private var pressLocation: NSPoint = .zero
    private var originAtPress: NSPoint = .zero
    private var isDragging = false

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        pressLocation = NSEvent.mouseLocation
        originAtPress = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - pressLocation.x
        let dy = point.y - pressLocation.y
        if !isDragging && hypot(dx, dy) > 3 {
            isDragging = true
            onDragBegan?()
        }
        guard isDragging else { return }
        window.setFrameOrigin(NSPoint(x: originAtPress.x + dx, y: originAtPress.y + dy))
        onDragMoved?(window.frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnded?()
        } else {
            onClick?()
        }
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

// MARK: - 球窗口

final class WidgetPanel: FloatingPanel {
    private let model: AppModel
    private var widgetHeight: CGFloat
    private let container = WidgetContainerView()
    private(set) var hosting: NSHostingView<AnyView>?

    static let margin: CGFloat = 5

    init(model: AppModel, size: CGFloat) {
        self.model = model
        self.widgetHeight = size
        let rect = WidgetPanel.contentSize(for: size)
        super.init(contentRect: NSRect(origin: .zero, size: rect))
        container.frame = NSRect(origin: .zero, size: rect)
        container.autoresizingMask = [.width, .height]
        contentView = container
        rebuildContent()
    }

    func rebuildContent() {
        hosting?.removeFromSuperview()
        let root = AnyView(WidgetRoot(model: model, size: widgetHeight))
        let view = NSHostingView(rootView: root)
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        hosting = view
    }

    /// 窗口尺寸 = 矩形 + 四周热区
    static func contentSize(for height: CGFloat) -> NSSize {
        NSSize(width: WidgetMetrics.width(for: height) + margin * 2, height: height + margin * 2)
    }

    func applySize(_ size: CGFloat) {
        guard size != widgetHeight else { return }
        widgetHeight = size
        let next = WidgetPanel.contentSize(for: size)
        var frame = self.frame
        // 保持中心位置不变
        frame.origin.x += (frame.width - next.width) / 2
        frame.origin.y += (frame.height - next.height) / 2
        frame.size = next
        setFrame(frame, display: true)
        container.frame = NSRect(origin: .zero, size: frame.size)
        rebuildContent()
    }

    var widgetFrame: NSRect {
        NSRect(x: frame.minX + WidgetPanel.margin,
               y: frame.minY + WidgetPanel.margin,
               width: WidgetMetrics.width(for: widgetHeight),
               height: widgetHeight)
    }

    var events: WidgetContainerView { container }
}

struct WidgetRoot: View {
    @ObservedObject var model: AppModel
    var size: CGFloat

    var body: some View {
        WidgetView(model: model,
                 height: size,
                 active: model.hovering || model.cardVisible || model.cardPinned || model.dragging)
    }
}

// MARK: - 卡片窗口

final class CardPanel: FloatingPanel {
    private let model: AppModel
    private let hosting: NSHostingView<AnyView>
    private var lastSideRight = true

    init(model: AppModel,
         onSettings: @escaping () -> Void,
         onRefresh: @escaping () -> Void,
         onOpenPlatform: @escaping () -> Void) {
        self.model = model
        let card = AnyView(CardView(model: model,
                                    onSettings: onSettings,
                                    onRefresh: onRefresh,
                                    onOpenPlatform: onOpenPlatform))
        hosting = FirstMouseHostingView(rootView: card)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 268, height: 258))
        contentView = hosting
        alphaValue = 0
    }

    private var contentSize: NSSize {
        let fitting = hosting.fittingSize
        return NSSize(width: 268, height: max(120, fitting.height))
    }

    func present(widgetFrame: NSRect, screen: NSScreen, animated: Bool) {
        let size = contentSize
        let target = CardPlacement.frame(cardSize: size, widgetFrame: widgetFrame,
                                         visible: screen.visibleFrame,
                                         preferRight: preferredRight(for: widgetFrame, screen: screen))
        setFrame(target, display: true)
        hosting.frame = NSRect(origin: .zero, size: size)
        orderFrontRegardless()
        hosting.autoresizingMask = [.width, .height]
        if animated {
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    /// 窗口高度可能因为固定态多一行而变化，重新测量并保持贴合球
    func refit(widgetFrame: NSRect, screen: NSScreen) {
        guard isVisible else { return }
        let size = contentSize
        let target = CardPlacement.frame(cardSize: size, widgetFrame: widgetFrame,
                                         visible: screen.visibleFrame,
                                         preferRight: preferredRight(for: widgetFrame, screen: screen))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            animator().setFrame(target, display: true)
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    private func preferredRight(for widgetFrame: NSRect, screen: NSScreen) -> Bool {
        let mid = screen.visibleFrame.midX
        let delta = widgetFrame.midX - mid
        if abs(delta) < 8 { return lastSideRight }
        lastSideRight = delta < 0
        return lastSideRight
    }
}

// MARK: - 摆位

enum CardPlacement {
    static func frame(cardSize: NSSize, widgetFrame: NSRect, visible: NSRect, preferRight: Bool) -> NSRect {
        let gap: CGFloat = 10
        let margin: CGFloat = 8
        let width = cardSize.width
        let height = cardSize.height

        var x = preferRight ? widgetFrame.maxX + gap : widgetFrame.minX - gap - width
        if x + width > visible.maxX - margin {
            x = widgetFrame.minX - gap - width
        }
        if x < visible.minX + margin {
            x = widgetFrame.maxX + gap
        }
        x = min(max(x, visible.minX + margin), max(visible.minX + margin, visible.maxX - width - margin))

        var y = widgetFrame.midY - height / 2
        y = min(max(y, visible.minY + margin), max(visible.minY + margin, visible.maxY - height - margin))
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
