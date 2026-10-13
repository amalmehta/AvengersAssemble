import AppKit
import SuiteCore
import SwiftUI

@main
enum Entry {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--screenshots") {
            let dir = i + 1 < args.count ? args[i + 1] : "screenshots"
            ScreenshotRenderer.run(outputDirectory: URL(fileURLWithPath: dir, isDirectory: true))
        } else {
            SuiteOfAgentsApp.main()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run` (no bundle): show in the Dock and come forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.terminate() }
    }
}

struct SuiteOfAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Suite of Agents", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Run") { model.selection = .newRun }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Upload Files…") { model.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Run") {
                Button("Start") { model.startRun() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canStart)
                Button("Cancel Run") { model.cancelRun() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!(model.liveRun?.isActive ?? false))
                Divider()
                Button("Refresh") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
