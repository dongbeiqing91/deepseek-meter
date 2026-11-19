import SwiftUI
import AppKit

// MARK: - 色板

enum Palette {
    static let disc = Color(red: 17 / 255, green: 20 / 255, blue: 25 / 255)
    static let track = Color(red: 43 / 255, green: 49 / 255, blue: 60 / 255)
    static let brand = Color(red: 77 / 255, green: 107 / 255, blue: 254 / 255)
    static let brandSoft = Color(red: 92 / 255, green: 121 / 255, blue: 255 / 255)
    static let danger = Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255)
    static let offlineDisc = Color(red: 58 / 255, green: 63 / 255, blue: 73 / 255)
    static let offlineRing = Color(red: 138 / 255, green: 145 / 255, blue: 157 / 255)
    static let text = Color(red: 244 / 255, green: 247 / 255, blue: 255 / 255)
    static let text2 = Color(red: 152 / 255, green: 162 / 255, blue: 189 / 255)
    static let text3 = Color(red: 106 / 255, green: 116 / 255, blue: 140 / 255)
    static let up = Color(red: 245 / 255, green: 163 / 255, blue: 163 / 255)
    static let down = Color(red: 127 / 255, green: 217 / 255, blue: 184 / 255)
    static let cardBG = Color(red: 14 / 255, green: 18 / 255, blue: 30 / 255)
    static let cardLine = Color.white.opacity(0.10)
}

// MARK: - 球

/// 矩形的尺寸规则：高 = Prefs.widgetHeight，宽按 66:35 推导，圆角 1/3.5 高
enum WidgetMetrics {
    static let aspect: CGFloat = 66.0 / 35.0
    static func width(for height: CGFloat) -> CGFloat { (height * aspect).rounded() }
    static func radius(for height: CGFloat) -> CGFloat { (height / 3.5).rounded() }
}

struct WidgetView: View {
    @ObservedObject var model: AppModel
    var height: CGFloat
    var active: Bool

    private var k: CGFloat { height / 35.0 }
    private var width: CGFloat { WidgetMetrics.width(for: height) }
    private var radius: CGFloat { WidgetMetrics.radius(for: height) }
    private var idleOpacity: Double { Prefs.shared.idleOpacity }

    private var bodyColor: Color {
        model.phase == .offline ? Palette.offlineDisc : Palette.disc
    }

    private var accent: Color {
        if model.isLow { return Palette.danger }
        switch model.phase {
        case .offline: return Palette.offlineRing
        case .unauthorized: return Palette.danger
        default: return Palette.brand
        }
    }

    private var showsBar: Bool {
        model.showsCurrencySymbol && Prefs.shared.budgetEnabled && model.phase != .noKey
    }

    private var numberColor: Color {
        model.phase == .offline ? Color(red: 230 / 255, green: 233 / 255, blue: 238 / 255) : Palette.text
    }

    private var barInset: CGFloat { 8 * k }

    /// 长数字自动降级，保证左右各留 ≥ 6pt 的余量
    private var numberSize: CGFloat {
        let count = model.balanceText.count
        let base: CGFloat = count >= 6 ? 11 : (count == 5 ? 12.5 : 14)
        return base * k
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(bodyColor)

            if showsBar {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.track)
                        .frame(height: 2 * k)
                    if model.ringProgress > 0.001 {
                        Capsule()
                            .fill(accent)
                            .frame(width: (width - barInset * 2) * CGFloat(model.ringProgress), height: 2 * k)
                    }
                }
                .frame(width: width - barInset * 2, height: 2 * k)
                .padding(.bottom, 4.5 * k)
            }

            HStack(alignment: .firstTextBaseline, spacing: 1 * k) {
                if model.showsCurrencySymbol {
                    Text(model.currencySymbol)
                        .font(.system(size: numberSize * 0.7, weight: .semibold))
                        .opacity(0.85)
                }
                Text(model.balanceText)
                    .font(.system(size: numberSize, weight: .semibold))
                    .monospacedDigit()
                    .kerning(-0.3 * k)
            }
            .foregroundStyle(numberColor)
            .padding(.bottom, showsBar ? 6 * k : 0)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: width, height: height)
        .opacity(active ? 1 : idleOpacity)
        .scaleEffect(active ? 1.03 : 1)
        .animation(.easeOut(duration: 0.2), value: active)
        .animation(.easeOut(duration: 0.2), value: model.ringProgress)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 卡片

