import AppKit
import SuiteCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var keyMessage: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.hasAPIKey {
                    LabeledContent("API key") {
                        HStack {
                            Label("Saved in your Keychain", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Remove", role: .destructive) { model.removeAPIKey(); keyMessage = nil }
                        }
                    }
                }
                LabeledContent(model.hasAPIKey ? "Replace key" : "API key") {
                    HStack {
                        SecureField("", text: $keyDraft, prompt: Text("sk-ant-…"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey).disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let keyMessage { Text(keyMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Anthropic API")
            } footer: {
                Text("Stored in the macOS Keychain and passed only to the engine on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Use offline mock (no API calls)", isOn: Binding(
                    get: { model.hasAPIKey ? model.settings.mock : true },
                    set: { model.settings.mock = $0 }))
                    .disabled(!model.hasAPIKey)
                Text(model.hasAPIKey
                     ? "The mock runs the whole pipeline with canned answers. Handy for trying things out for free."
                     : "No API key is saved, so runs always use the offline mock. Add a key above to make real calls.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Mode") }

            Section {
                LabeledContent("Max cost per run") {
                    HStack(spacing: 6) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("", value: $model.settings.maxCostUsd, format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        Stepper("", value: $model.settings.maxCostUsd, in: 0.1...500, step: 0.5).labelsHidden()
                    }
                }
                LabeledContent("Max tasks per run") {
                    HStack(spacing: 6) {
                        TextField("", value: $model.settings.maxTasks, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        Stepper("", value: $model.settings.maxTasks, in: 1...500).labelsHidden()
                    }
                }
                LabeledContent("Max agent steps") {
                    HStack(spacing: 6) {
                        TextField("", value: $model.settings.maxAgentSteps, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        Stepper("", value: $model.settings.maxAgentSteps, in: 1...100).labelsHidden()
                    }
                }
                LabeledContent("Tasks at once") {
                    HStack(spacing: 6) {
                        TextField("", value: $model.settings.maxParallelTasks, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        Stepper("", value: $model.settings.maxParallelTasks, in: 1...8).labelsHidden()
                    }
                }
                .help("Independent tasks run side by side, up to this many. 1 runs them one at a time.")
            } header: { Text("Budget") }

            Section {
                LabeledContent("Your rating weight") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.userRatingWeight, in: 0...10, step: 0.5).frame(width: 160)
                        Text(String(format: "%.1f×", model.settings.userRatingWeight)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Cost penalty per $") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.costPenaltyPerUsd, in: 0...2, step: 0.05).frame(width: 160)
                        Text(String(format: "%.2f", model.settings.costPenaltyPerUsd)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Task wording weight") {
                    HStack(spacing: 10) {
                        Slider(value: $model.settings.textWeight, in: 0...1, step: 0.1).frame(width: 160)
                        Text(String(format: "%.1f", model.settings.textWeight)).monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("Learning")
            } footer: {
                Text("How much your thumbs-up or thumbs-down outweighs the reviewer's score, how much each dollar spent lowers a result's reward, and how much a task's wording (rather than only its kind) decides who gets it and on which model. 0 routes on kind alone.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                pathRow("uv path", text: $model.uvOverride, placeholder: "Found automatically", directory: false)
                pathRow("Engine folder", text: $model.engineDirOverride, placeholder: "Built into the app", directory: true)
                LabeledContent("Data folder") {
                    HStack {
                        Text(model.dataFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Reveal Data Folder") { model.revealDataFolder() }
                    }
                }
            } header: { Text("Advanced") }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
    }

    private func saveKey() {
        if model.saveAPIKey(keyDraft) {
            keyDraft = ""
            keyMessage = "Saved. New runs will use the Anthropic API unless mock mode is on."
        } else {
            keyMessage = "Couldn't save the key to the Keychain."
        }
    }

    private func pathRow(_ label: String, text: Binding<String>, placeholder: String, directory: Bool) -> some View {
        LabeledContent(label) {
            HStack {
                TextField("", text: text, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    let p = NSOpenPanel()
                    p.canChooseDirectories = directory
                    p.canChooseFiles = !directory
                    p.allowsMultipleSelection = false
                    if directory { p.message = "Choose the engine folder (it contains pyproject.toml)" }
                    if p.runModal() == .OK, let url = p.url { text.wrappedValue = url.path }
                }
            }
        }
    }
}
