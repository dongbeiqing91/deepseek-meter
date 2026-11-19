import Foundation
import SQLite3

// MARK: - 设置

final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    private enum Key {
        static let refresh = "refreshMinutes"
        static let budgetOn = "budgetEnabled"
        static let budget = "dailyBudget"
        static let size = "widgetHeight"
        static let idle = "idleOpacity"
        static let hideFullscreen = "hideInFullscreen"
        static let origin = "widgetOrigin"
        static let onboarded = "hasOnboarded"
    }

    var refreshMinutes: Int {
        get { d.object(forKey: Key.refresh) as? Int ?? 5 }
        set { d.set(newValue, forKey: Key.refresh) }
    }

    var budgetEnabled: Bool {
        get { d.object(forKey: Key.budgetOn) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.budgetOn) }
    }

    var dailyBudget: Double {
        get { d.object(forKey: Key.budget) as? Double ?? 10 }
        set { d.set(newValue, forKey: Key.budget) }
    }

    var widgetHeight: CGFloat {
        get { CGFloat(d.object(forKey: Key.size) as? Double ?? 35) }
        set { d.set(Double(newValue), forKey: Key.size) }
    }

    /// 静止时不透明度：0.5 / 0.7 / 1.0
    var idleOpacity: Double {
        get { d.object(forKey: Key.idle) as? Double ?? 0.5 }
        set { d.set(newValue, forKey: Key.idle) }
    }

    var hideInFullscreen: Bool {
        get { d.object(forKey: Key.hideFullscreen) as? Bool ?? false }
        set { d.set(newValue, forKey: Key.hideFullscreen) }
    }

    var widgetOrigin: CGPoint? {
        get {
            guard let s = d.string(forKey: Key.origin) else { return nil }
            let parts = s.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let p = newValue {
                d.set("\(Int(p.x.rounded())),\(Int(p.y.rounded()))", forKey: Key.origin)
            } else {
                d.removeObject(forKey: Key.origin)
            }
        }
    }

    var hasOnboarded: Bool {
        get { d.bool(forKey: Key.onboarded) }
        set { d.set(newValue, forKey: Key.onboarded) }
    }
}

// MARK: - 余额接口

struct BalanceSnapshot {
    let currency: String
    let total: Double
    let granted: Double
    let topped: Double
    let available: Bool
}

enum MeterError: LocalizedError, Equatable {
    case noKey
    case unauthorized
    case rateLimited
    case http(Int)
    case network(String)
    case decode

    var errorDescription: String? {
        switch self {
        case .noKey: return "还没有填写 API Key"
        case .unauthorized: return "API Key 无效或已过期"
        case .rateLimited: return "请求太频繁（429）"
        case .http(let code): return "服务返回 \(code)"
        case .network(let msg): return msg
        case .decode: return "返回内容解析失败"
        }
    }
}

struct BalanceAPI {
    private struct Response: Decodable {
        struct Info: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String
            let topped_up_balance: String
        }
        let is_available: Bool?
        let balance_infos: [Info]
    }

    func fetch(key: String) async throws -> BalanceSnapshot {
        guard var comps = URLComponents(string: "https://api.deepseek.com/user/balance") else {
            throw MeterError.decode
        }
        comps.query = nil
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let ns = error as NSError
            NSLog("[DeepSeekMeter] fetch failed domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
            throw MeterError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw MeterError.decode }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw MeterError.unauthorized
        case 429:
            throw MeterError.rateLimited
        default:
            throw MeterError.http(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw MeterError.decode
        }
        // 优先人民币
        let infos = decoded.balance_infos
        guard let info = infos.first(where: { $0.currency.uppercased() == "CNY" }) ?? infos.first else {
            throw MeterError.decode
        }
        return BalanceSnapshot(
            currency: info.currency.uppercased(),
            total: Double(info.total_balance) ?? 0,
            granted: Double(info.granted_balance) ?? 0,
            topped: Double(info.topped_up_balance) ?? 0,
            available: decoded.is_available ?? true
        )
    }
}

