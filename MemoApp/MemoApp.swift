import SwiftUI

@main
struct MemoApp: App {
    @State private var store = Store.shared

    var body: some Scene {
        // 用单实例 Window（而非 WindowGroup），避免每个深链都开一个新窗口
        Window("Memo", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 720)
        .handlesExternalEvents(matching: ["memo"])
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
