import Foundation
import Observation

/// App 侧的可观察数据仓库：内存态 + 300ms 防抖落盘。
@MainActor
@Observable
public final class Store {

    public static let shared = Store()

    public private(set) var data: StoreData
    public private(set) var lastError: String?
    public private(set) var lastSavedAt: Date?

    public let url: URL
    private var pendingSave: Task<Void, Never>?

    public init(url: URL = AppInfo.storeURL) {
        self.url = url
        let result = StoreFile.loadResult(from: url)
        self.data = result.data
        self.lastError = result.problem
        ensureAnchor()
    }

    // MARK: - 读取

    public func dayEntry(_ key: String) -> DayEntry? {
        data.days[key]
    }

    public func tasks(for date: Date) -> [PlanTask] {
        data.days[CalendarMath.dateKey(date)]?.tasks ?? []
    }

    public func weekEntry(_ weekKey: String) -> WeekEntry? {
        data.weeks[weekKey]
    }

    public func daySnapshot(for date: Date, today: Date = Date()) -> DaySnapshot {
        CalendarMath.daySnapshot(for: date, data: data, today: today)
    }

    public func weekSnapshot(containing date: Date, today: Date = Date()) -> WeekSnapshot {
        CalendarMath.weekSnapshot(containing: date, data: data, today: today)
    }

    public func monthStats(for month: Date, today: Date = Date()) -> MonthStats {
        CalendarMath.monthStats(for: month, data: data, today: today)
    }

    /// 本周实际上班天数（已计入单日例外）
    public func workdays(forWeekContaining date: Date) -> Int {
        CalendarMath.effectiveWorkdays(inWeekContaining: date, data: data).count
    }

    /// 本周「基准」上班天数（不含单日例外），用于设置页预览
    public func baseWorkdays(forWeekContaining date: Date) -> Int {
        let key = CalendarMath.weekKey(date)
        return CalendarMath.workdays(forWeekContaining: date,
                                     settings: data.settings,
                                     override: data.weeks[key]?.workdaysOverride)
    }

    public var dayOverrideCount: Int { data.dayOverrides.count }

    // MARK: - 写入

    public func updateDay(_ key: String, _ mutate: (inout DayEntry) -> Void) {
        var entry = data.days[key] ?? DayEntry()
        mutate(&entry)
        entry.updatedAt = Date()
        if entry.isEmpty {
            data.days.removeValue(forKey: key)
        } else {
            data.days[key] = entry
        }
        scheduleSave()
    }

    public func updateWeek(_ weekKey: String, _ mutate: (inout WeekEntry) -> Void) {
        var entry = data.weeks[weekKey] ?? WeekEntry()
        mutate(&entry)
        entry.updatedAt = Date()
        if entry.isEmpty {
            data.weeks.removeValue(forKey: weekKey)
        } else {
            data.weeks[weekKey] = entry
        }
        scheduleSave()
    }

    @discardableResult
    public func addTask(to date: Date, text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = PlanTask(text: trimmed)
        updateDay(CalendarMath.dateKey(date)) { $0.tasks.append(task) }
        return task.id
    }

    public func toggleTask(_ date: Date, taskID: UUID) {
        updateDay(CalendarMath.dateKey(date)) { entry in
            if let idx = entry.tasks.firstIndex(where: { $0.id == taskID }) {
                entry.tasks[idx].done.toggle()
            }
        }
    }

    /// 改计划文字；改成空白等于删除
    public func updateTaskText(_ date: Date, taskID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateDay(CalendarMath.dateKey(date)) { entry in
            guard let index = entry.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            if trimmed.isEmpty {
                entry.tasks.remove(at: index)
            } else {
                entry.tasks[index].text = trimmed
            }
        }
    }

    public func deleteTask(_ date: Date, taskID: UUID) {
        updateDay(CalendarMath.dateKey(date)) { entry in
            entry.tasks.removeAll { $0.id == taskID }
        }
    }

