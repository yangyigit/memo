import SwiftUI
import WidgetKit

struct MonthWidgetView: View {
    let entry: MemoEntry

    private var todayDone: Int { entry.todayEntry?.doneCount ?? 0 }
    private var todayTotal: Int { entry.todayTasks.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CalendarMath.monthTitle(entry.date))
                    .font(Theme.serif(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("本周上班 \(entry.weekSnapshot.workdays) 天")
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.inkSecondary)
            }

            CompactMonthGrid(data: entry.data, reference: entry.date, fontSize: 10, cellHeight: 15)

            HStack(spacing: 6) {
                Text(CalendarMath.shortDayTitle(entry.date))
                    .font(Theme.sans(9, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(entry.problem ?? (todayTotal > 0 ? "计划 \(todayDone)/\(todayTotal)" : "今天还没有计划"))
                    .font(Theme.sans(9))
                    .foregroundStyle(entry.problem == nil ? Theme.inkSecondary : Theme.accent)
                    .lineLimit(1)
                Spacer()
                Text(CalendarMath.weekdaySymbol(for: entry.date))
                    .font(Theme.sans(9))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .widgetURL(URL(string: "memo://today"))
    }
}

struct MonthWidget: Widget {
    let kind = WidgetKinds.month

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    PaperTexture(gridSpacing: 16, fiberCount: 160)
                }
        }
        .configurationDisplayName("月历")
        .description("当月日历，点开回到今天。")
        .supportedFamilies([.systemMedium])
    }
}