struct CardView: View {
    @ObservedObject var model: AppModel
    var onSettings: () -> Void
    var onRefresh: () -> Void
    var onOpenPlatform: () -> Void

    private var currency: String { model.currencySymbol }

    var body: some View {
        Group {
            if model.phase == .noKey {
                setupCard
            } else {
                normalCard
            }
        }
        .padding(14)
        .frame(width: 268, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Palette.cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Palette.cardLine, lineWidth: 1)
        )
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text("还没有配置 API Key")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.top, 10)
            Text("只读余额接口，Key 存在本机、仅当前用户可读")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.text3)
                .padding(.top, 3)
            Button(action: onSettings) {
                Text("填写 API Key")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.brand.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Palette.brand.opacity(0.36), lineWidth: 1)
                    )
                    .foregroundStyle(Color(red: 220 / 255, green: 228 / 255, blue: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private var hasData: Bool { model.snapshot != nil }

    private var normalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if hasData {
                balanceRow
            }
            if model.phase == .unauthorized {
                authError
            }
            if hasData {
                divider
                stats
                bars
                divider
                footer
            } else if model.phase == .loading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在读取余额…")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.text3)
                }
                .padding(.top, 14)
                .padding(.bottom, 4)
            }
            if model.cardPinned {
                actions
            }
        }
    }

    private var authError: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("!")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Palette.danger.opacity(0.22)))
                    .foregroundStyle(Color(red: 1, green: 194 / 255, blue: 194 / 255))
                VStack(alignment: .leading, spacing: 1) {
                    Text("API Key 无效或已过期")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 212 / 255, blue: 212 / 255))
                    Text("401 · 请在设置里重新填写")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.text3)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.danger.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.danger.opacity(0.22), lineWidth: 1)
            )

            Button(action: onSettings) {
                Text("重新填写 Key")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.brand.opacity(0.22))
                    )
                    .foregroundStyle(Color(red: 220 / 255, green: 228 / 255, blue: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("可用余额")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.text3)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(model.syncText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusTextColor)
                    .monospacedDigit()
            }
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .ok: return Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
        case .loading: return Palette.brand
        case .offline: return Color(red: 232 / 255, green: 178 / 255, blue: 90 / 255)
        case .unauthorized, .noKey: return Palette.danger
        }
    }

    private var statusTextColor: Color {
        switch model.phase {
        case .offline: return Palette.text3
        case .unauthorized, .noKey: return Palette.up
        default: return Palette.text3
        }
    }

    private var balanceRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currency)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.55)
                Text(model.snapshot.map { AppModel.money($0.total) } ?? "—")
                    .font(.system(size: 23, weight: .bold))
                    .monospacedDigit()
                    .kerning(-0.6)
            }
            .foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            Text("今日 −\(model.todayText)")
                .font(.system(size: 11.5))
                .foregroundStyle(model.spendToday > 0 ? Palette.up : Palette.text3)
                .monospacedDigit()
        }
        .padding(.top, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 11)
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 6) {
            stat("今天", model.todayText, model.todayDelta, current: model.spendToday, previous: model.prevToday)
            stat("近 7 天", model.sevenText, model.sevenDelta, current: model.spend7, previous: model.prev7)
            stat("近 30 天", model.thirtyText, model.spend30 > 0 ? model.average30Text : "—", current: 0, previous: 0, neutral: true)
        }
    }

    private func stat(_ label: String, _ value: String, _ note: String, current: Double, previous: Double, neutral: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.text3)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(currency)
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.5)
                Text(value.replacingOccurrences(of: currency, with: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .kerning(-0.3)
            }
            .foregroundStyle(Palette.text)
            Text(note)
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(noteColor(note, neutral: neutral))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noteColor(_ note: String, neutral: Bool) -> Color {
        guard !neutral else { return Palette.text3 }
        if note.hasPrefix("↑") { return Palette.up }
        if note.hasPrefix("↓") { return Palette.down }
        return Palette.text3
    }

    private var bars: some View {
        let maxValue = max(model.bars.max() ?? 0, 0.01)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(model.bars.enumerated()), id: \.offset) { index, value in
                let ratio = value / maxValue
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == model.bars.count - 1 ? Palette.brandSoft : Palette.brand.opacity(0.28))
                    .frame(height: 4 + 20 * ratio)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .padding(.top, 11)
    }

    private var footer: some View {
        HStack {
            Text("充值 \(model.toppedText)　赠金 \(model.grantedText)")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.text3)
                .monospacedDigit()
            Spacer(minLength: 6)
            Text(model.recordText)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.text3)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            actionButton("设置", primary: false, action: onSettings)
            actionButton("打开平台", primary: false, action: onOpenPlatform)
            actionButton("刷新", primary: true, action: onRefresh)
        }
        .padding(.top, 12)
    }

    private func actionButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(primary ? Palette.brand.opacity(0.24) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(primary ? Palette.brand.opacity(0.38) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(primary ? Color(red: 220 / 255, green: 228 / 255, blue: 1) : Palette.text2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 首次启动

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onDone: () -> Void
    var onQuit: () -> Void

    @State private var key = ""
    @State private var status: String?
    @State private var busy = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("连接你的 DeepSeek 账户")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text("Key 只保存在本机（仅当前用户可读），仅用于读取余额（只读接口 /user/balance），支持 ⌘V 粘贴。")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 16)

            Text("API KEY")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Palette.text3)
                .padding(.bottom, 5)

            HStack(spacing: 0) {
                SecureField("sk-...", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($keyFocused)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 9)
                    .foregroundStyle(Palette.text)

                Button(action: pasteKey) {
                    Text("粘贴")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                        .foregroundStyle(Palette.text2)
                }
                .buttonStyle(.plain)
                .help("从剪贴板粘贴 API Key（也可以直接按 ⌘V）")
                .padding(.trailing, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(keyFocused ? Palette.brand.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
            )

            if let status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(status.hasPrefix("验证通过") ? Palette.down : Palette.up)
                    .padding(.top, 9)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            HStack(spacing: 8) {
                Button(action: submit) {
                    Text(busy ? "验证中…" : "验证并使用")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            LinearGradient(colors: [Color(red: 92 / 255, green: 121 / 255, blue: 1), Color(red: 68 / 255, green: 89 / 255, blue: 232 / 255)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button(action: openKeyPage) {
                    Text("获取 Key")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .foregroundStyle(Palette.text2)
                }
                .buttonStyle(.plain)
            }

            Button(action: onQuit) {
                Text("稍后再说，退出")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.text3)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(22)
        .frame(width: 420, height: 268, alignment: .topLeading)
        .onAppear { keyFocused = true }
        .background(Color(red: 16 / 255, green: 20 / 255, blue: 30 / 255))
    }

    private func submit() {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "请先粘贴 API Key"
            return
        }
        busy = true
        status = nil
        Task {
            let result = await model.validate(key: key)
            if let result, result.hasPrefix("验证通过") {
                model.saveKey(key)
                status = result
                try? await Task.sleep(nanoseconds: 350_000_000)
                onDone()
            } else {
                status = result ?? "验证失败"
            }
            busy = false
        }
    }

    private func pasteKey() {
        if let text = NSPasteboard.general.string(forType: .string) {
            key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            keyFocused = true
        }
    }

    private func openKeyPage() {
        if let url = URL(string: "https://platform.deepseek.com/api_keys") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onChange: () -> Void

    @AppStorage("refreshMinutes") private var refreshMinutes = 5
    @AppStorage("budgetEnabled") private var budgetEnabled = true
    @AppStorage("dailyBudget") private var dailyBudget = 10.0
    @AppStorage("widgetHeight") private var widgetHeight = 35.0
    @AppStorage("idleOpacity") private var idleOpacity = 0.5
    @AppStorage("hideInFullscreen") private var hideInFullscreen = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var keyField = ""
    @State private var keyStatus: String?
    @State private var launchError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("账户")
                row("API Key", detail: model.maskedKey) {
                    HStack(spacing: 6) {
                        HStack(spacing: 0) {
                            SecureField("sk-...", text: $keyField)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, design: .monospaced))
                                .padding(.leading, 9)
                                .padding(.trailing, 4)
                                .padding(.vertical, 7)
                                .foregroundStyle(Palette.text)
                            Button("粘贴") { pasteIntoField() }
                                .buttonStyle(PasteChip())
                                .help("从剪贴板粘贴（也可以直接按 ⌘V）")
                                .padding(.trailing, 4)
                        }
                        .frame(width: 156)
                        .background(roundedField)
                        Button("保存") { saveKey() }
                            .buttonStyle(CompactButton())
                    }
                }
                if let keyStatus {
                    Text(keyStatus)
                        .font(.system(size: 10.5))
                        .foregroundStyle(keyStatus.hasPrefix("验证通过") ? Palette.down : Palette.up)
                        .padding(.leading, 150)
                        .padding(.bottom, 6)
                }

                row("刷新间隔") {
                    Picker("", selection: $refreshMinutes) {
                        Text("1 分").tag(1)
                        Text("5 分").tag(5)
                        Text("15 分").tag(15)
                        Text("30 分").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    .onChange(of: refreshMinutes) { _ in model.applyPrefsChange() }
                }

                sectionTitle("外观")
                row("今日预算环", detail: "环 = 今日花费 / 预算") {
                    HStack(spacing: 8) {
                        TextField("", value: $dailyBudget, format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .frame(width: 64)
                            .background(roundedField)
                            .foregroundStyle(Palette.text)
                        Toggle("", isOn: $budgetEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    .onChange(of: budgetEnabled) { _ in onChange() }
                    .onChange(of: dailyBudget) { _ in onChange() }
                }
                row("挂件尺寸", detail: "31 / 35 / 39 是高，宽按 1.9 倍推导") {
                    Picker("", selection: $widgetHeight) {
                        Text("31").tag(31.0)
                        Text("35").tag(35.0)
                        Text("39").tag(39.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                    .onChange(of: widgetHeight) { _ in onChange() }
                }
                row("静止不透明度") {
                    Picker("", selection: $idleOpacity) {
                        Text("50%").tag(0.5)
                        Text("70%").tag(0.7)
                        Text("100%").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    .onChange(of: idleOpacity) { _ in onChange() }
                }
                row("全屏 App 中隐藏") {
                    Toggle("", isOn: $hideInFullscreen)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: hideInFullscreen) { _ in onChange() }
                }

                sectionTitle("系统")
                row("开机自动启动") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: launchAtLogin) { value in
                            LoginItem.set(value) { err in
                                launchError = err
                                if err != nil { launchAtLogin = LoginItem.isEnabled }
                            }
                        }
                }
                if let launchError {
                    Text(launchError)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.up)
                        .padding(.leading, 150)
                }

                row("本地数据") {
                    HStack(spacing: 6) {
                        Button("导出 CSV") { exportCSV() }
                            .buttonStyle(CompactButton())
                        Button("清空历史") { clearHistory() }
                            .buttonStyle(CompactButton())
                    }
                }

                Divider().padding(.vertical, 10).opacity(0.25)
                Text("DeepSeek Meter 0.1.0 · 余额接口仅只读；用量按余额差值估算")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.text3)
            }
            .padding(20)
        }
        .frame(width: 440, height: 560)
        .background(Color(red: 17 / 255, green: 21 / 255, blue: 31 / 255))
        .onAppear { keyField = SecretStore.load() ?? "" }
    }

    private var roundedField: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.text3)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text2)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.text3)
                }
            }
            Spacer(minLength: 12)
            content()
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private func pasteIntoField() {
        if let text = NSPasteboard.general.string(forType: .string) {
            keyField = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func saveKey() {
        let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { keyStatus = "请先填写 API Key"; return }
        keyStatus = "验证中…"
        Task {
            let result = await model.validate(key: trimmed)
            keyStatus = result
            if result?.hasPrefix("验证通过") == true {
                model.saveKey(trimmed)
                await model.refresh()
                onChange()
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "deepseek-usage.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url {
            try? model.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空本地用量记录？"
        alert.informativeText = "只会删除本机的采样数据，不影响账户余额。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Store().clearAll()
            model.recompute()
        }
    }
}

struct PasteChip: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .foregroundStyle(Palette.text2)
    }
}

struct CompactButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .foregroundStyle(Palette.text2)
    }
}
