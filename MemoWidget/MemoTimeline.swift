import WidgetKit
import SwiftUI

struct MemoEntry: TimelineEntry {
    let date: Date
    let data: StoreData
    /// 读取异常时的提示（例如沙盒读不到数据目录），正常为 nil
    var problem: String? = nil

    var today: Date { date }
    var todayKey: String { CalendarMath.dateKey(date) }
    var todayEntry: DayEntry? { data.days[CalendarMath.dateKey(date)] }
    var todayTasks: [PlanTask] { todayEntry?.tasks ?? [] }
    var weekSnapshot: WeekSnapshot { CalendarMath.weekSnapshot(containing: date, data: data, today: date) }

    static let sample: MemoEntry = {
        var data = StoreData()
        let today = Date()
        let todayKey = CalendarMath.dateKey(today)
        data.days[todayKey] = DayEntry(
            summary: "把小组件做出来了，桌面终于有点样子。",
            tasks: [
                PlanTask(text: "写周报", done: true),
                PlanTask(text: "整理设计稿", done: false),
                PlanTask(text: "跑步 5 公里", done: false)
            ]
        )
        data.days[CalendarMath.dateKey(CalendarMath.addDays(-1, to: today))] = DayEntry(summary: "读完了两章书")
        data.days[CalendarMath.dateKey(CalendarMath.addDays(-3, to: today))] = DayEntry(summary: "加班到十点")
        return MemoEntry(date: today, data: data)
    }()
}

struct MemoProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> MemoEntry {
        MemoEntry.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> Void) {
        if context.isPreview {
            completion(MemoEntry.sample)
        } else {
            completion(loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry(now)
        let next = now.addingTimeInterval(Self.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry(_ now: Date = Date()) -> MemoEntry {
        let result = StoreFile.loadResult(from: AppInfo.storeURL)
        var problem = result.problem
        if problem == nil, !FileManager.default.fileExists(atPath: AppInfo.storeURL.path) {
            problem = "还没有数据，先在 Memo 里写一条"
        }
        return MemoEntry(date: now, data: result.data, problem: problem)
    }
}
