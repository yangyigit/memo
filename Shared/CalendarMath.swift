import Foundation

/// 日历格子中的一天
public struct GridDay: Identifiable, Equatable {
    public let date: Date
    public let key: String
    public let isInCurrentMonth: Bool
    public let isToday: Bool

    public var id: String { key }

    public init(date: Date, key: String, isInCurrentMonth: Bool, isToday: Bool) {
        self.date = date
        self.key = key
        self.isInCurrentMonth = isInCurrentMonth
        self.isToday = isToday
    }
}

/// 全部日期计算都是纯函数，App / Widget / 测试共用。
public enum CalendarMath {

    /// 周一为一周首日，与 ISO 周、大小周语义一致
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        return c
    }

    public static let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    // MARK: - 键

    public static func dateKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps)
    }

    /// ISO 8601 周键，如 "2026-W45"
    public static func weekKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    public static func monday(fromWeekKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1].dropFirst()) else { return nil }
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = 2
        return calendar.date(from: comps)
    }

    // MARK: - 周

    /// 该日期所在周的周一（当天零点）
    public static func startOfWeek(_ date: Date) -> Date {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        return calendar.startOfDay(for: start)
    }

    public static func endOfWeek(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 6, to: startOfWeek(date)) ?? date
    }

    /// 两个周之间相差多少周（可为负）
    public static func weeksBetween(monday lhs: Date, and rhs: Date) -> Int {
        let a = calendar.startOfDay(for: lhs)
        let b = calendar.startOfDay(for: rhs)
        let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        return Int((Double(days) / 7.0).rounded())
    }

    // MARK: - 月

    public static func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    public static func addMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: startOfMonth(date)) ?? date
    }

    public static func addWeeks(_ weeks: Int, to date: Date) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }

    public static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// 固定 42 格（6 周 × 7 天），周一起始
    public static func monthGrid(for month: Date, today: Date = Date()) -> [GridDay] {
        let first = startOfMonth(month)
        let gridStart = startOfWeek(first)
        let todayKey = dateKey(today)
        let monthComps = calendar.dateComponents([.year, .month], from: first)

        return (0..<42).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let comps = calendar.dateComponents([.year, .month], from: day)
            let key = dateKey(day)
            return GridDay(
                date: day,
                key: key,
                isInCurrentMonth: comps.year == monthComps.year && comps.month == monthComps.month,
                isToday: key == todayKey
            )
        }
    }

    // MARK: - 大小周 / 工作日

    /// 某一周上班天数：手动覆盖 > 交替规则 > 小周天数
    public static func workdays(forWeekContaining date: Date, settings: Settings, override: Int?) -> Int {
        let maxWorkdays = 6 // 周日不进入「基准」工作日；要周日上班请用单日例外
        if let override {
            return min(max(override, 0), maxWorkdays)
        }
        let small = min(max(settings.smallWeekDays, 1), maxWorkdays)
        guard settings.alternating else { return small }
        guard let anchor = monday(fromWeekKey: settings.bigWeekAnchor) else { return small }

        let diff = weeksBetween(monday: anchor, and: startOfWeek(date))
        let isBig = abs(diff) % 2 == 0
        return isBig ? min(max(settings.bigWeekDays, 1), maxWorkdays) : small
    }

    /// 一周中的工作日日期集合：从周一起取前 n 天，最多到周六
    public static func workdayDates(inWeekContaining date: Date, workdays count: Int) -> Set<String> {
        let monday = startOfWeek(date)
        let n = min(max(count, 0), 6)
        var result = Set<String>()
        for offset in 0..<n {
            if let d = calendar.date(byAdding: .day, value: offset, to: monday) {
                result.insert(dateKey(d))
            }
        }
        return result
    }

    /// 基准工作日 + 单日例外后的实际工作日集合
    public static func workdayDateSet(inWeekContaining date: Date,
                                      settings: Settings,
                                      weekOverride: Int?,
                                      dayOverrides: [String: DayOverride]) -> Set<String> {
        let base = workdays(forWeekContaining: date, settings: settings, override: weekOverride)
        var set = workdayDates(inWeekContaining: date, workdays: base)
        let monday = startOfWeek(date)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: monday) else { continue }
            let key = dateKey(day)
            switch dayOverrides[key] {
            case .work: set.insert(key)
            case .rest: set.remove(key)
            case nil: break
            }
        }
        return set
    }

    /// 直接从整库算某周的实际工作日集合
    public static func effectiveWorkdays(inWeekContaining date: Date, data: StoreData) -> Set<String> {
        workdayDateSet(inWeekContaining: date,
                       settings: data.settings,
                       weekOverride: data.weeks[weekKey(date)]?.workdaysOverride,
                       dayOverrides: data.dayOverrides)
    }

    public static func isWorkday(_ date: Date, settings: Settings, override: Int?) -> Bool {
        let count = workdays(forWeekContaining: date, settings: settings, override: override)
        return workdayDates(inWeekContaining: date, workdays: count).contains(dateKey(date))
    }

    // MARK: - 文案

    private static var chineseLocale: Locale { Locale(identifier: "zh_CN") }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    public static func monthTitle(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    public static func dayTitle(_ date: Date) -> String {
        fullDayFormatter.string(from: date)
    }

    public static func shortDayTitle(_ date: Date) -> String {
        shortDayFormatter.string(from: date)
    }

    public static func weekRangeTitle(monday: Date) -> String {
        let sunday = addDays(6, to: monday)
        return "\(monthDayFormatter.string(from: monday)) – \(monthDayFormatter.string(from: sunday))"
    }

    public static func isoWeekNumber(_ date: Date) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    public static func weekdaySymbol(for date: Date) -> String {
        let idx = (calendar.component(.weekday, from: date) + 5) % 7 // 周一 => 0
        return weekdaySymbols[max(0, min(6, idx))]
    }

    // MARK: - 快照构造

    public static func daySnapshot(for date: Date, data: StoreData, today: Date = Date()) -> DaySnapshot {
        let key = dateKey(date)
        let workdaySet = effectiveWorkdays(inWeekContaining: date, data: data)
        return DaySnapshot(
            date: calendar.startOfDay(for: date),
            key: key,
            entry: data.days[key],
            isWorkday: workdaySet.contains(key),
            isToday: key == dateKey(today),
            override: data.dayOverrides[key]
        )
    }

    public static func weekSnapshot(containing date: Date, data: StoreData, today: Date = Date()) -> WeekSnapshot {
        let monday = startOfWeek(date)
        let key = weekKey(monday)
        let entry = data.weeks[key]
        let workdaySet = effectiveWorkdays(inWeekContaining: monday, data: data)
        let days = (0..<7).map { offset -> DaySnapshot in
            let day = addDays(offset, to: monday)
            let dayKey = dateKey(day)
            return DaySnapshot(
                date: calendar.startOfDay(for: day),
                key: dayKey,
                entry: data.days[dayKey],
                isWorkday: workdaySet.contains(dayKey),
                isToday: dayKey == dateKey(today),
                override: data.dayOverrides[dayKey]
            )
        }
        return WeekSnapshot(monday: monday, weekKey: key, days: days, workdays: workdaySet.count, entry: entry)
    }

    public static func monthStats(for month: Date, data: StoreData, today: Date = Date()) -> MonthStats {
        let grid = monthGrid(for: month, today: today).filter(\.isInCurrentMonth)
        var recorded = 0
        var total = 0
        var done = 0
        var workdays = 0
        var countedWeeks = Set<String>()

        for day in grid {
            if let entry = data.days[day.key], !entry.isEmpty {
                recorded += 1
                total += entry.tasks.count
                done += entry.doneCount
            }
            let key = weekKey(day.date)
            if !countedWeeks.contains(key) {
                countedWeeks.insert(key)
                let workdaySet = Self.effectiveWorkdays(inWeekContaining: day.date, data: data)
                workdays += grid.filter { workdaySet.contains($0.key) }.count
            }
        }
        return MonthStats(recordedDays: recorded, taskTotal: total, taskDone: done, workdays: workdays)
    }
}
