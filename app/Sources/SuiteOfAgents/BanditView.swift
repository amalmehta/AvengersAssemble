import Charts
import SuiteCore
import SwiftUI

struct BanditView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bandit").font(.largeTitle.weight(.bold))
                    Text("What the company has learned. Each cell is a Beta posterior over how well an agent does a kind of task; routing samples from these, so strong cells win more often while weak ones still get tried.")
                        .font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let b = model.bandit, !b.routing.isEmpty || !b.variants.isEmpty {
                    Card { RoutingHeatmap(snapshot: b) }
                    Card { VariantSection(snapshot: b) }
                } else {
                    VStack(spacing: 10) {
                        if model.isRefreshing { ProgressView() }
                        Text(model.isRefreshing ? "Loading…" : "Nothing learned yet. Finish a run to see the posteriors here.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - Heatmap

struct RoutingHeatmap: View {
    @Environment(AppModel.self) private var model
    var snapshot: BanditSnapshot

    private var kinds: [String] {
        let present = Set(snapshot.routing.map(\.kind))
        let base = snapshot.kinds.isEmpty ? Array(present) : snapshot.kinds
        return base.filter { present.contains($0) }.sorted { KindCatalog.order($0) < KindCatalog.order($1) }
    }

    private var agents: [String] {
        let present = Set(snapshot.routing.map(\.agent))
        var ordered = model.agents.map(\.id).filter { present.contains($0) }
        for a in snapshot.routing.map(\.agent) where !ordered.contains(a) { ordered.append(a) }
        return ordered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Who gets which work", systemImage: "square.grid.3x3.fill")
                Spacer()
                legend
            }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Color.clear.frame(width: 96, height: 1).gridCellUnsizedAxes(.vertical)
                    ForEach(agents, id: \.self) { a in
                        VStack(spacing: 3) {
                            Image(systemName: Naming.agentSymbol(a)).foregroundStyle(.secondary)
                            Text(model.agentName(a))
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottom)
                    }
                }
                ForEach(kinds, id: \.self) { kind in
                    GridRow {
                        KindChip(kind: kind, compact: true)
                            .frame(width: 96, alignment: .leading)
                        ForEach(agents, id: \.self) { a in
                            HeatCell(arm: snapshot.arm(kind: kind, agent: a), color: .kind(kind, family: model.kindFamily(kind)))
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Mean reward").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach([0.1, 0.3, 0.5, 0.7, 0.9], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(HeatCell.opacity(v))).frame(width: 16, height: 10)
                }
            }
            Text("0 → 1").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HeatCell: View {
    var arm: RoutingArm?
    var color: Color
    @Environment(\.colorScheme) private var scheme

    static func opacity(_ mean: Double) -> Double { 0.10 + 0.80 * pow(min(max(mean, 0), 1), 1.4) }

    var body: some View {
        if let arm {
            let strong = arm.mean >= 0.72
            VStack(spacing: 1) {
                Text(String(format: "%.2f", arm.mean)).font(.callout.monospacedDigit().weight(.semibold))
                Text("n = \(arm.n)").font(.caption2.monospacedDigit()).opacity(0.85)
            }
            .foregroundStyle(strong ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(Self.opacity(arm.mean))))
            .help("α \(String(format: "%.1f", arm.alpha)) · β \(String(format: "%.1f", arm.beta))")
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

// MARK: - Variants

struct VariantSection: View {
    @Environment(AppModel.self) private var model
    var snapshot: BanditSnapshot

    private var agentOrder: [String] {
        var out = model.agents.map(\.id).filter { id in snapshot.variants.contains { $0.agent == id } }
        for a in snapshot.variants.map(\.agent) where !out.contains(a) { out.append(a) }
        return out
    }

    private var variantOrder: [String] {
        let known = ["opus-high", "sonnet-medium", "haiku"]
        var out = known.filter { v in snapshot.variants.contains { $0.variant == v } }
        for v in snapshot.variants.map(\.variant) where !out.contains(v) { out.append(v) }
        return out
    }

    private static let variantColors: [Color] = [.indigo.opacity(0.85), .teal, .gray]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Which model each agent uses", systemImage: "cpu")
            Chart {
                ForEach(snapshot.variants, id: \.self) { v in
                    BarMark(x: .value("Agent", model.agentName(v.agent)),
                            y: .value("Mean", v.mean))
                        .foregroundStyle(by: .value("Variant", Naming.variantName(v.variant)))
                        .position(by: .value("Variant", Naming.variantName(v.variant)))
                        .cornerRadius(3)
                    RuleMark(x: .value("Agent", model.agentName(v.agent)),
                             yStart: .value("Low", max(0, v.mean - v.standardDeviation)),
                             yEnd: .value("High", min(1, v.mean + v.standardDeviation)))
                        .position(by: .value("Variant", Naming.variantName(v.variant)))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
            .chartForegroundStyleScale(domain: variantOrder.map { Naming.variantName($0) },
                                       range: Array(Self.variantColors.prefix(max(variantOrder.count, 1))) + Array(repeating: Color.secondary, count: max(0, variantOrder.count - 3)))
            .chartXScale(domain: agentOrder.map { model.agentName($0) })
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)

            Text("Bars show the posterior mean reward, whiskers ±1 standard deviation.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            table
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Agent")
                ForEach(variantOrder, id: \.self) { Text(Naming.variantName($0)) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(agentOrder, id: \.self) { agent in
                GridRow {
                    Label(model.agentName(agent), systemImage: Naming.agentSymbol(agent))
                        .font(.callout)
                        .lineLimit(1)
                    ForEach(variantOrder, id: \.self) { variant in
                        if let v = snapshot.variants.first(where: { $0.agent == agent && $0.variant == variant }) {
                            HStack(spacing: 8) {
                                Meter(fraction: v.mean, tint: .accentColor).frame(width: 70)
                                Text(String(format: "%.2f", v.mean)).font(.callout.monospacedDigit().weight(.medium))
                                Text("n \(v.n) · α \(String(format: "%.1f", v.alpha)) β \(String(format: "%.1f", v.beta))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
