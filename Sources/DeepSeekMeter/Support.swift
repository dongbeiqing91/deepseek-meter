import Foundation
import ServiceManagement

// MARK: - 旧版本数据迁移

enum LegacyMigration {
    /// 从 DeepSeekMeter 改名过来：把 Application Support 目录整体搬过去，Key 和用量历史都不丢
    static func run() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent("DeepSeekMeter", isDirectory: true)
        let new = base.appendingPathComponent("DeepSeekMeter", isDirectory: true)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            NSLog("[DeepSeekMeter] migrated data directory")
        } catch {
            NSLog("[DeepSeekMeter] migrate failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - 开机启动

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool, completion: @escaping (String?) -> Void) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            completion(nil)
        } catch {
            completion("开机启动设置失败：\(error.localizedDescription)")
        }
    }
}
