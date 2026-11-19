import Foundation

/// API Key 存储
///
/// 不用钥匙串：ad-hoc 签名的 App 每次重建 cdhash 都变，钥匙串 ACL 会反复弹
/// “想使用你的机密信息…”并要求输入登录密码。这里退回到 0600 权限的本地文件，
/// 只有当前用户可读；Key 本身只能读余额，不能调用任何写接口。
enum SecretStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeekMeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var fileURL: URL { directory.appendingPathComponent("api.key") }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? Data(trimmed.utf8).write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 自检：写入 → 读取 → 权限位 → 删除
    static func selfTest() -> String {
        save("dsb-test-value")
        let ok = load() == "dsb-test-value"
        let perms = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let existing = load()
        if existing == "dsb-test-value" { clear() }
        return ok && perms == 0o600 ? "ok" : "failed (read=\(ok) perms=\(String(perms, radix: 8)))"
    }
}
