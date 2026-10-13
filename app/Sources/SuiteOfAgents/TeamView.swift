import SuiteCore
import SwiftUI

struct TeamView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Team").font(.largeTitle.weight(.bold))
                        Text("Specialists the bandit can route tasks to. Each agent is a YAML file you can edit.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.openAgentsFolder() } label: {
                        Label("Open Agents Folder", systemImage: "folder")
                    }
                    .controlSize(.large)
                }

                if model.agents.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(model.agents) { AgentCard(agent: $0) }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if model.isRefreshing { ProgressView() }
            Text(model.isRefreshing ? "Loading the team…" : "No agents yet. They're created the first time the engine runs.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct AgentCard: View {
    @Environment(AppModel.self) private var model
    var agent: AgentInfo

    var body: some View {
        let accent: Color = agent.skills.first.map { Color.kind($0, family: model.kindFamily($0)) } ?? .secondary
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: Naming.agentSymbol(agent.id))
                        .font(.title2)
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name).font(.headline)
                        if !agent.routable {
                            Text(agent.id == "reviewer" ? "Judge · not routed" : "Planner · not routed")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(agent.skills.count) skills · \(agent.variants.count) model variants")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Text(agent.role)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 34, alignment: .topLeading)
                if !agent.skills.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(agent.skills, id: \.self) { KindChip(kind: $0, compact: true) }
                    }
                }
                if !agent.variants.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(agent.variants, id: \.self) { Pill(text: Naming.variantName($0), systemImage: "cpu") }
                    }
                }
            }
        }
    }
}
