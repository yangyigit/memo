import XCTest

final class FestivalsTests: XCTestCase {

    private func date(_ key: String) -> Date {
        CalendarMath.date(fromKey: key)!
    }

    private func name(_ key: String) -> String? {
        Festivals.festival(on: date(key))?.name
    }

    func testSolarFestivals() {
        XCTAssertEqual(name("2026-01-01"), "元旦")
        XCTAssertEqual(name("2026-05-01"), "劳动节")
        XCTAssertEqual(name("2026-10-01"), "国庆节")
        XCTAssertEqual(name("2026-12-25"), "圣诞节")
        XCTAssertEqual(name("2026-02-14"), "情人节")
    }

    func testLunarFestivals() {
        // 2026 春节 = 2/17，除夕 = 2/16
        XCTAssertEqual(name("2026-02-16"), "除夕")
        XCTAssertEqual(name("2026-02-17"), "春节")
        XCTAssertEqual(name("2026-03-03"), "元宵")
        XCTAssertEqual(name("2026-06-19"), "端午")
        XCTAssertEqual(name("2026-08-19"), "七夕")
        XCTAssertEqual(name("2026-09-25"), "中秋")
        XCTAssertEqual(name("2026-10-18"), "重阳")
        // 2025 春节 = 1/29
        XCTAssertEqual(name("2025-01-29"), "春节")
        XCTAssertEqual(name("2025-10-06"), "中秋")
    }

    func testQingming() {
        XCTAssertEqual(name("2026-04-05"), "清明")
        XCTAssertEqual(name("2024-04-04"), "清明")
        XCTAssertEqual(name("2025-04-04"), "清明")
    }

    func testOrdinaryDayHasNoFestival() {
        XCTAssertNil(name("2026-11-04"))
        XCTAssertNil(name("2026-02-24"))
    }

    func testMajorFlag() {
        XCTAssertTrue(Festivals.festival(on: date("2026-02-17"))!.isMajor)
        XCTAssertFalse(Festivals.festival(on: date("2026-02-14"))!.isMajor)
    }

    func testMonthFestivalMap() {
        let map = Festivals.festivals(inMonth: date("2026-10-01"))
        XCTAssertEqual(map["2026-10-01"]?.name, "国庆节")
        XCTAssertEqual(map["2026-10-18"]?.name, "重阳")
        // 只包含当月，不含相邻月
        XCTAssertNil(map["2026-09-25"])
        XCTAssertEqual(map.count, 2)
    }
}
