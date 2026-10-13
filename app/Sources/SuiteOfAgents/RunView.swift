import SuiteCore
import SwiftUI

struct RunView: View {
    @Environment(AppModel.self) private var model
    var state: RunState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                TaskListView(state: state)
                    .frame(minWidth: 520, idealWidth: 660, maxWidth: .infinity)
                InspectorView(state: state)
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 470)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.goal.isEmpty ? "Run" : state.goal)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        RunStatusBadge(status: state.status)
                        if state.mock { Pill(text: "Offline mock", systemImage: "wifi.slash", tint: .orange) }
                        if let d = state.createdAt {
                            Text(d.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                        }
                        if state.loading { ProgressView().controlSize(.small) }
                    }
                }
                Spacer()
                if state.isActive {
                    Button(role: .cancel) { model.cancelRun() } label: {
                        Label(state.status == "canceling" ? "Canceling…" : "Cancel Run", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                    .disabled(state.status == "canceling")
                }
            }
            BudgetBar(spent: state.spentUsd, cap: state.maxCostUsd, tasks: state.tasksDone, maxTasks: state.maxTasks)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Task list

struct TaskListView: View {
    @Environment(AppModel.self) private var model
    var state: RunState

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("#").frame(width: 24, alignment: .trailing)
                Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                Text("Kind").frame(width: 92, alignment: .leading)
                Text("Status").frame(width: 84, alignment: .leading)
                Text("Score").frame(width: 50, alignment: .center)
                Text("Your Rating").frame(width: 72, alignment: .center)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            Divider()

            if state.tasks.isEmpty {
                VStack(spacing: 10) {
                    if state.isActive {
                        ProgressView()
                        Text("The CEO is planning the work…").foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "list.bullet.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("No tasks in this run.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $state.selectedTaskID) {
                    ForEach(state.tasks) { task in
                        TaskRow(task: task, state: state).tag(task.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    var task: SuiteTask
    var state: RunState

    var body: some View {
        HStack(spacing: 10) {
            Text("\(task.seq)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body.weight(.medium)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Image(systemName: Naming.agentSymbol(task.agent ?? "")).imageScale(.small)
                    Text(model.agentName(task.agent))
                    if task.variant != nil {
                        Text("·")
                        Text(Naming.variantName(task.variant))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            KindChip(kind: task.kind, compact: true).frame(width: 92, alignment: .leading)
            StatusLabel(status: task.status).frame(width: 84, alignment: .leading)
            ScoreBadge(score: task.judgeScore).frame(width: 50)
            RatingButtons(task: task, state: state).frame(width: 72)
        }
        .padding(.vertical, 5)
    }
}

struct RatingButtons: View {
    @Environment(AppModel.self) private var model
    var task: SuiteTask
    var state: RunState

    var body: some View {
        HStack(spacing: 4) {
            button(.up, symbol: "hand.thumbsup", tint: .green, help: "Good result")
            button(.down, symbol: "hand.thumbsdown", tint: .red, help: "Poor result")
        }
        .disabled(task.status != .done && task.status != .failed)
    }

    private func button(_ r: UserRating, symbol: String, tint: Color, help: String) -> some View {
        let on = task.rating == r
        return Button {
            model.rate(task, r, in: state)
        } label: {
            Image(systemName: on ? symbol + ".fill" : symbol)
                .foregroundStyle(on ? tint : Color.secondary)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? tint.opacity(0.14) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Clear your rating" : help)
        .accessibilityLabel(r == .up ? "Thumbs up" : "Thumbs down")
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    var state: RunState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let id = state.selectedTaskID, let task = state.tasks.first(where: { $0.id == id }) {
                    TaskDetail(task: task, state: state)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Report", systemImage: "doc.richtext")
                        if let report = state.report, !report.isEmpty {
                            MarkdownView(text: report)
                        } else {
                            Text(state.isActive ? "The CEO writes the report when the run finishes." : "This run has no report.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TaskDetail: View {
    @Environment(AppModel.self) private var model
    var task: SuiteTask
    var state: RunState

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    KindChip(kind: task.kind)
                }
                HStack(spacing: 12) {
                    Label(model.agentName(task.agent), systemImage: Naming.agentSymbol(task.agent ?? ""))
                    Pill(text: Naming.variantName(task.variant), systemImage: "cpu")
                    StatusLabel(status: task.status)
                    Spacer()
                    if let c = task.costUsd {
                        Text(Naming.dollars(c)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .font(.callout)

                if let d = task.description, !d.isEmpty {
                    field("Task", d)
                }
                if let s = task.summary, !s.isEmpty {
                    field("Result", s)
                }
                if task.judgeScore != nil || task.judgeRationale != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SectionHeader(title: "Reviewer")
                            ScoreBadge(score: task.judgeScore)
                            Spacer()
                            RatingButtons(task: task, state: state)
                        }
                        if let r = task.judgeRationale {
                            Text(r).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                }
                if let samples = state.samples[task.id], !samples.isEmpty {
                    SamplesView(samples: samples, chosen: task.agent)
                }
                if let notes = state.activity[task.id], !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Activity")
                        ForEach(notes.suffix(12)) { n in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: n.icon).foregroundStyle(.secondary).imageScale(.small)
                                Text(n.text).font(.callout).lineLimit(3)
                            }
                        }
                    }
                }
                HStack {
                    if let path = task.outputPath, !path.isEmpty {
                        Button {
                            let folder = state.runFolder ?? SuitePaths.runFolder(dataFolder: model.dataFolder, runId: state.id)
                            model.reveal(SuitePaths.outputURL(outputPath: path, runFolder: folder))
                        } label: {
                            Label("Open Output", systemImage: "folder")
                        }
                        Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }

    private func field(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title)
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

/// Thompson samples drawn when the task was routed: why this agent won.
struct SamplesView: View {
    @Environment(AppModel.self) private var model
    var samples: [String: Double]
    var chosen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(title: "Why this agent")
            ForEach(Array(samples.sorted { $0.value > $1.value }.prefix(5)), id: \.key) { agent, value in
                HStack(spacing: 8) {
                    Text(model.agentName(agent))
                        .font(.callout.weight(agent == chosen ? .semibold : .regular))
                        .frame(width: 140, alignment: .leading)
                        .lineLimit(1)
                    Meter(fraction: value, tint: agent == chosen ? .accentColor : .secondary)
                    Text(String(format: "%.2f", value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            Text(samples.count > 5 ? "Top 5 of \(samples.count). Each agent's skill was sampled from its posterior; the highest sample won." : "Each agent's skill was sampled from its posterior; the highest sample won.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