    public func moveTasks(in date: Date, from source: IndexSet, to destination: Int) {
        updateDay(CalendarMath.dateKey(date)) { entry in
            entry.tasks.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// 把某个任务移到另一个任务之前（拖拽排序）
    public func moveTask(in date: Date, taskID: UUID, before targetID: UUID) {
        guard taskID != targetID else { return }
        updateDay(CalendarMath.dateKey(date)) { entry in
            guard let from = entry.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            let task = entry.tasks.remove(at: from)
            if let to = entry.tasks.firstIndex(where: { $0.id == targetID }) {
                entry.tasks.insert(task, at: to)
            } else {
                entry.tasks.append(task)
            }
        }
    }

    public func updateSettings(_ mutate: (inout Settings) -> Void) {
        mutate(&data.settings)
        if data.settings.bigWeekAnchor.isEmpty {
            data.settings.bigWeekAnchor = CalendarMath.weekKey(Date())
        }
        scheduleSave()
    }

    public func setWorkdaysOverride(weekKey: String, value: Int?) {
        updateWeek(weekKey) { $0.workdaysOverride = value }
    }

    /// 标记某天为例外（nil 表示恢复跟随规则）
    public func setDayOverride(_ date: Date, value: DayOverride?) {
        let key = CalendarMath.dateKey(date)
        if let value {
            data.dayOverrides[key] = value
        } else {
            data.dayOverrides.removeValue(forKey: key)
        }
        scheduleSave()
    }

    public func clearDayOverrides() {
        data.dayOverrides.removeAll()
        scheduleSave()
    }

    public func setWeekSummary(weekKey: String, text: String) {
        updateWeek(weekKey) { $0.summary = text }
    }

    // MARK: - 落盘

    private func ensureAnchor() {
        if data.settings.bigWeekAnchor.isEmpty {
            data.settings.bigWeekAnchor = CalendarMath.weekKey(Date())
        }
    }

    private func scheduleSave() {
        lastError = nil
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// 立即落盘（关闭窗口、进入后台、测试时调用）
    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        if let error = StoreFile.save(data, to: url) {
            lastError = "保存失败：\(error.localizedDescription)"
        } else {
            lastSavedAt = Date()
            lastError = nil
        }
        StoreFile.notifyWidgets()
    }

    // MARK: - 导出

    /// 按月导出 Markdown，返回文件路径
    @discardableResult
    public func exportMarkdown(month: Date) -> URL? {
        let grid = CalendarMath.monthGrid(for: month).filter(\.isInCurrentMonth)
        let monthTitle = CalendarMath.monthTitle(month)
        var lines: [String] = ["# \(monthTitle)", ""]

        for day in grid {
            guard let entry = data.days[day.key], !entry.isEmpty else { continue }
            lines.append("## \(CalendarMath.dayTitle(day.date))")
            lines.append("")
            let summary = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                lines.append(summary)
                lines.append("")
            }
            if !entry.tasks.isEmpty {
                for task in entry.tasks {
                    lines.append("- [\(task.done ? "x" : " ")] \(task.text)")
                }
                lines.append("")
            }
        }

        let weekKeys = Set(grid.map { CalendarMath.weekKey($0.date) }).sorted()
        let weekSections = weekKeys.compactMap { key -> String? in
            guard let week = data.weeks[key],
                  !week.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "## \(key) 周总结\n\n\(week.summary)\n"
        }
        if !weekSections.isEmpty {
            lines.append("# 周总结")
            lines.append("")
            lines.append(contentsOf: weekSections)
        }

        let text = lines.joined(separator: "\n")
        let dir = AppInfo.exportDirectory
        let comps = CalendarMath.calendar.dateComponents([.year, .month], from: month)
        let filename = String(format: "%04d-%02d.md", comps.year ?? 0, comps.month ?? 0)
        let fileURL = dir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }
}
