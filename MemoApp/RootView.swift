import SwiftUI

struct IdentifiableDate: Identifiable {
    let date: Date
    var id: String { CalendarMath.dateKey(date) }
}

enum RootSection: String, CaseIterable, Identifiable {
    case month, week, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "月"
        case .week: return "周"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .month: return "calendar"
        case .week: return "calendar.badge.clock"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store

    @State private var section: RootSection = .month
    @State private var monthAnchor: Date = CalendarMath.startOfMonth(Date())
    @State private var weekAnchor: Date = Date()
    @State private var selectedDay: IdentifiableDate?
    @State private var today: Date = Date()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Hairline(vertical: true)
            content
        }
        .background(Theme.paper)
        .sheet(item: $selectedDay) { item in
            DayDetailView(date: item.date)
                .environment(store)
        }
        .onOpenURL { handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = Date()
                store.saveNow()
            } else if phase == .background {
                store.saveNow()
            }
        }
        .overlay(alignment: .top) {
            if let error = store.lastError {
                Text(error)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.92), in: Capsule())
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        VStack(spacing: 8) {
            Text("MEMO")
                .font(Theme.serif(12, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 36)
                .padding(.bottom, 20)

            ForEach(RootSection.allCases) { item in
                Button {
                    section = item
                    if item == .week { weekAnchor = today }
                    if item == .month { monthAnchor = CalendarMath.startOfMonth(today) }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .regular))
                        Text(item.title)
                            .font(Theme.sans(11))
                    }
                    .foregroundStyle(section == item ? Theme.ink : Theme.inkSecondary)
                    .frame(width: 60, height: 52)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(section == item ? Theme.ink.opacity(0.06) : .clear)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(CalendarMath.monthTitle(today))")
                    .font(Theme.serif(11))
                Text(CalendarMath.weekdaySymbol(for: today))
                    .font(Theme.sans(10))
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.bottom, 18)
        }
        .frame(width: Theme.sidebarWidth)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch section {
        case .month:
            MonthView(monthAnchor: $monthAnchor,
                      selectedDay: $selectedDay,
                      today: today,
                      onOpenWeek: { weekAnchor in
                          self.weekAnchor = weekAnchor
                          section = .week
                      })
        case .week:
            WeekView(weekAnchor: $weekAnchor,
                     selectedDay: $selectedDay,
                     today: today)
        case .settings:
            SettingsView()
        }
    }

    // MARK: - 深链

    private func handle(_ url: URL) {
        guard url.scheme == "memo" else { return }
        switch url.host {
        case "today":
            today = Date()
            section = .month
            monthAnchor = CalendarMath.startOfMonth(today)
            selectedDay = nil
        case "day":
            let key = url.pathComponents.dropFirst().joined(separator: "/")
            if let date = CalendarMath.date(fromKey: key) {
                section = .month
                monthAnchor = CalendarMath.startOfMonth(date)
                selectedDay = IdentifiableDate(date: date)
            }
        default:
            break
        }
    }
}
