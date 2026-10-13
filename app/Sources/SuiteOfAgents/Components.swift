import AppKit
import SuiteCore
import SwiftUI

extension Color {
    static func kind(_ id: String, family: KindFamily? = nil) -> Color {
        Color(nsColor: KindPalette.nsColor(for: id, family: family))
    }
}

/// A rounded tag for a task kind: tinted background plus coloured text.
struct KindChip: View {
    @Environment(AppModel.self) private var model
    var kind: String
    var compact = false

    var body: some View {
        let c = Color.kind(kind, family: model.kindFamily(kind))
        Text(model.kindName(kind))
            .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(c)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(c.opacity(0.15)))
            .overlay(Capsule().strokeBorder(c.opacity(0.28), lineWidth: 0.5))
    }
}

/// A neutral capsule (variants, file chips, badges).
struct Pill: View {
    var text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
        .fixedSize()
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth { y += lineHeight + lineSpacing; x = 0; lineHeight = 0 }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += lineHeight + lineSpacing; x = bounds.minX; lineHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

/// A thin capsule meter.
struct Meter: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint.gradient)
                    .frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

/// Spend and task-count against their caps.
struct BudgetBar: View {
    var spent: Double
    var cap: Double
    var tasks: Int
    var maxTasks: Int

    var body: some View {
        HStack(spacing: 24) {
            gauge(icon: "dollarsign.circle", label: "Spent",
                  value: "\(Naming.dollars(spent)) of \(Naming.dollars(cap))",
                  fraction: cap > 0 ? spent / cap : 0,
                  tint: spent / max(cap, 0.0001) > 0.9 ? .orange : .accentColor)
            gauge(icon: "checklist", label: "Tasks", value: "\(tasks) of \(maxTasks)",
                  fraction: maxTasks > 0 ? Double(tasks) / Double(maxTasks) : 0, tint: .teal)
        }
    }

    private func gauge(icon: String, label: String, value: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).monospacedDigit().fontWeight(.medium)
            }
            .font(.callout)
            Meter(fraction: fraction, tint: tint)
        }
        .frame(minWidth: 180, maxWidth: 260)
    }
}

/// A coloured score badge for judge scores (0...1).
struct ScoreBadge: View {
    var score: Double?

    var body: some View {
        if let score {
            Text(String(format: "%.2f", score))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint(score))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(tint(score).opacity(0.12)))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    private func tint(_ s: Double) -> Color {
        s >= 0.8 ? .green : s >= 0.65 ? .primary.opacity(0.75) : .orange
    }
}

struct StatusLabel: View {
    var status: TaskStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: status.symbolName).foregroundStyle(color)
            }
            Text(status.displayName)
        }
        .font(.callout)
        .foregroundStyle(status == .pending ? .secondary : .primary)
        .lineLimit(1)
    }

    var color: Color {
        switch status {
        case .done: return .green
        case .failed: return .red
        case .running: return .accentColor
        case .pending, .skipped: return .secondary
        }
    }
}

struct RunStatusBadge: View {
    var status: String

    var body: some View {
        Pill(text: RunStatusName.display(status), systemImage: symbol, tint: tint)
    }

    private var symbol: String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "budget": return "gauge.with.dots.needle.100percent"
        case "canceled", "canceling": return "stop.circle"
        case "error": return "exclamationmark.triangle.fill"
        default: return "bolt.circle"
        }
    }

    private var tint: Color {
        switch status {
        case "done": return .green
        case "budget": return .orange
        case "error": return .red
        case "canceled", "canceling": return .secondary
        default: return .accentColor
        }
    }
}

/// Top-of-content error banner with optional stderr.
struct BannerView: View {
    var banner: Banner
    var onClose: () -> Void
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(.headline)
                    Text(banner.message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer()
                if banner.details != nil {
                    Button(showDetails ? "Hide Details" : "Show Details") { showDetails.toggle() }
                        .buttonStyle(.link)
                }
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Dismiss")
            }
            if showDetails, let d = banner.details {
                ScrollView {
                    Text(d).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.35)))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

/// Section heading used in the inspector and other panes.
struct SectionHeader: View {
    var title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

/// Rounded card background used across views.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
