import Foundation
import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case noKey
        case loading
        case ok
        case offline
        case unauthorized
    }

    // MARK: 状态

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: BalanceSnapshot?
    @Published private(set) var lastSync: Date?
    @Published private(set) var errorText: String?

    @Published private(set) var spendToday: Double = 0
    @Published private(set) var spend7: Double = 0
    @Published private(set) var spend30: Double = 0
    @Published private(set) var prevToday: Double = 0
    @Published private(set) var prev7: Double = 0
    @Published private(set) var prev30: Double = 0
    @Published private(set) var bars: [Double] = Array(repeating: 0, count: 7)
    @Published private(set) var recordedDays: Int = 0

    // UI 状态（AppKit 侧驱动）
    @Published var hovering = false
    @Published var cardVisible = false
    @Published var cardPinned = false
    @Published var dragging = false
    @Published var settingsOpen = false

    let prefs = Prefs.shared
    private let api = BalanceAPI()
    private let store = Store()

    private var timer: Timer?
    private var retryTask: Task<Void, Never>?
    private var isRefreshing = false
    private var failures = 0
    private let preview: Bool

    // MARK: 初始化

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            snapshot = BalanceSnapshot(currency: "CNY", total: 82.40, granted: 0, topped: 100, available: true)
            lastSync = Date()
            phase = .ok
            spendToday = 1.23; spend7 = 8.90; spend30 = 34.12
            prevToday = 1.10; prev7 = 9.27; prev30 = 30.5
            recordedDays = 12
            bars = [2.1, 3.2, 2.6, 4.3, 3.0, 5.1, 1.23]
            return
        }
        loadCachedBalance()
        recompute()
        if !hasKey {
            phase = .noKey
        } else if snapshot == nil {
            phase = .loading
        }
    }

    deinit {
        timer?.invalidate()
        retryTask?.cancel()
    }

    // MARK: 生命周期

    func start() {
        guard !preview else { return }
        observeWake()
        scheduleTimer()
        Task { await refresh() }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, prefs.refreshMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func applyPrefsChange() {
        guard !preview else { return }
        scheduleTimer()
        objectWillChange.send()
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: Key

    /// 测试用：DSB_FAKE_KEY 可覆盖钥匙串里的 Key（只读，不会保存）
    private var resolvedKey: String? {
        if let fake = ProcessInfo.processInfo.environment["DSB_FAKE_KEY"], !fake.isEmpty { return fake }
        return SecretStore.load()
    }

    var hasKey: Bool { resolvedKey != nil }

    var maskedKey: String {
        guard let key = SecretStore.load(), key.count > 8 else { return "未填写" }
        return "sk-••••••••\(key.suffix(4))"
    }

    func saveKey(_ key: String) {
        SecretStore.save(key)
        prefs.hasOnboarded = true
        failures = 0
    }

    func validate(key: String) async -> String? {
        do {
            let snap = try await api.fetch(key: key.trimmingCharacters(in: .whitespacesAndNewlines))
            return "验证通过 · 当前余额 ¥\(Self.money(snap.total)) \(snap.currency)"
        } catch {
            return (error as? MeterError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: 拉取

    func refresh() async {
        guard !preview, !isRefreshing else { return }
        guard let key = resolvedKey else {
            phase = .noKey
            return
        }
        isRefreshing = true
        if snapshot == nil { phase = .loading }
        defer { isRefreshing = false }

        do {
            let snap = try await api.fetch(key: key)
            failures = 0
            errorText = nil
            snapshot = snap
            lastSync = Date()
            phase = .ok
            store.insert(snapshot: snap)
            persist(balance: snap)
            recompute()
            NSLog("[DeepSeekMeter] balance ok: \(snap.currency) \(snap.total)")
            isLow = snap.total > 0 && snap.total < 5
        } catch let err as MeterError {
            failures += 1
            errorText = err.errorDescription
            NSLog("[DeepSeekMeter] balance error: \(err.errorDescription ?? "?")")
            switch err {
            case .unauthorized:
                phase = .unauthorized
            case .noKey:
                phase = .noKey
            default:
                phase = snapshot == nil ? .offline : .offline
            }
            scheduleRetry()
        } catch {
            failures += 1
            errorText = error.localizedDescription
            phase = .offline
            scheduleRetry()
        }
    }

    @Published private(set) var isLow = false

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = min(300.0, 15.0 * pow(2.0, Double(failures - 1)))
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: 缓存余额（离线时也有旧值可看）

    private func persist(balance snap: BalanceSnapshot) {
        let d = UserDefaults.standard
        d.set(snap.total, forKey: "cache.total")
        d.set(snap.granted, forKey: "cache.granted")
        d.set(snap.topped, forKey: "cache.topped")
        d.set(snap.currency, forKey: "cache.currency")
        d.set(Date().timeIntervalSince1970, forKey: "cache.ts")
    }

    private func loadCachedBalance() {
        let d = UserDefaults.standard
        guard d.object(forKey: "cache.ts") != nil else { return }
        let snap = BalanceSnapshot(
            currency: d.string(forKey: "cache.currency") ?? "CNY",
            total: d.double(forKey: "cache.total"),
            granted: d.double(forKey: "cache.granted"),
            topped: d.double(forKey: "cache.topped"),
            available: true
        )
        snapshot = snap
        isLow = snap.total > 0 && snap.total < 5
        lastSync = Date(timeIntervalSince1970: d.double(forKey: "cache.ts"))
        phase = .ok
    }

    // MARK: 聚合

    func recompute() {
        let daily = store.dailySpend()
        recordedDays = store.recordedDays()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func sum(_ from: Int, _ to: Int) -> Double {
            var total = 0.0
            for offset in from...to {
                guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                total += daily[cal.startOfDay(for: day)] ?? 0
            }
            return total
        }
        spendToday = daily[today] ?? 0
        spend7 = sum(0, 6)
        spend30 = sum(0, 29)
        prevToday = daily[cal.date(byAdding: .day, value: -1, to: today) ?? today] ?? 0
        prev7 = sum(7, 13)
        prev30 = sum(30, 59)

        var series: [Double] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            if let day = cal.date(byAdding: .day, value: -offset, to: today) {
                series.append(daily[cal.startOfDay(for: day)] ?? 0)
            } else {
                series.append(0)
            }
        }
        bars = series
    }

    // MARK: 展示

    var balanceText: String {
        guard let snap = snapshot else { return "···" }
        return Self.compact(snap.total)
    }

    var balanceFontSize: CGFloat {
        let n = balanceText.count
        if n >= 6 { return 12 }
        if n == 5 { return 13.5 }
        return 15
    }

    var showsCurrencySymbol: Bool { snapshot != nil }

    var currencySymbol: String {
        (snapshot?.currency ?? "CNY") == "USD" ? "$" : "¥"
    }

    var todayText: String { "\(currencySymbol)\(Self.money(spendToday))" }
    var sevenText: String { "\(currencySymbol)\(Self.money(spend7))" }
    var thirtyText: String { "\(currencySymbol)\(Self.money(spend30))" }

    var todayDelta: String { Self.delta(spendToday, prevToday) }
    var sevenDelta: String { Self.delta(spend7, prev7) }
    var thirtyDelta: String { Self.delta(spend30, prev30) }

    var average30Text: String { "日均 \(Self.money(spend30 / 30))" }

    var budgetProgress: Double {
        guard prefs.budgetEnabled, prefs.dailyBudget > 0 else { return 0 }
        return min(1, max(0, spendToday / prefs.dailyBudget))
    }

    var ringProgress: Double {
        guard prefs.budgetEnabled else { return 0 }
        return budgetProgress
    }

    var syncText: String {
        guard let lastSync else { return "尚未同步" }
        let seconds = Date().timeIntervalSince(lastSync)
        if phase == .offline { return "离线 · \(Self.ago(seconds))" }
        if seconds < 60 { return "刚刚更新" }
        return "\(Self.ago(seconds))"
    }

    var toppedText: String {
        guard let snap = snapshot else { return "—" }
        return "\(currencySymbol)\(Self.money(snap.topped))"
    }

    var grantedText: String {
        guard let snap = snapshot else { return "—" }
        return "\(currencySymbol)\(Self.money(snap.granted))"
    }

    var recordText: String { recordedDays > 0 ? "记录 \(recordedDays) 天" : "刚开始记录" }

    // MARK: 格式化

    static func money(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    static func compact(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(format: "%.1f", v)
    }

    static func delta(_ current: Double, _ previous: Double) -> String {
        guard previous > 0.005 else { return "—" }
        let change = (current - previous) / previous
        let pct = Int((abs(change) * 100).rounded())
        if pct == 0 { return "持平" }
        return change > 0 ? "↑ \(pct)%" : "↓ \(pct)%"
    }

    static func ago(_ seconds: TimeInterval) -> String {
        if seconds < 120 { return "1 分钟前" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86400)) 天前"
    }

    func exportCSV() -> String { store.exportCSV() }
}
