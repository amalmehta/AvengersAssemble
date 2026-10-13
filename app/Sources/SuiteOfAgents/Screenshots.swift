import AppKit
import SuiteCore
import SwiftUI

/// `--screenshots <dir>`: renders the main views with demo data, offscreen, in light and dark,
/// via NSHostingView + cacheDisplay (which also draws AppKit-backed controls), then exits.
@MainActor
enum ScreenshotRenderer {
    static func run(outputDirectory dir: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let pages: [(String, SidebarItem)] = [
            ("run", .run(DemoData.runId)),
            ("bandit", .bandit),
            ("team", .team),
            ("new-run", .newRun),
        ]
        var written: [String] = []
        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (name, item) in pages {
                let model = AppModel(demo: true)
                model.selection = item
                let view = MainView(screenshotChrome: true).environment(model).environment(\.controlActiveState, .key)
                let url = dir.appendingPathComponent("\(name)-\(appearanceName).png")
                if renderWindow(view, size: NSSize(width: 1400, height: 900), appearance: appearance, to: url, titled: false) {
                    written.append(url.lastPathComponent)
                }
            }
            let model = AppModel(demo: true)
            let settings = VStack(spacing: 0) {
                ZStack {
                    Text("Settings").font(.headline)
                    HStack(spacing: 8) {
                        ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) {
                            Circle().fill($0).frame(width: 12, height: 12)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 40)
                SettingsView()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(model)
            .environment(\.controlActiveState, .key)
            let url = dir.appendingPathComponent("settings-\(appearanceName).png")
            if renderWindow(settings, size: nil, appearance: appearance, to: url, titled: false, title: "Settings") {
                written.append(url.lastPathComponent)
            }
        }
        print("Wrote \(written.count) screenshots to \(dir.path): \(written.joined(separator: ", "))")
        exit(written.isEmpty ? 1 : 0)
    }

    private static func renderWindow<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance.Name, to url: URL,
                                              titled: Bool, title: String = "Suite of Agents") -> Bool {
        let hosting = NSHostingView(rootView: view)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let contentSize = size ?? hosting.fittingSize
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        let window = ShotWindow(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: style, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(contentSize)
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        if size == nil {
            // Let the form settle, then size the window to fit it.
            pump(0.3)
            window.setContentSize(hosting.fittingSize)
        }
        pump(1.2)
        hosting.layoutSubtreeIfNeeded()
        pump(0.4)

        // Capture the whole window frame view (title bar + toolbar + content).
        let target: NSView = titled ? (window.contentView?.superview ?? hosting) : hosting
        let bounds = target.bounds
        guard let rep = target.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        target.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url); return true } catch {
            FileHandle.standardError.write("Couldn't write \(url.path): \(error)\n".data(using: .utf8)!)
            return false
        }
    }

    private static func pump(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

/// Offscreen borderless window that still counts as key, so controls render in their active style.
final class ShotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
