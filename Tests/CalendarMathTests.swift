import XCTest

final class CalendarMathTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        return CalendarMath.calendar.date(from: comps)!
    }

    private func settings(anchor: String, big: Int = 6, small: Int = 5, alternating: Bool = true) -> Settings {
        Settings(bigWeekDays: big, smallWeekDays: small, bigWeekAnchor: anchor, alternating: alternating)
    }

    // MARK: - 键

    func testDateKeyRoundTrip() {
        let d = date(2026, 11, 4)
        let key = CalendarMath.dateKey(d)
        XCTAssertEqual(key, "2026-11-04")
        let back = CalendarMath.date(fromKey: key)
        XCTAssertNotNil(back)
        XCTAssertEqual(CalendarMath.dateKey(back!), "2026-11-04")
    }

    func testDateKeyPadsSingleDigits() {
        XCTAssertEqual(CalendarMath.dateKey(date(2026, 1, 5)), "2026-01-05")
    }

    func testWeekKeyBasic() {
        XCTAssertEqual(CalendarMath.weekKey(date(2026, 11, 4)), "2026-W45")
    }

    func testWeekKeyCrossYear() {
        // 2025-12-29 周一 属于 2026-W01
        XCTAssertEqual(CalendarMath.weekKey(date(2025, 12, 29)), "2026-W01")
        // 2025-12-28 周日 属于 2025-W52
        XCTAssertEqual(CalendarMath.weekKey(date(2025, 12, 28)), "2025-W52")
    }

    func testMondayFromWeekKey() {
        let monday = CalendarMath.monday(fromWeekKey: "2026-W45")
        XCTAssertNotNil(monday)
        XCTAssertEqual(CalendarMath.dateKey(monday!), "2026-11-02")
    }

    func testStartOfWeekIsMonday() {
        // 2026-11-04 是周三
        let start = CalendarMath.startOfWeek(date(2026, 11, 4))
        XCTAssertEqual(CalendarMath.dateKey(start), "2026-11-02")
        XCTAssertEqual(CalendarMath.calendar.component(.weekday, from: start), 2)
    }

    func testWeeksBetween() {
        let a = CalendarMath.startOfWeek(date(2026, 11, 4))
        let b = CalendarMath.addWeeks(2, to: a)
        XCTAssertEqual(CalendarMath.weeksBetween(monday: a, and: b), 2)
        XCTAssertEqual(CalendarMath.weeksBetween(monday: b, and: a), -2)
    }

    // MARK: - 月网格

    func testMonthGridShape() {
        let grid = CalendarMath.monthGrid(for: date(2026, 11, 4), today: date(2026, 11, 4))
        XCTAssertEqual(grid.count, 42)
        // 第一格是 2026-10-26（周一）
        XCTAssertEqual(grid.first?.key, "2026-10-26")
        XCTAssertEqual(CalendarMath.calendar.component(.weekday, from: grid[0].date), 2)
        // 连续 42 天
        for i in 1..<grid.count {
            let prev = grid[i - 1].date
            XCTAssertEqual(CalendarMath.dateKey(CalendarMath.addDays(1, to: prev)), grid[i].key)
        }
        // 覆盖整月
        let inMonth = grid.filter(\.isInCurrentMonth).map(\.key)
        XCTAssertEqual(inMonth.count, 30)
        XCTAssertEqual(inMonth.first, "2026-11-01")
        XCTAssertEqual(inMonth.last, "2026-11-30")
    }

    func testMonthGridMarksToday() {
        let grid = CalendarMath.monthGrid(for: date(2026, 11, 1), today: date(2026, 11, 4))
        let todayCells = grid.filter(\.isToday)
        XCTAssertEqual(todayCells.count, 1)
        XCTAssertEqual(todayCells.first?.key, "2026-11-04")
    }

    // MARK: - 大小周

    func testAlternatingWorkdays() {
        let s = settings(anchor: "2026-W45")
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 4), settings: s, override: nil), 6)
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 11), settings: s, override: nil), 5)
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 18), settings: s, override: nil), 6)
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 10, 28), settings: s, override: nil), 5)
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 10, 21), settings: s, override: nil), 6)
    }

    func testOverrideWinsOverRule() {
        let s = settings(anchor: "2026-W45")
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 11), settings: s, override: 6), 6)
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 4), settings: s, override: 4), 4)
    }

    func testNoAlternatingUsesSmallWeek() {
        let s = settings(anchor: "2026-W45", alternating: false)
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 4), settings: s, override: nil), 5)
    }

    func testMissingAnchorFallsBackToSmallWeek() {
        let s = settings(anchor: "")
        XCTAssertEqual(CalendarMath.workdays(forWeekContaining: date(2026, 11, 4), settings: s, override: nil), 5)
    }

    func testWorkdayDatesNeverIncludeSunday() {
        let six = CalendarMath.workdayDates(inWeekContaining: date(2026, 11, 4), workdays: 6)
        XCTAssertEqual(six.count, 6)
        XCTAssertTrue(six.contains("2026-11-02"))
        XCTAssertTrue(six.contains("2026-11-07")) // 周六
        XCTAssertFalse(six.contains("2026-11-08")) // 周日
    }

    func testWorkdayDatesClamp() {
        let seven = CalendarMath.workdayDates(inWeekContaining: date(2026, 11, 4), workdays: 7)
        XCTAssertEqual(seven.count, 6)
        let five = CalendarMath.workdayDates(inWeekContaining: date(2026, 11, 4), workdays: 5)
        XCTAssertFalse(five.contains("2026-11-07"))
        XCTAssertEqual(five.count, 5)
    }

    // MARK: - 快照

    func testWeekSnapshotStats() {
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        var day = DayEntry(summary: "写完了", tasks: [PlanTask(text: "a", done: true), PlanTask(text: "b", done: false)])
        day.updatedAt = Date()
        data.days["2026-11-04"] = day
        data.weeks["2026-W45"] = WeekEntry(workdaysOverride: nil, summary: "这周还行")

        let snap = CalendarMath.weekSnapshot(containing: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(snap.weekKey, "2026-W45")
        XCTAssertEqual(snap.days.count, 7)
        XCTAssertEqual(snap.workdays, 6)
        XCTAssertEqual(snap.restDays, 1)
        XCTAssertEqual(snap.hasRecord, 1)
        XCTAssertEqual(snap.taskTotal, 2)
        XCTAssertEqual(snap.taskDone, 1)
        XCTAssertFalse(snap.isOverridden)
    }


    // MARK: - 单日例外

    func testRestOverrideRemovesWorkday() {
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        data.dayOverrides["2026-11-07"] = .rest // 大周的周六
        let snap = CalendarMath.weekSnapshot(containing: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(snap.workdays, 5)
        XCTAssertEqual(snap.restDays, 2)
        XCTAssertEqual(snap.manualDays, 1)
        XCTAssertFalse(snap.days.first { $0.key == "2026-11-07" }!.isWorkday)
        XCTAssertEqual(snap.days.first { $0.key == "2026-11-07" }!.override, .rest)
    }

    func testWorkOverrideAllowsSunday() {
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        // 2026-W46 是小周（5 天），把周日补班
        data.dayOverrides["2026-11-15"] = .work
        let snap = CalendarMath.weekSnapshot(containing: date(2026, 11, 11), data: data, today: date(2026, 11, 11))
        XCTAssertEqual(snap.weekKey, "2026-W46")
        XCTAssertEqual(snap.workdays, 6)
        XCTAssertEqual(snap.restDays, 1)
        XCTAssertTrue(snap.days.first { $0.key == "2026-11-15" }!.isWorkday)
    }

    func testOverrideOnlyAffectsItsOwnDay() {
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        data.dayOverrides["2026-11-02"] = .rest // 周一放假
        let snap = CalendarMath.weekSnapshot(containing: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(snap.workdays, 5)
        XCTAssertFalse(snap.days.first { $0.key == "2026-11-02" }!.isWorkday)
        XCTAssertTrue(snap.days.first { $0.key == "2026-11-03" }!.isWorkday)
        // 不影响相邻周
        let next = CalendarMath.weekSnapshot(containing: date(2026, 11, 11), data: data, today: date(2026, 11, 11))
        XCTAssertEqual(next.workdays, 5)
        XCTAssertEqual(next.manualDays, 0)
    }

    func testWeekOverrideZeroMeansWholeWeekOff() {
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        data.weeks["2026-W45"] = WeekEntry(workdaysOverride: 0)
        var snap = CalendarMath.weekSnapshot(containing: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(snap.workdays, 0)
        XCTAssertTrue(snap.days.allSatisfy { !$0.isWorkday })

        // 整周放假里单独让周三上班
        data.dayOverrides["2026-11-04"] = .work
        snap = CalendarMath.weekSnapshot(containing: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(snap.workdays, 1)
        XCTAssertTrue(snap.days.first { $0.key == "2026-11-04" }!.isWorkday)
    }

    func testMonthStatsRespectsOverrides() {
        let plain = CalendarMath.monthStats(for: date(2026, 11, 4),
                                            data: StoreData(settings: settings(anchor: "2026-W45")),
                                            today: date(2026, 11, 4))
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        data.dayOverrides["2026-11-04"] = .rest
        let withRest = CalendarMath.monthStats(for: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(plain.workdays - withRest.workdays, 1)

        var data2 = StoreData(settings: settings(anchor: "2026-W45"))
        data2.dayOverrides["2026-11-08"] = .work // 周日补班
        let withSunday = CalendarMath.monthStats(for: date(2026, 11, 4), data: data2, today: date(2026, 11, 4))
        XCTAssertEqual(withSunday.workdays - plain.workdays, 1)
    }

    func testLegacyFileWithoutOverridesStillDecodes() throws {
        let json = """
        {"version":1,"settings":{"alternating":true,"bigWeekAnchor":"2026-W45","bigWeekDays":6,"smallWeekDays":5},"days":{},"weeks":{}}
        """
        let data = try JSONDecoder().decode(StoreData.self, from: Data(json.utf8))
        XCTAssertTrue(data.dayOverrides.isEmpty)
    }

    func testMonthStats() {
        var data = StoreData(settings: settings(anchor: "2026-W45"))
        data.days["2026-11-04"] = DayEntry(summary: "x", tasks: [PlanTask(text: "a", done: true)])
        data.days["2026-11-05"] = DayEntry(summary: "y")
        let stats = CalendarMath.monthStats(for: date(2026, 11, 4), data: data, today: date(2026, 11, 4))
        XCTAssertEqual(stats.recordedDays, 2)
        XCTAssertEqual(stats.taskTotal, 1)
        XCTAssertEqual(stats.taskDone, 1)
        XCTAssertGreaterThan(stats.workdays, 15)
        XCTAssertLessThanOrEqual(stats.workdays, 30)
    }
}
