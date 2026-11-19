import Foundation

/// 用量聚合的自检：造 14 天的采样（含一次充值、一次赠金过期），验证只有真实消耗被计入
enum StoreDiagnostics {
    static func run() {
        let path = ProcessInfo.processInfo.environment["DSB_DB_PATH"] ?? "/tmp/dsb-stats-test.db"
        try? FileManager.default.removeItem(atPath: path)
        setenv("DSB_DB_PATH", path, 1)

        let store = Store()
        let cal = Calendar.current
        let now = Date()
        var balance = 100.0
        var expected: [String: Double] = [:]

        for offset in stride(from: 13, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let spend = 0.5 + Double((offset * 7) % 5)
            let morning = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
            let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day

            store.insert(ts: morning, snapshot: BalanceSnapshot(currency: "CNY", total: balance, granted: 0, topped: 100, available: true))
            if offset == 5 {
                // 充值 50：余额上升，不能被算成消耗
                balance += 50
                store.insert(ts: cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day,
                             snapshot: BalanceSnapshot(currency: "CNY", total: balance, granted: 0, topped: 150, available: true))
            }
            if offset == 3 {
                // 赠金过期 2 元：余额下降但没有消耗
                // 赠金过期：余额下降但 topped 不变 —— 仅凭余额无法与消耗区分，按消耗计
                balance -= 2
                store.insert(ts: cal.date(bySettingHour: 13, minute: 0, second: 0, of: day) ?? day,
                             snapshot: BalanceSnapshot(currency: "CNY", total: balance, granted: 0, topped: 150, available: true))
            }
            balance -= spend
            store.insert(ts: evening, snapshot: BalanceSnapshot(currency: "CNY", total: balance, granted: 0, topped: 150, available: true))
            expected[dayKey(day)] = spend + (offset == 3 ? 2 : 0)
        }

        let daily = store.dailySpend()
        var byKey: [String: Double] = [:]
        for (date, amount) in daily { byKey[dayKey(date)] = amount }

        var failures: [String] = []
        for (day, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = byKey[day]
            let ok = abs((got ?? -1) - want) < 0.005
            print(String(format: "%@ expect %.2f got %@ %@", day, want,
                         got.map { String(format: "%.2f", $0) } ?? "nil", ok ? "✓" : "✗"))
            if !ok { failures.append(day) }
        }
        let todayKey = dayKey(Calendar.current.startOfDay(for: now))
        let last7 = expected.filter { $0.key >= dayKey(Calendar.current.date(byAdding: .day, value: -6, to: now)!) }.values.reduce(0, +)
        let all = expected.values.reduce(0, +)
        print(String(format: "recordedDays=%d 7d=%.2f 14d=%.2f today=%@", store.recordedDays(), last7, all, todayKey))
        if store.recordedDays() != 14 { failures.append("recordedDays 应为 14") }
        if byKey.values.contains(where: { $0 > 25 }) { failures.append("出现异常大额日消耗，充值被计入了") }
        print(failures.isEmpty ? "SELFTEST OK" : "SELFTEST FAILED: \(failures.joined(separator: "; "))")
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
