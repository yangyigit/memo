import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(Store.self) private var store

    @State private var exportMessage: String?
    @State private var today = Date()

    private var settings: Settings { store.data.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置")
                    .font(Theme.serif(30, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                workweekCard
                dataCard
                diagnosticsCard
                aboutCard

                Spacer(minLength: 0)
            }
            .padding(Theme.pagePadding)
        }
        .onAppear { today = Date() }
    }

    // MARK: - 大小周

    private var workweekCard: some View {
        PaperCard(padding: 16, showsGrid: false) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("大小周规则")

                row("大周上班天数") {
                    Stepper(value: Binding(
                        get: { settings.bigWeekDays },
                        set: { value in store.updateSettings { $0.bigWeekDays = value } }
                    ), in: 1...6) {
                        Text("\(settings.bigWeekDays) 天")
                            .font(Theme.serif(14))
                            .foregroundStyle(Theme.ink)
                    }
                    .fixedSize()
                }

                row("小周上班天数") {
                    Stepper(value: Binding(
                        get: { settings.smallWeekDays },
                        set: { value in store.updateSettings { $0.smallWeekDays = value } }
                    ), in: 1...6) {
                        Text("\(settings.smallWeekDays) 天")
                            .font(Theme.serif(14))
                            .foregroundStyle(Theme.ink)
                    }
                    .fixedSize()
                }

                row("按大小周交替") {
                    Toggle("", isOn: Binding(
                        get: { settings.alternating },
                        set: { value in store.updateSettings { $0.alternating = value } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Hairline()

                row("锚点周（该周为大周）") {
                    HStack(spacing: 8) {
                        Text(anchorDescription)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.inkSecondary)
                        Button("设为本周") {
                            store.updateSettings { $0.bigWeekAnchor = CalendarMath.weekKey(Date()) }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.sans(11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent.opacity(0.10)))
                    }
                }

                Hairline()

                row("单日例外") {
                    HStack(spacing: 8) {
                        Text(store.dayOverrideCount == 0 ? "没有" : "\(store.dayOverrideCount) 天")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.inkSecondary)
                        if store.dayOverrideCount > 0 {
                            Button("清除全部") { store.clearDayOverrides() }
                                .buttonStyle(.plain)
                                .font(Theme.sans(11, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Theme.accent.opacity(0.10)))
                        }
                    }
                }

                Text("在任意一天的页面里点「设例外」，可以把那天标成上班或休息（调休补班、法定假日、请假）。")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.inkSecondary)

                Hairline()

                Text(previewText)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var anchorDescription: String {
        guard let monday = CalendarMath.monday(fromWeekKey: settings.bigWeekAnchor) else { return "未设置" }
        return "\(settings.bigWeekAnchor) · \(CalendarMath.weekRangeTitle(monday: monday))"
    }

    private var previewText: String {
        let thisWeek = store.workdays(forWeekContaining: today)
        let nextWeek = store.workdays(forWeekContaining: CalendarMath.addWeeks(1, to: today))
        let thisMonday = CalendarMath.startOfWeek(today)
        let nextMonday = CalendarMath.addWeeks(1, to: thisMonday)
        return "本周（\(CalendarMath.weekRangeTitle(monday: thisMonday))）上班 \(thisWeek) 天；下周（\(CalendarMath.weekRangeTitle(monday: nextMonday))）上班 \(nextWeek) 天。基准不含周日，需要周日补班时用单日例外。"
    }

    // MARK: - 数据

    private var dataCard: some View {
        PaperCard(padding: 16, showsGrid: false) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("数据")

                Text(AppInfo.dataDirectory.path)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.inkSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    actionButton("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppInfo.storeURL])
                    }
                    actionButton("导出本月 Markdown") {
                        if let url = store.exportMarkdown(month: today) {
                            exportMessage = "已导出：\(url.lastPathComponent)"
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            exportMessage = store.lastError ?? "导出失败"
                        }
                    }
                    Spacer()
                }

                if let exportMessage {
                    Text(exportMessage)
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - 诊断

    private var diagnosticsCard: some View {
        PaperCard(padding: 16, showsGrid: false) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("诊断")
                diagRow("数据文件", storeFileDescription)
                diagRow("最近保存", store.lastSavedAt.map { timeString($0) } ?? "—")
                diagRow("已记录", "\(store.data.days.filter { !$0.value.isEmpty }.count) 天 / \(store.data.weeks.count) 周")
                diagRow("小组件", "桌面右键 → 编辑小组件 → 搜索 Memo")
            }
        }
    }

    private var storeFileDescription: String {
        let path = AppInfo.storeURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int {
            return "store.json · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        }
        return "store.json · 尚未创建"
    }

    private func diagRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        PaperCard(padding: 16, showsGrid: false) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("关于")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Memo")
                        .font(Theme.serif(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("v1.0 · 本地数据 · 无账号")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 工具

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.ink)
            Spacer()
            content()
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
