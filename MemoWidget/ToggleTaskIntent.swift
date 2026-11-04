import SwiftUI
import AppIntents
import WidgetKit

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "勾选计划"
    static var description = IntentDescription("在小组件里直接勾掉今天的计划")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "日期")
    var dayKey: String

    @Parameter(title: "任务")
    var taskID: String

    init() {}

    init(dayKey: String, taskID: String) {
        self.dayKey = dayKey
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: taskID) {
            StoreFile.toggleTask(dayKey: dayKey, taskID: uuid)
        }
        return .result()
    }
}
