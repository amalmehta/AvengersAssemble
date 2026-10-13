import AppKit
import SuiteCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var hostWindow: NSWindow?
    @State private var pasteMonitor: Any?

    /// Screenshot mode draws the same sidebar and detail views side by side in a plain layout,
    /// because offscreen capture can't draw the system's glass sidebar and title bar.
    var screenshotChrome = false

    var body: some View {
        if screenshotChrome {
            decorated(screenshotLayout)
        } else {
            decorated(splitView)
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            detailWithBanner
        }
        .navigationTitle("Suite of Agents")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload runs, team and bandit from the engine")
                .disabled(model.isRefreshing)
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
    }

    private var screenshotLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) {
                        Circle().fill($0).frame(width: 12, height: 12)
                    }
                    Spacer()
                    Image(systemName: "sidebar.left").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
                Sidebar()
            }
            .frame(width: 250)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 18) {
                    Text("Suite of Agents").font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                    Image(systemName: "gearshape")
                }
                .foregroundStyle(.secondary)
                .font(.title3)
                .padding(.horizontal, 20)
                .frame(height: 52)
                Divider()
                detailWithBanner
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detailWithBanner: some View {
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let banner = model.banner {
                    BannerView(banner: banner) { model.banner = nil }
                }
            }
    }

    private func decorated<V: View>(_ content: V) -> some View {
        @Bindable var model = model
        return content
        // Files dropped anywhere on the window are attached.
        .onDrop(of: [.fileURL, .image], isTargeted: $model.dropTargeted, perform: handleDrop)
        .overlay {
            if model.dropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
                    Label("Drop to attach", systemImage: "paperclip")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(8)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FeedbackButton().padding(14)
        }
        .background(WindowReader(window: $hostWindow))
        .onAppear(perform: installPasteMonitor)
        .onDisappear {
            if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
        }
        .task {
            if !model.loadedOnce { await model.refreshAll() }
        }
        .onChange(of: model.selection) { _, new in
            if case let .run(id)? = new, model.runState(for: id) == nil || model.runState(for: id)?.tasks.isEmpty == true,
               !(model.liveRun?.id == id) {
                Task { await model.loadRun(id) }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .newRun, .none:
            NewRunView()
        case .team:
            TeamView()
        case .bandit:
            BanditView()
        case let .run(id):
            if let state = model.runState(for: id) {
                RunView(state: state).id(state.id)
            } else {
                ProgressView("Loading run…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.attach([url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
                    let finish: (Data?) -> Void = { d in
                        guard let d else { return }
                        Task { @MainActor in
                            if let png = NSBitmapImageRep(data: d)?.representation(using: .png, properties: [:]),
                               let url = model.writeTempImage(png) { model.attach([url]) }
                        }
                    }
                    if let data { finish(data) } else {
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { d, _ in finish(d) }
                    }
                }
            }
        }
        return handled
    }

    /// ⌘V with files or an image on the pasteboard attaches them, wherever focus is in the main window.
    private func installPasteMonitor() {
        guard pasteMonitor == nil, !model.isDemo else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v",
                  let w = hostWindow, event.window === w else { return event }
            return model.pasteFromPasteboard() ? nil : event
        }
    }
}

/// Captures the hosting NSWindow.
struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { window = v.window }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if v.window !== window { DispatchQueue.main.async { window = v.window } }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                Label("New Run", systemImage: "plus.circle").tag(SidebarItem.newRun)
                Label("Team", systemImage: "person.3").tag(SidebarItem.team)
                Label("Bandit", systemImage: "chart.bar.xaxis").tag(SidebarItem.bandit)
            }
            Section("Runs") {
                if let live = model.liveRun, !model.runs.contains(where: { $0.id == live.id }) {
                    RunSidebarRow(goal: live.goal, status: live.status, date: live.createdAt, spent: live.spentUsd, live: live.isActive)
                        .tag(SidebarItem.run(live.id))
                }
                ForEach(model.runs) { run in
                    let live = model.liveRun?.id == run.id ? model.liveRun : nil
                    RunSidebarRow(goal: run.goal, status: live?.status ?? run.status, date: run.createdDate,
                                  spent: live?.spentUsd ?? run.spentUsd, live: live?.isActive ?? false)
                        .tag(SidebarItem.run(run.id))
                }
                if model.runs.isEmpty && model.liveRun == nil {
                    Text(model.isRefreshing ? "Loading…" : "No runs yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

struct RunSidebarRow: View {
    var goal: String
    var status: String
    var date: Date?
    var spent: Double
    var live: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if live {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon).foregroundStyle(tint)
                }
            }
            .frame(width: 16)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.isEmpty ? "Untitled run" : goal).lineLimit(2)
                HStack(spacing: 4) {
                    if let date { Text(date.formatted(.relative(presentation: .named))) }
                    Text("·")
                    Text(Naming.dollars(spent)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "budget": return "gauge.with.dots.needle.100percent"
        case "canceled": return "stop.circle"
        case "error": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private var tint: Color {
        switch status {
        case "done": return .green
        case "budget": return .orange
        case "error": return .red
        default: return .secondary
        }
    }
}

struct FeedbackButton: View {
    @Environment(AppModel.self) private var model
    @State private var open = false
    @State private var text = ""
    @State private var thanks = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            Label("Feedback", systemImage: "bubble.left")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Send feedback about Suite of Agents")
        .popover(isPresented: $open, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                if thanks {
                    Label("Thanks! Your feedback was saved.", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    Text("Feedback").font(.headline)
                    Text("What's working, what isn't? Saved on this Mac only.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Your thoughts…", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Cancel") { open = false }
                        Button("Send") {
                            if model.sendFeedback(text) {
                                thanks = true
                                text = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { open = false; thanks = false }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(14)
            .frame(width: 320)
        }
    }
}
