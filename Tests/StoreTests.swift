import XCTest

final class StoreFileTests: XCTestCase {

    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("memo-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("store.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveLoadRoundTrip() throws {
        var data = StoreData()
        data.settings.bigWeekDays = 6
        data.settings.smallWeekDays = 5
        data.settings.bigWeekAnchor = "2026-W45"
        data.days["2026-11-04"] = DayEntry(summary: "总结内容",
                                          tasks: [PlanTask(text: "写代码", done: true)])
        data.weeks["2026-W45"] = WeekEntry(workdaysOverride: 6, summary: "周总结")

        XCTAssertNil(StoreFile.save(data, to: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = StoreFile.load(from: url)
        XCTAssertEqual(loaded.days["2026-11-04"]?.summary, "总结内容")
        XCTAssertEqual(loaded.days["2026-11-04"]?.tasks.first?.text, "写代码")
        XCTAssertEqual(loaded.days["2026-11-04"]?.tasks.first?.done, true)
        XCTAssertEqual(loaded.weeks["2026-W45"]?.workdaysOverride, 6)
        XCTAssertEqual(loaded.settings.bigWeekAnchor, "2026-W45")
    }

    func testSecondSaveCreatesBackup() throws {
        var data = StoreData()
        data.days["2026-11-04"] = DayEntry(summary: "第一版")
        XCTAssertNil(StoreFile.save(data, to: url))

        data.days["2026-11-04"] = DayEntry(summary: "第二版")
        XCTAssertNil(StoreFile.save(data, to: url))

        let backup = StoreFile.backupURL(for: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let backupData = StoreFile.load(from: backup)
        XCTAssertEqual(backupData.days["2026-11-04"]?.summary, "第一版")
        XCTAssertEqual(StoreFile.load(from: url).days["2026-11-04"]?.summary, "第二版")
    }

    func testCorruptFileFallsBackToBackup() throws {
        var data = StoreData()
        data.days["2026-11-04"] = DayEntry(summary: "好数据")
        XCTAssertNil(StoreFile.save(data, to: url))
        // 再存一次生成 .bak
        XCTAssertNil(StoreFile.save(data, to: url))

        try "{ not json ".write(to: url, atomically: true, encoding: .utf8)

        let result = StoreFile.loadResult(from: url)
        XCTAssertNotNil(result.problem)
        XCTAssertEqual(result.data.days["2026-11-04"]?.summary, "好数据")
    }

    func testCorruptWithoutBackupRebuildsEmpty() throws {
        try "garbage".write(to: url, atomically: true, encoding: .utf8)
        let result = StoreFile.loadResult(from: url)
        XCTAssertNotNil(result.problem)
        XCTAssertTrue(result.data.days.isEmpty)
    }

    func testToggleTaskFromWidgetPath() throws {
        let task = PlanTask(text: "喝水", done: false)
        var data = StoreData()
        data.days["2026-11-04"] = DayEntry(tasks: [task])
        XCTAssertNil(StoreFile.save(data, to: url))

        XCTAssertTrue(StoreFile.toggleTask(dayKey: "2026-11-04", taskID: task.id, at: url))
        XCTAssertEqual(StoreFile.load(from: url).days["2026-11-04"]?.tasks.first?.done, true)

        XCTAssertTrue(StoreFile.toggleTask(dayKey: "2026-11-04", taskID: task.id, at: url))
        XCTAssertEqual(StoreFile.load(from: url).days["2026-11-04"]?.tasks.first?.done, false)
    }

    func testToggleMissingTaskIsNoop() throws {
        XCTAssertFalse(StoreFile.toggleTask(dayKey: "2026-11-04", taskID: UUID(), at: url))
    }
}

@MainActor
final class StoreTests: XCTestCase {

    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("memo-store-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("store.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testEmptyDayIsRemoved() {
        let store = Store(url: url)
        let key = "2026-11-04"
        store.updateDay(key) { $0.summary = "有内容" }
        XCTAssertNotNil(store.dayEntry(key))
        store.updateDay(key) { $0.summary = "" }
        XCTAssertNil(store.dayEntry(key))
    }

    func testWhitespaceOnlySummaryIsEmpty() {
        let store = Store(url: url)
        let key = "2026-11-04"
        store.updateDay(key) { $0.summary = "   \n  " }
        XCTAssertNil(store.dayEntry(key))
    }

    func testAddToggleDeleteTask() {
        let store = Store(url: url)
        let day = CalendarMath.date(fromKey: "2026-11-04")!
        let id = store.addTask(to: day, text: "  跑步  ")
        XCTAssertNotNil(id)
        XCTAssertEqual(store.tasks(for: day).first?.text, "跑步")

        store.toggleTask(day, taskID: id!)
        XCTAssertEqual(store.tasks(for: day).first?.done, true)

        store.deleteTask(day, taskID: id!)
        XCTAssertTrue(store.tasks(for: day).isEmpty)
        XCTAssertNil(store.dayEntry("2026-11-04"))
    }

    func testUpdateTaskText() {
        let store = Store(url: url)
        let day = CalendarMath.date(fromKey: "2026-11-04")!
        let id = store.addTask(to: day, text: "跑步")!
        store.updateTaskText(day, taskID: id, text: "  跑步 5 公里  ")
        XCTAssertEqual(store.tasks(for: day).first?.text, "跑步 5 公里")
        XCTAssertEqual(store.tasks(for: day).count, 1)
    }

    func testUpdateTaskTextToBlankDeletesTask() {
        let store = Store(url: url)
        let day = CalendarMath.date(fromKey: "2026-11-04")!
        let id = store.addTask(to: day, text: "跑步")!
        store.updateTaskText(day, taskID: id, text: "   ")
        XCTAssertTrue(store.tasks(for: day).isEmpty)
        XCTAssertNil(store.dayEntry("2026-11-04"))
    }

    func testBlankTaskIsIgnored() {
        let store = Store(url: url)
        let day = CalendarMath.date(fromKey: "2026-11-04")!
        XCTAssertNil(store.addTask(to: day, text: "   "))
        XCTAssertTrue(store.tasks(for: day).isEmpty)
    }

    func testSettingsAnchorAutoFilled() {
        let store = Store(url: url)
        XCTAssertFalse(store.data.settings.bigWeekAnchor.isEmpty)
    }

    func testOverridePersistsAndClears() {
        let store = Store(url: url)
        store.setWorkdaysOverride(weekKey: "2026-W45", value: 6)
        XCTAssertEqual(store.weekEntry("2026-W45")?.workdaysOverride, 6)
        store.setWorkdaysOverride(weekKey: "2026-W45", value: nil)
        XCTAssertNil(store.weekEntry("2026-W45"))
    }

    func testSaveNowWritesFile() {
        let store = Store(url: url)
        let day = CalendarMath.date(fromKey: "2026-11-04")!
        store.addTask(to: day, text: "写文档")
        store.saveNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(StoreFile.load(from: url).days["2026-11-04"]?.tasks.count, 1)
    }


    func testSetAndClearDayOverride() {
        let store = Store(url: url)
        let day = CalendarMath.date(fromKey: "2026-11-07")!
        XCTAssertEqual(store.dayOverrideCount, 0)

        store.setDayOverride(day, value: .rest)
        XCTAssertEqual(store.dayOverrideCount, 1)
        XCTAssertEqual(store.daySnapshot(for: day, today: day).override, .rest)
        XCTAssertFalse(store.daySnapshot(for: day, today: day).isWorkday)

        store.saveNow()
        let reloaded = Store(url: url)
        XCTAssertEqual(reloaded.daySnapshot(for: day, today: day).override, .rest)

        store.setDayOverride(day, value: nil)
        XCTAssertEqual(store.dayOverrideCount, 0)
        XCTAssertTrue(store.daySnapshot(for: day, today: day).isWorkday)
    }

    func testClearAllDayOverrides() {
        let store = Store(url: url)
        store.setDayOverride(CalendarMath.date(fromKey: "2026-11-07")!, value: .rest)
        store.setDayOverride(CalendarMath.date(fromKey: "2026-11-08")!, value: .work)
        XCTAssertEqual(store.dayOverrideCount, 2)
        store.clearDayOverrides()
        XCTAssertEqual(store.dayOverrideCount, 0)
        store.saveNow()
        XCTAssertTrue(StoreFile.load(from: url).dayOverrides.isEmpty)
    }

    func testWorkdaysHelperCountsOverrides() {
        let store = Store(url: url)
        store.updateSettings { $0.bigWeekAnchor = "2026-W45" }
        let saturday = CalendarMath.date(fromKey: "2026-11-07")!
        XCTAssertEqual(store.workdays(forWeekContaining: saturday), 6)
        store.setDayOverride(saturday, value: .rest)
        XCTAssertEqual(store.workdays(forWeekContaining: saturday), 5)
        XCTAssertEqual(store.baseWorkdays(forWeekContaining: saturday), 6)
    }

    func testWorkdaysHelperMatchesRules() {
        let store = Store(url: url)
        store.updateSettings {
            $0.bigWeekAnchor = "2026-W45"
            $0.bigWeekDays = 6
            $0.smallWeekDays = 5
            $0.alternating = true
        }
        XCTAssertEqual(store.workdays(forWeekContaining: CalendarMath.date(fromKey: "2026-11-04")!), 6)
        XCTAssertEqual(store.workdays(forWeekContaining: CalendarMath.date(fromKey: "2026-11-11")!), 5)
    }
}
