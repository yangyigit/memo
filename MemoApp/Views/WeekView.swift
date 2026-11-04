import SwiftUI

struct WeekView: View {
    @Environment(Store.self) private var store

    @Binding var weekAnchor: Date
    @Binding var selectedDay: IdentifiableDate?
    var today: Date

    private var snapshot: WeekSnapshot {
        store.weekSnapshot(containing: weekAnchor, today: today)
    }

    private func summaryBinding(for weekKey: String) -> Binding<String> {
        Binding(
            get: { store.weekEntry(weekKey)?.summary ?? "" },
            set: { store.setWeekSummary(weekKey: weekKey, text: $0) }
        )
    }

    private func overrideBinding(for snap: WeekSnapshot) -> Binding<Int> {
        Binding(
            get: { store.weekEntry(snap.weekKey)?.workdaysOverride ?? snap.workdays },
            set: { store.setWorkdaysOverride(weekKey: snap.weekKey, value: $0) }
        )
    }

    var body: some View {
        let snap = snapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(snap)
                workdayCard(snap)
                daysCard(snap)
                summaryCard(snap)
                statsLine(snap)
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 头部

    private func header(_ snap: WeekSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("第 \(CalendarMath.isoWeekNumber(snap.monday)) 周")
                .font(Theme.serif(30, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text(CalendarMath.weekRangeTitle(monday: snap.monday))
                .font(Theme.serif(15))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.leading, 2)

            Spacer()

            iconButton("chevron.left") { weekAnchor = CalendarMath.addWeeks(-1, to: weekAnchor) }
            iconButton("chevron.right") { weekAnchor = CalendarMath.addWeeks(1, to: weekAnchor) }
            textButton("本周") { weekAnchor = today }
        }
    }

    // MARK: - 上班天数

    private func workdayCard(_ snap: WeekSnapshot) -> some View {
        PaperCard(padding: 16, showsGrid: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("本周上班")
                    Spacer()
                    Text("\(snap.workdays) 天")
                        .font(Theme.serif(18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(snap.isOverridden ? "已手动设置" : "跟随大小周规则")
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.inkSecondary)
                }

                HStack(spacing: 6) {
                    chip("自动", selected: !snap.isOverridden) {
                        store.setWorkdaysOverride(weekKey: snap.weekKey, value: nil)
                    }
                    ForEach([4, 5, 6], id: \.self) { n in
                        chip("\(n) 天", selected: snap.entry?.workdaysOverride == n) {
                            store.setWorkdaysOverride(weekKey: snap.weekKey, value: n)
                        }
                    }

                    Spacer()

                    Stepper(value: overrideBinding(for: snap), in: 1...6) {
                        Text("自定义 \(snap.entry?.workdaysOverride ?? snap.workdays)")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - 七天列表

    private func daysCard(_ snap: WeekSnapshot) -> some View {
        PaperCard(padding: 8, showsGrid: false) {
            VStack(spacing: 0) {
                ForEach(Array(snap.days.enumerated()), id: \.element.id) { index, day in
                    Button {
                        selectedDay = IdentifiableDate(date: day.date)
                    } label: {
                        dayRow(day)
                    }
                    .buttonStyle(.plain)

                    if index < snap.days.count - 1 {
                        Hairline().padding(.leading, 12)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: DaySnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(CalendarMath.weekdaySymbol(for: day.date))
                    .font(Theme.label(10))
                    .foregroundStyle(day.isWorkday ? Theme.inkSecondary : Theme.inkSecondary.opacity(0.55))
                Text("\(CalendarMath.calendar.component(.day, from: day.date))")
                    .font(Theme.serif(16, weight: day.isToday ? .semibold : .regular))
                    .foregroundStyle(day.isToday ? Theme.accent : Theme.ink)
            }
            .frame(width: 30)

            Text(day.hasSummary ? (day.entry?.summaryPreview ?? "") : "—")
                .font(Theme.sans(12))
                .foregroundStyle(day.hasSummary ? Theme.ink : Theme.inkSecondary.opacity(0.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if day.taskTotal > 0 {
                HStack(spacing: 6) {
                    ThinProgressBar(
                        value: Double(day.taskDone) / Double(day.taskTotal),
                        height: 2
                    )
                    .frame(width: 42)
                    Text("\(day.taskDone)/\(day.taskTotal)")
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.inkSecondary)
                }
            } else if !day.isWorkday {
                Text("休息")
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(day.isToday ? Theme.todayFill : (day.isWorkday ? .clear : Theme.restDayFill))
        }
        .contentShape(Rectangle())
    }

    // MARK: - 周总结

    private func summaryCard(_ snap: WeekSnapshot) -> some View {
        PaperCard(padding: 16, showsGrid: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("本周总结")
                    Spacer()
                    Text("\(summaryBinding(for: snap.weekKey).wrappedValue.count) 字")
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.8))
                }

                PlainTextEditor(text: summaryBinding(for: snap.weekKey))
                    .frame(height: 170)
                    .overlay(alignment: .topLeading) {
                        if summaryBinding(for: snap.weekKey).wrappedValue.isEmpty {
                            Text("这一周的关键词、做完的事、没做好的地方……")
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.inkSecondary.opacity(0.55))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func statsLine(_ snap: WeekSnapshot) -> some View {
        HStack(spacing: 8) {
            Text("有记录 \(snap.hasRecord) 天")
            dot
            Text("计划 \(snap.taskDone)/\(snap.taskTotal)")
            dot
            Text("上班 \(snap.workdays) 天")
            dot
            Text("休息 \(snap.restDays) 天")
            Spacer()
        }
        .font(Theme.sans(11))
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 4)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Theme.inkSecondary.opacity(0.6))
    }

    // MARK: - 控件

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.paper : Theme.inkSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Theme.ink.opacity(0.82) : Theme.ink.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

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
