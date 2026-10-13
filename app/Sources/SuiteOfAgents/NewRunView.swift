import AppKit
import SuiteCore
import SwiftUI

/// Plain-text editor that does NOT accept dropped files, so file drops fall through to the
/// window-wide drop target instead of being inserted as paths.
final class GoalTextView: NSTextView {
    var placeholder = ""

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter {
            $0 != .fileURL && $0 != .URL && $0 != NSPasteboard.PasteboardType("NSFilenamesPboardType")
                && $0 != .tiff && $0 != .png && $0 != .fileContents
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholder.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: 15),
            ]
            let inset = textContainerInset
            let pad = textContainer?.lineFragmentPadding ?? 5
            let rect = NSRect(x: inset.width + pad, y: inset.height, width: bounds.width - 2 * (inset.width + pad), height: bounds.height)
            (placeholder as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs)
        }
    }
}

struct GoalEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = GoalTextView()
        tv.placeholder = placeholder
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        tv.string = text
        tv.setAccessibilityLabel("Goal")
        tv.updateDragTypeRegistration()
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? GoalTextView else { return }
        if tv.string != text { tv.string = text; tv.needsDisplay = true }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GoalEditor
        init(_ p: GoalEditor) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            tv.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // ⌘↩ starts the run.
            if selector == #selector(NSResponder.insertNewline(_:)),
               NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

struct AttachmentChip: View {
    var url: URL
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: url.pathExtension) ?? .data))
                .resizable().frame(width: 16, height: 16)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(url.lastPathComponent)")
        }
        .font(.callout)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .fixedSize()
        .help(url.path)
    }
}

struct NewRunView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New Run").font(.largeTitle.weight(.bold))
                    Text("Give the company a goal. The CEO plans the work, the bandit picks who does each task and on which model, and the reviewer scores every result.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 0) {
                    GoalEditor(text: $model.draftGoal,
                               placeholder: "e.g. Launch a company that sells a home robot that folds laundry",
                               onSubmit: { model.startRun() })
                        .frame(minHeight: 150, maxHeight: 240)

                    if !model.attachments.isEmpty {
                        Divider().padding(.horizontal, 10)
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(model.attachments, id: \.self) { url in
                                AttachmentChip(url: url) { model.detach(url) }
                            }
                        }
                        .padding(10)
                    }

                    Divider()
                    HStack(spacing: 10) {
                        Button {
                            model.presentOpenPanel()
                        } label: {
                            Label("Upload…", systemImage: "paperclip")
                        }
                        .help("Attach files for the agents to use")
                        Text("or drop files anywhere, or paste with ⌘V")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(10)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))

                HStack(spacing: 12) {
                    if model.effectiveMock {
                        Pill(text: "Offline mock", systemImage: "wifi.slash", tint: .orange)
                            .help(model.hasAPIKey ? "Mock mode is on in Settings." : "No API key saved, so runs use the offline mock. Add one in Settings.")
                    } else {
                        Pill(text: "Live API", systemImage: "bolt.fill", tint: .green)
                    }
                    Text("Up to \(Naming.dollars(model.settings.maxCostUsd)) and \(model.settings.maxTasks) tasks")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Text("Change…")
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    Spacer()
                    if let live = model.liveRun, live.isActive {
                        Button(role: .cancel) { model.cancelRun() } label: {
                            Label("Cancel Run", systemImage: "stop.fill")
                        }
                        .controlSize(.large)
                        .disabled(live.status == "canceling")
                    }
                    Button {
                        model.startRun()
                    } label: {
                        Label("Start", systemImage: "play.fill").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canStart)
                    .help(model.liveRun?.isActive == true ? "A run is already in progress" : "Start the run (⌘↩)")
                }

                if let live = model.liveRun, live.isActive {
                    Button {
                        model.selection = .run(live.id)
                    } label: {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Running: \(live.goal)").lineLimit(1)
                            Spacer()
                            Text("\(live.tasksDone) tasks · \(Naming.dollars(live.spentUsd))").monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
    }
}
