import SwiftUI

struct MonthView: View {
    @Environment(Store.self) private var store

    @Binding var monthAnchor: Date
    @Binding var selectedDay: IdentifiableDate?
    var today: Date
    var onOpenWeek: (Date) -> Void

    private var grid: [GridDay] {
        CalendarMath.monthGrid(for: monthAnchor, today: today)
    }

    private var stats: MonthStats {
        store.monthStats(for: monthAnchor, today: today)
    }

    private var festivalMap: [String: Festival] {
        Festivals.festivals(inMonth: monthAnchor)
    }

    private var weeks: [[GridDay]] {
        stride(from: 0, to: grid.count, by: 7).map { Array(grid[$0..<min($0 + 7, grid.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            PaperCard(padding: 14, showsGrid: false) {
                VStack(spacing: 0) {
                    weekdayHeader
                    Hairline().padding(.vertical, 8)
                    VStack(spacing: 3) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            HStack(spacing: 2) {
                                ForEach(week) { day in
                                    dayCell(day, festivals: festivalMap)
                                }
                            }
                        }
                    }
                }
            }

            footer

            Spacer(minLength: 0)
        }
        .padding(Theme.pagePadding)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(CalendarMath.monthTitle(monthAnchor))
                .font(Theme.serif(30, weight: .semibold))
                .foregroundStyle(Theme.ink)

            if let festival = Festivals.festival(on: today) {
                Text("今天 · \(festival.name)")
                    .font(Theme.sans(11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.10)))
            }

            Spacer()

            iconButton("chevron.left") { monthAnchor = CalendarMath.addMonths(-1, to: monthAnchor) }
            iconButton("chevron.right") { monthAnchor = CalendarMath.addMonths(1, to: monthAnchor) }

            textButton("今天") {
                monthAnchor = CalendarMath.startOfMonth(today)
                selectedDay = IdentifiableDate(date: today)
            }
            textButton("本周") { onOpenWeek(today) }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(CalendarMath.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(Theme.label(11))
                    .tracking(1)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("本月 \(stats.recordedDays) 天有记录")
            dot
            Text("计划 \(stats.taskDone)/\(stats.taskTotal)")
            dot
            Text("上班 \(stats.workdays) 天")
            Spacer()
        }
        .font(Theme.sans(11))
        .foregroundStyle(Theme.inkSecondary)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Theme.inkSecondary.opacity(0.6))
    }

    // MARK: - 格子

    private func dayCell(_ day: GridDay, festivals: [String: Festival]) -> some View {
        let snapshot = store.daySnapshot(for: day.date, today: today)
        return Button {
            selectedDay = IdentifiableDate(date: day.date)
        } label: {
            DayCell(snapshot: snapshot,
                    isInCurrentMonth: day.isInCurrentMonth,
                    festival: festivals[day.key])
        }
        .buttonStyle(.plain)
    }

    // MARK: - 小组件

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.ink.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.ink.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单个日期格

struct DayCell: View {
    let snapshot: DaySnapshot
    let isInCurrentMonth: Bool
    var festival: Festival? = nil

    @State private var hovering = false

    private var dayNumber: String {
        let c = CalendarMath.calendar.dateComponents([.day], from: snapshot.date)
        return "\(c.day ?? 0)"
    }

    private var numberColor: Color {
        if snapshot.isToday { return Theme.accent }
        if !isInCurrentMonth { return Theme.inkSecondary.opacity(0.45) }
        return snapshot.isWorkday ? Theme.ink : Theme.inkSecondary
    }

    private var fill: Color {
        if snapshot.isToday { return Theme.todayFill }
        if hovering { return Theme.hoverFill }
        if !snapshot.isWorkday { return Theme.ink.opacity(0.032) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                Text(dayNumber)
                    .font(Theme.serif(16, weight: snapshot.isToday ? .semibold : .regular))
                    .foregroundStyle(numberColor)
                Spacer(minLength: 0)
                if snapshot.hasSummary {
                    Circle()
                        .fill(Theme.accent.opacity(isInCurrentMonth ? 0.75 : 0.35))
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                }
            }

            if let festival {
                Text(festival.name)
                    .font(Theme.sans(9, weight: festival.isMajor ? .medium : .regular))
                    .foregroundStyle(festival.isMajor ? Theme.accent.opacity(0.9) : Theme.inkSecondary)
                    .lineLimit(1)
                    .opacity(isInCurrentMonth ? 1 : 0.45)
            }

            Spacer(minLength: 0)

            if let preview = snapshot.entry?.summaryPreview, !preview.isEmpty {
                Text(preview)
                    .font(Theme.sans(9.5))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(festival == nil ? 2 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isInCurrentMonth ? 1 : 0.45)
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 4) {
                if snapshot.taskTotal > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        ThinProgressBar(
                            value: Double(snapshot.taskDone) / Double(snapshot.taskTotal),
                            height: 2
                        )
                        Text("\(snapshot.taskDone)/\(snapshot.taskTotal)")
                            .font(Theme.sans(9))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                Spacer(minLength: 0)

                if let override = snapshot.override {
                    Text(override.badge)
                        .font(Theme.sans(9, weight: .medium))
                        .foregroundStyle(override == .work
                                         ? Theme.accent.opacity(isInCurrentMonth ? 1 : 0.5)
                                         : Theme.inkSecondary.opacity(isInCurrentMonth ? 0.9 : 0.5))
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
        }
        .overlay {
            if snapshot.isToday {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }
}
