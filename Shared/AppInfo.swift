import Foundation

/// 应用级常量：App 与 Widget 共享，两边都用同一套路径与标识。
public enum AppInfo {

    /// 真实 home 目录。
    /// Widget 扩展运行在 App Sandbox 里，`NSHomeDirectory()` / `.applicationSupportDirectory`
    /// 会被重定向到 `~/Library/Containers/<bundle id>/Data`，因此这里绕开 Foundation 的
    /// 用户目录 API，直接取 passwd 里的 home，保证 App 与 Widget 落在同一个路径。
    public static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// 数据目录：~/Library/Application Support/Memo
    public static var dataDirectory: URL {
        realHomeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Memo", isDirectory: true)
    }

    public static var storeURL: URL { dataDirectory.appendingPathComponent("store.json") }
    public static var backupURL: URL { dataDirectory.appendingPathComponent("store.json.bak") }
    public static var exportDirectory: URL { dataDirectory.appendingPathComponent("export", isDirectory: true) }
}
