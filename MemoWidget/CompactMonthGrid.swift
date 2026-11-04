import SwiftUI
import WidgetKit

/// 组件内的紧凑月历网格（数字 + 有记录小点）
struct CompactMonthGrid: View {
    let data: StoreData
    let reference: Date
    var fontSize: CGFloat = 9
    var cellHeight: CGFloat = 15
    var showsDots: Bool = true
    var spacing: CGFloat = 1

    private var grid: [GridDay] {
        CalendarMath.monthGrid(for: reference, today: reference)
    }

    private var rows: [[GridDay]] {
        stride(from: 0, to: grid.count, by: 7).map { Array(grid[$0..<min($0 + 7, grid.count)]) }
    }

    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: 0) {
                ForEach(CalendarMath.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: fontSize - 1, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        cell(day)
                    }
                }
                .frame(height: cellHeight)
            }
        }
    }

    private func cell(_ day: GridDay) -> some View {
        let entry = data.days[day.key]
        let hasSummary = !(entry?.summaryPreview.isEmpty ?? true)
        let dayNumber = CalendarMath.calendar.component(.day, from: day.date)

        return VStack(spacing: 0.5) {
            Text("\(dayNumber)")
                .font(.system(size: fontSize, weight: day.isToday ? .semibold : .regular, design: .serif))
                .foregroundStyle(numberColor(day))
                .frame(maxWidth: .infinity)
                .background {
                    if day.isToday {
                        Circle()
                            .fill(Theme.accent.opacity(0.14))
                            .frame(width: fontSize + 5, height: fontSize + 5)
                    }
                }

            if showsDots {
                Circle()
                    .fill(hasSummary ? Theme.accent.opacity(day.isInCurrentMonth ? 0.8 : 0.35) : .clear)
                    .frame(width: 2.5, height: 2.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func numberColor(_ day: GridDay) -> Color {
        if day.isToday { return Theme.accent }
        if !day.isInCurrentMonth { return Theme.inkSecondary.opacity(0.45) }
        let isWorkday = workdays.contains(day.key)
        return isWorkday ? Theme.ink : Theme.inkSecondary.opacity(0.85)
    }

    private var workdays: Set<String> {
        var set = Set<String>()
        for week in rows {
            guard let first = week.first else { continue }
            set.formUnion(CalendarMath.effectiveWorkdays(inWeekContaining: first.date, data: data))
        }
        return set
    }
}
