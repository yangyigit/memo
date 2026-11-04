import SwiftUI
import WidgetKit

struct TodayWidgetView: View {
    let entry: MemoEntry

    private var tasks: [PlanTask] { entry.todayTasks }
    private var visibleTasks: [PlanTask] { Array(tasks.prefix(5)) }
    private var hiddenCount: Int { max(0, tasks.count - visibleTasks.count) }
    private var doneCount: Int { entry.todayEntry?.doneCount ?? 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左：月历
            VStack(alignment: .leading, spacing: 4) {
                Text(CalendarMath.monthTitle(entry.date))
                    .font(Theme.serif(12, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                CompactMonthGrid(data: entry.data, reference: entry.date, fontSize: 8.5, cellHeight: 14, spacing: 0.5)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text("本周上班 \(entry.weekSnapshot.workdays) 天")
                        .font(Theme.sans(8.5))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("计划 \(entry.weekSnapshot.taskDone)/\(entry.weekSnapshot.taskTotal)")
                        .font(Theme.sans(8.5))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(width: 148)

            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)

            // 右：今日计划
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CalendarMath.shortDayTitle(entry.date))
                        .font(Theme.serif(13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(CalendarMath.weekdaySymbol(for: entry.date))
                        .font(Theme.sans(9))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 0)
                    if !tasks.isEmpty {
                        Text("\(doneCount)/\(tasks.count)")
                            .font(Theme.sans(9, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }

                if tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今天还没有计划")
                            .font(Theme.sans(10))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("点开写一条")
                            .font(Theme.sans(9))
                            .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                    }
                    .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(visibleTasks) { task in
                            Button(intent: ToggleTaskIntent(dayKey: entry.todayKey, taskID: task.id.uuidString)) {
                                HStack(spacing: 5) {
                                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(task.done ? Theme.accent : Theme.inkSecondary.opacity(0.75))
                                    Text(task.text)
                                        .font(Theme.sans(10))
                                        .foregroundStyle(task.done ? Theme.inkSecondary : Theme.ink)
                                        .strikethrough(task.done, color: Theme.inkSecondary.opacity(0.6))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount) 项")
                        .font(Theme.sans(9))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer(minLength: 0)

                Text(entry.problem ?? "点空白打开写总结")
                    .font(Theme.sans(8.5))
                    .foregroundStyle(entry.problem == nil ? Theme.inkSecondary.opacity(0.65) : Theme.accent)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(URL(string: "memo://day/\(entry.todayKey)"))
    }
}

struct TodayWidget: Widget {
    let kind = "MemoTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    PaperTexture(gridSpacing: 16, fiberCount: 200)
                }
        }
        .configurationDisplayName("今天")
        .description("月历 + 今天的计划，可直接勾选。")
        .supportedFamilies([.systemLarge])
    }
}
