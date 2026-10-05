import AppKit
import SwiftUI

@main struct VNLauncherApp: App {
    @State private var store = LibraryStore()
    private var testWidth: CGFloat {
        ProcessInfo.processInfo.environment["VNLAUNCHER_DEMO"] == "1"
            ? CGFloat(Double(ProcessInfo.processInfo.environment["VNLAUNCHER_TEST_WIDTH"] ?? "1180") ?? 1180) : 1180
    }
    private var testHeight: CGFloat {
        ProcessInfo.processInfo.environment["VNLAUNCHER_DEMO"] == "1"
            ? CGFloat(Double(ProcessInfo.processInfo.environment["VNLAUNCHER_TEST_HEIGHT"] ?? "780") ?? 780) : 780
    }
    var body: some Scene {
        WindowGroup {
            LibraryView(store: store).frame(minWidth: 900, minHeight: 650).preferredColorScheme(.light)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar).defaultSize(width: testWidth, height: testHeight)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入游戏…") { store.importFile() }.keyboardShortcut("o")
                Button("发现 Steam 游戏…") { store.discoverSteam() }
            }
        }
    }
}
