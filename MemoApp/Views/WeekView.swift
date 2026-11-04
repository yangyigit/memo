import SwiftUI

struct WeekView: View {
    @Environment(Store.self) private var store

    @Binding var weekAnchor: Date
    @Binding var selectedDay: IdentifiableDate?
    var today: Date

    @State private var summaryDraft = ""
    @State private var loadedWeekKey = ""
    @State private var commitTask: Task<Void, Never>?

    private var snapshot: WeekSnapshot {
        store.weekSnapshot(containing: weekAnchor, today: today)
    }

    // MARK: - 周总结草稿（打字不直接写库，防抖后再提交）

    private func loadDraft(_ weekKey: String) {
        guard loadedWeekKey != weekKey else { return }
        flush(commitTo: loadedWeekKey)
        summaryDraft = store.weekEntry(weekKey)?.summary ?? ""
        loadedWeekKey = weekKey
    }

    private func flush(commitTo targetKey: String? = nil) {
        commitTask?.cancel()
        commitTask = nil
        let key = targetKey ?? loadedWeekKey
        guard !key.isEmpty else { return }
        let draft = summaryDraft
        guard (store.weekEntry(key)?.summary ?? "") != draft else { return }
        store.setWeekSummary(weekKey: key, text: draft)
    }

    private func scheduleCommit(_ weekKey: String) {
        commitTask?.cancel()
        let draft = summaryDraft
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            guard (store.weekEntry(weekKey)?.summary ?? "") != draft else { return }
            store.setWeekSummary(weekKey: weekKey, text: draft)
        }
    }

    /// 只针对「基准天数」，不要用 snap.workdays（那是含单日例外的实际天数）
    private func baseWorkdays(_ snap: WeekSnapshot) -> Int {
        store.baseWorkdays(forWeekContaining: snap.monday)
    }

    private func overrideBinding(for snap: WeekSnapshot) -> Binding<Int> {
        Binding(
            get: { store.weekEntry(snap.weekKey)?.workdaysOverride ?? baseWorkdays(snap) },
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
        .onAppear { loadDraft(snap.weekKey) }
        .onChange(of: snap.weekKey) { _, newKey in loadDraft(newKey) }
        .onChange(of: summaryDraft) { _, _ in scheduleCommit(snap.weekKey) }
        .onDisappear { flush() }
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

            iconButton("chevron.left") {
                flush()
                weekAnchor = CalendarMath.addWeeks(-1, to: weekAnchor)
            }
            iconButton("chevron.right") {
                flush()
                weekAnchor = CalendarMath.addWeeks(1, to: weekAnchor)
            }
            textButton("本周") {
                flush()
                weekAnchor = today
            }
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
                    Text(sourceText(snap))
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.inkSecondary)
                }

                HStack(spacing: 6) {
                    chip("自动", selected: !snap.isOverridden) {
                        store.setWorkdaysOverride(weekKey: snap.weekKey, value: nil)
                    }
                    ForEach([4, 5, 6, 0], id: \.self) { n in
                        chip("\(n) 天", selected: snap.entry?.workdaysOverride == n) {
                            store.setWorkdaysOverride(weekKey: snap.weekKey, value: n)
                        }
                    }

                    Spacer()

                    Stepper(value: overrideBinding(for: snap), in: 0...6) {
                        Text("自定义 \(snap.entry?.workdaysOverride ?? baseWorkdays(snap))")
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

            if let festival = Festivals.festival(on: day.date) {
                Text(festival.name)
                    .font(Theme.sans(9, weight: .medium))
                    .foregroundStyle(festival.isMajor ? Theme.accent : Theme.inkSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill((festival.isMajor ? Theme.accent : Theme.ink).opacity(0.08)))
            }

            Text(day.hasSummary ? (day.entry?.summaryPreview ?? "") : "—")
                .font(Theme.sans(12))
                .foregroundStyle(day.hasSummary ? Theme.ink : Theme.inkSecondary.opacity(0.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let override = day.override {
                Text(override.badge)
                    .font(Theme.sans(9, weight: .medium))
                    .foregroundStyle(override == .work ? Theme.accent : Theme.inkSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill((override == .work ? Theme.accent : Theme.ink).opacity(0.10))
                    )
            }

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
            } else if !day.isWorkday && !day.isManualOverride {
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
                    Text("\(summaryDraft.count) 字")
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.8))
                }

                PlainTextEditor(text: $summaryDraft,
                                identity: snap.weekKey,
                                placeholder: "这一周的关键词、做完的事、没做好的地方……")
                    .frame(height: 170)
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
            if snap.manualDays > 0 {
                dot
                Text("例外 \(snap.manualDays) 天")
            }
            Spacer()
        }
        .font(Theme.sans(11))
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 4)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Theme.inkSecondary.opacity(0.6))
    }

    private func sourceText(_ snap: WeekSnapshot) -> String {
        var parts: [String] = []
        if snap.isOverridden {
            parts.append("已手动设置")
        } else {
            parts.append("跟随大小周规则")
        }
        if snap.manualDays > 0 {
            parts.append("含 \(snap.manualDays) 天例外")
        }
        return parts.joined(separator: " · ")
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
