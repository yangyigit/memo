import Foundation

// MARK: - 计划条目

public struct PlanTask: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var text: String
    public var done: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, done: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.done = done
        self.createdAt = createdAt
    }
}

// MARK: - 单日例外（节假日 / 调休补班 / 请假）

public enum DayOverride: String, Codable, Equatable, Hashable {
    /// 强制上班（可让周日变成上班日，用于调休补班）
    case work
    /// 强制休息（法定假日、请假）
    case rest

    public var title: String { self == .work ? "上班" : "休息" }
    /// 月历/周视图里的小标记
    public var badge: String { self == .work ? "班" : "休" }
}

// MARK: - 一天

public struct DayEntry: Codable, Equatable {
    public var summary: String
    public var tasks: [PlanTask]
    public var updatedAt: Date

    public init(summary: String = "", tasks: [PlanTask] = [], updatedAt: Date = Date()) {
        self.summary = summary
        self.tasks = tasks
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tasks.isEmpty
    }

    public var doneCount: Int { tasks.filter(\.done).count }

    /// 第一行非空文本，用于周视图列表摘要
    public var summaryPreview: String {
        summary
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

// MARK: - 一周

public struct WeekEntry: Codable, Equatable {
    /// 手动覆盖本周上班天数；nil 表示跟随大小周规则
    public var workdaysOverride: Int?
    public var summary: String
    public var updatedAt: Date

    public init(workdaysOverride: Int? = nil, summary: String = "", updatedAt: Date = Date()) {
        self.workdaysOverride = workdaysOverride
        self.summary = summary
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        workdaysOverride == nil && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 设置

public struct Settings: Codable, Equatable {
    /// 大周上班天数
    public var bigWeekDays: Int
    /// 小周上班天数
    public var smallWeekDays: Int
    /// 锚点周的 ISO 周键（该周为大周），如 "2026-W45"
    public var bigWeekAnchor: String
    /// 是否按大小周交替
    public var alternating: Bool

    public init(bigWeekDays: Int = 6,
                smallWeekDays: Int = 5,
                bigWeekAnchor: String = "",
                alternating: Bool = true) {
        self.bigWeekDays = bigWeekDays
        self.smallWeekDays = smallWeekDays
        self.bigWeekAnchor = bigWeekAnchor
        self.alternating = alternating
    }
}

// MARK: - 整库

public struct StoreData: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var settings: Settings
    public var days: [String: DayEntry]
    public var weeks: [String: WeekEntry]
    /// 单日例外：key 为 "2026-11-04"
    public var dayOverrides: [String: DayOverride]

    public init(version: Int = StoreData.currentVersion,
                settings: Settings = Settings(),
                days: [String: DayEntry] = [:],
                weeks: [String: WeekEntry] = [:],
                dayOverrides: [String: DayOverride] = [:]) {
        self.version = version
        self.settings = settings
        self.days = days
        self.weeks = weeks
        self.dayOverrides = dayOverrides
    }

    // 容错解码：缺字段时用默认值，避免旧文件/半截字段导致整库读不出来
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? StoreData.currentVersion
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
        days = (try? c.decode([String: DayEntry].self, forKey: .days)) ?? [:]
        weeks = (try? c.decode([String: WeekEntry].self, forKey: .weeks)) ?? [:]
        dayOverrides = (try? c.decode([String: DayOverride].self, forKey: .dayOverrides)) ?? [:]
    }
}

// MARK: - 派生视图模型（App 与 Widget 共用）

/// 某一天在 UI 上的完整状态
public struct DaySnapshot: Identifiable, Equatable {
    public let date: Date
    public let key: String
    public let entry: DayEntry?
    public let isWorkday: Bool
    public let isToday: Bool
    /// 手动的单日例外；nil 表示跟随大小周规则
    public let override: DayOverride?

    public var id: String { key }
    public var taskTotal: Int { entry?.tasks.count ?? 0 }
    public var taskDone: Int { entry?.doneCount ?? 0 }
    public var hasSummary: Bool { !(entry?.summaryPreview.isEmpty ?? true) }
    public var isManualOverride: Bool { override != nil }

    public init(date: Date, key: String, entry: DayEntry?, isWorkday: Bool, isToday: Bool,
                override: DayOverride? = nil) {
        self.date = date
        self.key = key
        self.entry = entry
        self.isWorkday = isWorkday
        self.isToday = isToday
        self.override = override
    }
}

/// 一周的统计与设置视图
public struct WeekSnapshot: Equatable {
    public let monday: Date
    public let weekKey: String
    public let days: [DaySnapshot]
    public let workdays: Int
    public let entry: WeekEntry?

    public var restDays: Int { 7 - workdays }
    public var hasRecord: Int { days.filter { $0.entry != nil }.count }
    public var manualDays: Int { days.filter(\.isManualOverride).count }
    public var taskTotal: Int { days.reduce(0) { $0 + $1.taskTotal } }
    public var taskDone: Int { days.reduce(0) { $0 + $1.taskDone } }
    public var isOverridden: Bool { entry?.workdaysOverride != nil }

    public init(monday: Date, weekKey: String, days: [DaySnapshot], workdays: Int, entry: WeekEntry?) {
        self.monday = monday
        self.weekKey = weekKey
        self.days = days
        self.workdays = workdays
        self.entry = entry
    }
}

/// 一个月的统计
public struct MonthStats: Equatable {
    public let recordedDays: Int
    public let taskTotal: Int
    public let taskDone: Int
    public let workdays: Int

    public init(recordedDays: Int, taskTotal: Int, taskDone: Int, workdays: Int) {
        self.recordedDays = recordedDays
        self.taskTotal = taskTotal
        self.taskDone = taskDone
        self.workdays = workdays
    }
}
