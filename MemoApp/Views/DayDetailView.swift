import SwiftUI

struct DayDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var current: Date
    @State private var newTask = ""
    @State private var today = Date()
    @State private var summaryDraft = ""
    @State private var loadedKey = ""
    @State private var commitTask: Task<Void, Never>?
    @FocusState private var addFieldFocused: Bool

    init(date: Date) {
        _current = State(initialValue: CalendarMath.calendar.startOfDay(for: date))
    }

    private var key: String { CalendarMath.dateKey(current) }
    private var snapshot: DaySnapshot { store.daySnapshot(for: current, today: today) }
    private var tasks: [PlanTask] { store.dayEntry(key)?.tasks ?? [] }

    // MARK: - 总结草稿（打字不直接写库，防抖后再提交）

    private func loadDraft() {
        guard loadedKey != key else { return }
        flush(commitTo: loadedKey)
        summaryDraft = store.dayEntry(key)?.summary ?? ""
        loadedKey = key
    }

    /// 把草稿写回指定日期（默认当前日期）；内容没变就什么都不做
    private func flush(commitTo targetKey: String? = nil) {
        commitTask?.cancel()
        commitTask = nil
        let dayKey = targetKey ?? key
        guard !dayKey.isEmpty, dayKey == loadedKey || targetKey == nil else { return }
        let draft = summaryDraft
        guard (store.dayEntry(dayKey)?.summary ?? "") != draft else { return }
        store.updateDay(dayKey) { $0.summary = draft }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        let draft = summaryDraft
        let dayKey = key
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            guard (store.dayEntry(dayKey)?.summary ?? "") != draft else { return }
            store.updateDay(dayKey) { $0.summary = draft }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            summarySection
            Hairline()
            taskSection
        }
        .frame(width: 660, height: 660)
        .background(Theme.paper)
        .onAppear {
            today = Date()
            loadDraft()
        }
        .onChange(of: key) { _, _ in loadDraft() }
        .onChange(of: summaryDraft) { _, _ in scheduleCommit() }
        .onDisappear {
            flush()
            store.saveNow()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(CalendarMath.dayTitle(current))
                    .font(Theme.serif(24, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 8) {
                    Text(workdayBadgeTitle)
                        .font(Theme.sans(10, weight: .medium))
                        .foregroundStyle(snapshot.isWorkday ? Theme.accent : Theme.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(snapshot.isWorkday ? Theme.accent.opacity(0.12) : Theme.ink.opacity(0.06))
                        )

                    overrideMenu

                    if let festival = Festivals.festival(on: current) {
                        Text(festival.name)
                            .font(Theme.sans(10, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.accent.opacity(0.10)))
                    }

                    Text(CalendarMath.weekKey(current) + " · 本周上班 \(store.workdays(forWeekContaining: current)) 天")
                        .font(Theme.sans(10))
                        .foregroundStyle(Theme.inkSecondary)

                    if let savedAt = store.lastSavedAt {
                        Text("已保存 \(timeString(savedAt))")
                            .font(Theme.sans(10))
                            .foregroundStyle(Theme.inkSecondary.opacity(0.8))
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                iconButton("chevron.left") { shift(-1) }
                iconButton("chevron.right") { shift(1) }
            }

            Button("关闭") { close() }
                .buttonStyle(.plain)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.ink.opacity(0.06)))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    // MARK: - 总结

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("总结")
                Spacer()
                Text("\(summaryDraft.count) 字")
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }

            PlainTextEditor(text: $summaryDraft, identity: key)
                .frame(height: 200)
                .overlay(alignment: .topLeading) {
                    if summaryDraft.isEmpty {
                        Text("今天过得怎么样？")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.inkSecondary.opacity(0.55))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - 计划

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("计划")
                Text("\(snapshot.taskDone)/\(tasks.count) 完成")
                    .font(Theme.sans(10))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            if tasks.isEmpty {
                VStack(spacing: 6) {
                    Text("今天还没有计划")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("在下面输入第一件事，回车即添加")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tasks) { task in
                            taskRow(task)
                                .onDrag {
                                    NSItemProvider(object: task.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], isTargeted: nil) { providers in
                                    handleDrop(on: task, providers: providers)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                TextField("添加一项计划，回车确认", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(Theme.sans(13))
                    .focused($addFieldFocused)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.ink.opacity(0.045))
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func taskRow(_ task: PlanTask) -> some View {
        HStack(spacing: 10) {
            Button {
                store.toggleTask(current, taskID: task.id)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(task.done ? Theme.accent : Theme.inkSecondary.opacity(0.7))
            }
            .buttonStyle(.plain)

            Text(task.text)
                .font(Theme.sans(13))
                .foregroundStyle(task.done ? Theme.inkSecondary : Theme.ink)
                .strikethrough(task.done, color: Theme.inkSecondary.opacity(0.6))

            Spacer(minLength: 0)

            Button {
                store.deleteTask(current, taskID: task.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    // MARK: - 例外

    private var workdayBadgeTitle: String {
        guard let override = snapshot.override else {
            return snapshot.isWorkday ? "上班日" : "休息日"
        }
        return override == .work ? "手动·上班" : "手动·休息"
    }

    private var overrideMenu: some View {
        Menu {
            Button("跟随大小周规则") { store.setDayOverride(current, value: nil) }
            Divider()
            Button("标记为上班") { store.setDayOverride(current, value: .work) }
            Button("标记为休息") { store.setDayOverride(current, value: .rest) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 9, weight: .medium))
                Text(snapshot.isManualOverride ? "已设例外" : "设例外")
                    .font(Theme.sans(10, weight: .medium))
            }
            .foregroundStyle(snapshot.isManualOverride ? Theme.accent : Theme.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.ink.opacity(0.05)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - 行为

    private func addTask() {
        store.addTask(to: current, text: newTask)
        newTask = ""
        addFieldFocused = true
    }

    private func handleDrop(on target: PlanTask, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString,
                  let draggedID = UUID(uuidString: text as String) else { return }
            DispatchQueue.main.async {
                store.moveTask(in: current, taskID: draggedID, before: target.id)
            }
        }
        return true
    }

    private func shift(_ days: Int) {
        flush()
        current = CalendarMath.calendar.startOfDay(for: CalendarMath.addDays(days, to: current))
    }

    private func close() {
        flush()
        store.saveNow()
        dismiss()
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
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
}