// MARK: - 本地采样（SQLite）

final class Store {
    private var db: OpaquePointer?
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeekMeter", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir.appendingPathComponent("usage.db")
        if let override = ProcessInfo.processInfo.environment["DSB_DB_PATH"], !override.isEmpty {
            url = URL(fileURLWithPath: override)
        }
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            NSLog("[DeepSeekMeter] sqlite open failed: \(url.path)")
            db = nil
            return
        }
        exec("""
        CREATE TABLE IF NOT EXISTS sample (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            total REAL NOT NULL,
            granted REAL NOT NULL,
            topped REAL NOT NULL,
            currency TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sample_ts ON sample(ts);
        """)
    }

    deinit { if let db { sqlite3_close(db) } }

    private func exec(_ sql: String) {
        guard let db else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            NSLog("[DeepSeekMeter] sqlite exec failed: \(String(cString: err ?? UnsafeMutablePointer(mutating: "")))")
            sqlite3_free(err)
        }
    }

    func insert(ts: Date = Date(), snapshot: BalanceSnapshot) {
        guard let db else { return }
        let sql = "INSERT INTO sample (ts, total, granted, topped, currency) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(ts.timeIntervalSince1970))
        sqlite3_bind_double(stmt, 2, snapshot.total)
        sqlite3_bind_double(stmt, 3, snapshot.granted)
        sqlite3_bind_double(stmt, 4, snapshot.topped)
        // SQLITE_STATIC：指针在 step 期间有效，避免依赖 C 的 transient 常量
        snapshot.currency.withCString { ptr in
            sqlite3_bind_text(stmt, 5, ptr, -1, nil)
            sqlite3_step(stmt)
        }
    }

    /// 每个自然日的消耗（余额差值，正差值才算消耗）
    func dailySpend() -> [Date: Double] {
        guard let db else { return [:] }
        // prev - total > 0 才累加；充值与赠金过期不会污染
        let sql = """
        WITH s AS (
          SELECT ts, total, LAG(total) OVER (ORDER BY ts) AS prev FROM sample ORDER BY ts
        )
        SELECT strftime('%Y-%m-%d', ts, 'unixepoch', 'localtime') AS d,
               SUM(CASE WHEN prev IS NOT NULL AND prev > total THEN prev - total ELSE 0 END) AS spent
        FROM s GROUP BY d;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var out: [Date: Double] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cstr = sqlite3_column_text(stmt, 0) else { continue }
            let day = String(cString: cstr)
            let amount = sqlite3_column_double(stmt, 1)
            if let date = dayFormatter.date(from: day) {
                out[Calendar.current.startOfDay(for: date)] = amount
            }
        }
        return out
    }

    /// 记录了多少天（有采样的自然日）
    func recordedDays() -> Int {
        guard let db else { return 0 }
        let sql = "SELECT COUNT(DISTINCT strftime('%Y-%m-%d', ts, 'unixepoch', 'localtime')) FROM sample"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// 实时消耗：最近一次采样到当前（用于卡片打开时的“今日已用”）
    func lastSample() -> (ts: Date, total: Double)? {
        guard let db else { return nil }
        let sql = "SELECT ts, total FROM sample ORDER BY ts DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let ts = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)))
        return (ts, sqlite3_column_double(stmt, 1))
    }

    func clearAll() {
        exec("DELETE FROM sample;")
    }

    func exportCSV() -> String {
        guard let db else { return "" }
        let sql = "SELECT ts, total, granted, topped, currency FROM sample ORDER BY ts"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "" }
        defer { sqlite3_finalize(stmt) }
        var lines = ["time,balance,granted,topped,currency"]
        let f = ISO8601DateFormatter()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)))
            let cur = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            lines.append("\(f.string(from: ts)),\(sqlite3_column_double(stmt, 1)),\(sqlite3_column_double(stmt, 2)),\(sqlite3_column_double(stmt, 3)),\(cur)")
        }
        return lines.joined(separator: "\n")
    }
}
