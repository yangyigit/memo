import Foundation

/// 节日标注：公历固定日 + 农历（用系统的中国农历日历现算）+ 清明（20 年小表）
/// 纯计算、离线、无需订阅，任何年份都能出结果。
public struct Festival: Equatable, Hashable {
    public let name: String
    /// 传统大节（春节/中秋/国庆…）：UI 上用强调色
    public let isMajor: Bool

    public init(name: String, isMajor: Bool) {
        self.name = name
        self.isMajor = isMajor
    }
}

public enum Festivals {

    // MARK: - 公历（月-日）

    private static let solar: [String: Festival] = [
        "01-01": Festival(name: "元旦", isMajor: true),
        "02-14": Festival(name: "情人节", isMajor: false),
        "03-08": Festival(name: "妇女节", isMajor: false),
        "03-12": Festival(name: "植树节", isMajor: false),
        "04-01": Festival(name: "愚人节", isMajor: false),
        "05-01": Festival(name: "劳动节", isMajor: true),
        "05-04": Festival(name: "青年节", isMajor: false),
        "06-01": Festival(name: "儿童节", isMajor: false),
        "09-10": Festival(name: "教师节", isMajor: false),
        "10-01": Festival(name: "国庆节", isMajor: true),
        "12-24": Festival(name: "平安夜", isMajor: false),
        "12-25": Festival(name: "圣诞节", isMajor: false)
    ]

    // MARK: - 农历（月-日，闰月不算）

    private static let lunar: [String: Festival] = [
        "1-1": Festival(name: "春节", isMajor: true),
        "1-15": Festival(name: "元宵", isMajor: true),
        "2-2": Festival(name: "龙抬头", isMajor: false),
        "5-5": Festival(name: "端午", isMajor: true),
        "7-7": Festival(name: "七夕", isMajor: false),
        "8-15": Festival(name: "中秋", isMajor: true),
        "9-9": Festival(name: "重阳", isMajor: false),
        "12-8": Festival(name: "腊八", isMajor: false)
    ]

    // MARK: - 清明（清明是节气，不在公历固定日；这里给 2020–2040 的表）

    private static let qingming: [Int: String] = [
        2020: "04-04", 2021: "04-04", 2022: "04-05", 2023: "04-05", 2024: "04-04",
        2025: "04-04", 2026: "04-05", 2027: "04-05", 2028: "04-04", 2029: "04-04",
        2030: "04-05", 2031: "04-05", 2032: "04-04", 2033: "04-04", 2034: "04-05",
        2035: "04-05", 2036: "04-04", 2037: "04-04", 2038: "04-05", 2039: "04-05",
        2040: "04-04"
    ]

    // MARK: - 农历换算

    private static var chineseCalendar: Calendar {
        var c = Calendar(identifier: .chinese)
        c.timeZone = .current
        return c
    }

    private static func lunarMonthDay(_ date: Date) -> (month: Int, day: Int, isLeap: Bool)? {
        let comps = chineseCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = comps.month, let day = comps.day else { return nil }
        return (month, day, comps.isLeapMonth ?? false)
    }

    // MARK: - 缓存（农历换算要跑 Calendar(.chinese)，按日缓存，避免每帧重算）

    private static let lock = NSLock()
    private static var cache: [String: Festival] = [:]
    private static var misses: Set<String> = []

    // MARK: - 查询

    /// 某天的节日（可能没有）
    public static func festival(on date: Date) -> Festival? {
        let dayKey = CalendarMath.dateKey(date)

        lock.lock()
        if let hit = cache[dayKey] { lock.unlock(); return hit }
        if misses.contains(dayKey) { lock.unlock(); return nil }
        lock.unlock()

        let result = computeFestival(on: date)

        lock.lock()
        if let result {
            cache[dayKey] = result
        } else {
            misses.insert(dayKey)
        }
        lock.unlock()
        return result
    }

    private static func computeFestival(on date: Date) -> Festival? {
        // 除夕：次日是农历正月初一
        let tomorrow = CalendarMath.addDays(1, to: date)
        if let next = lunarMonthDay(tomorrow),
           next.month == 1, next.day == 1, !next.isLeap {
            return Festival(name: "除夕", isMajor: true)
        }

        if let today = lunarMonthDay(date), !today.isLeap,
           let festival = lunar["\(today.month)-\(today.day)"] {
            return festival
        }

        let dayKey = CalendarMath.dateKey(date) // yyyy-MM-dd
        let monthDay = String(dayKey.suffix(5))
        if let festival = solar[monthDay] {
            return festival
        }

        let year = CalendarMath.calendar.component(.year, from: date)
        if let qm = qingming[year], qm == monthDay {
            return Festival(name: "清明", isMajor: true)
        }

        return nil
    }

    /// 某个月里所有节日（key 为 "yyyy-MM-dd"）
    public static func festivals(inMonth month: Date) -> [String: Festival] {
        let grid = CalendarMath.monthGrid(for: month)
        var result: [String: Festival] = [:]
        for day in grid where day.isInCurrentMonth {
            if let festival = festival(on: day.date) {
                result[day.key] = festival
            }
        }
        return result
    }
}
