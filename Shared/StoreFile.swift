import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 纯 IO 层：不依赖 SwiftUI / 观察机制，App、Widget、AppIntent、测试共用。
public enum StoreFile {

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
    }

    public static func quarantineURL(for url: URL) -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
    }

    public struct LoadResult {
        public var data: StoreData
        /// 非 nil 表示发生过异常，需要提示用户
        public var problem: String?

        public init(data: StoreData, problem: String? = nil) {
            self.data = data
            self.problem = problem
        }
    }

    /// 读取：主文件 → 备份 → 空库
    public static func loadResult(from url: URL = AppInfo.storeURL) -> LoadResult {
        let decoder = decoder()

        if let bytes = try? Data(contentsOf: url) {
            if let data = try? decoder.decode(StoreData.self, from: bytes) {
                return LoadResult(data: data)
            }
            // 主文件损坏：留档
            try? FileManager.default.moveItem(at: url, to: quarantineURL(for: url))
            if let backupBytes = try? Data(contentsOf: backupURL(for: url)),
               let backup = try? decoder.decode(StoreData.self, from: backupBytes) {
                return LoadResult(data: backup, problem: "数据文件损坏，已从备份恢复")
            }
            return LoadResult(data: StoreData(), problem: "数据文件损坏且无可用备份，已重建空库（原文件已留档）")
        }

        return LoadResult(data: StoreData())
    }

    public static func load(from url: URL = AppInfo.storeURL) -> StoreData {
        loadResult(from: url).data
    }

    /// 原子写入 + 保留一份上一版备份
    @discardableResult
    public static func save(_ data: StoreData, to url: URL = AppInfo.storeURL) -> Error? {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let bytes = try encoder().encode(data)
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".tmp")
            try bytes.write(to: tmp, options: .atomic)

            if FileManager.default.fileExists(atPath: url.path) {
                let backup = backupURL(for: url)
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: url, to: backup)
            }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            return nil
        } catch {
            return error
        }
    }

    /// 组件内直接勾选任务（不需要 App 进程）
    @discardableResult
    public static func toggleTask(dayKey: String, taskID: UUID, at url: URL = AppInfo.storeURL) -> Bool {
        var data = load(from: url)
        guard var entry = data.days[dayKey],
              let idx = entry.tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        entry.tasks[idx].done.toggle()
        entry.updatedAt = Date()
        data.days[dayKey] = entry
        save(data, to: url)
        notifyWidgets()
        return true
    }

    public static func notifyWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
