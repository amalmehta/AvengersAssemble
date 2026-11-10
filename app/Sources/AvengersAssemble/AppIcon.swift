import AppKit
import AvengersAssembleCore
import SwiftUI

/// The app icon: a team assembling. A terracotta lead (the CEO) at the centre, joined to a ring of six agents
/// in one muted blue. Flat, with no glow: colour marks the lead, and only the lead.
/// Drawn on Apple's macOS icon grid: a 824-point rounded square centred on a 1024-point canvas.
struct AppIconView: View {
    /// Small sizes (16 and 32 px) draw bigger nodes and thicker spokes, so the shape still reads.
    var simplified = false

    private static let canvas: CGFloat = 1024
    private static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let agentAngles: [Double] = [90, 30, -30, -90, -150, 150]
    private static let tileTop = Color(hex: 0x1F2840), tileBottom = Color(hex: 0x141A2B)
    private static let agent = Color(hex: 0x7E9CC4), lead = Color(hex: 0xC8714E)

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / Self.canvas, y: size.height / Self.canvas)
            drawTile(&ctx)
            drawTeam(&ctx)
        }
        .frame(width: Self.canvas, height: Self.canvas)
    }

    private func drawTile(_ ctx: inout GraphicsContext) {
        let shape = Path(roundedRect: Self.tile, cornerRadius: 185.4, style: .continuous)
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8))
        shadowed.fill(shape, with: .color(Self.tileBottom))
        ctx.fill(shape, with: .linearGradient(Gradient(colors: [Self.tileTop, Self.tileBottom]),
                                              startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
    }

    private func drawTeam(_ ctx: inout GraphicsContext) {
        let center = CGPoint(x: 512, y: 512)
        let ring: CGFloat = 255
        let nodeRadius: CGFloat = simplified ? 74 : 58
        let hubRadius: CGFloat = simplified ? 100 : 86
        let points = Self.agentAngles.map { degrees -> CGPoint in
            let a = degrees * .pi / 180
            return CGPoint(x: center.x + ring * cos(a), y: center.y - ring * sin(a))
        }
        for p in points {  // spokes from the lead to each agent
            var line = Path()
            line.move(to: center)
            line.addLine(to: p)
            ctx.stroke(line, with: .color(Self.agent.opacity(0.55)),
                       style: StrokeStyle(lineWidth: simplified ? 26 : 14, lineCap: .round))
        }
        for p in points { ctx.fill(Self.disc(p, nodeRadius), with: .color(Self.agent)) }
        ctx.fill(Self.disc(center, hubRadius), with: .color(Self.lead))
    }

    private static func disc(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
}

private extension Color {
    init(hex: UInt32) {
        let rgb = RGB(hex: hex)
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }
}

/// `--render-icon <folder>`: writes AppIcon.iconset (every macOS size) for iconutil to pack into an .icns.
enum IconRenderer {
    static let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    @MainActor static func run(outputDirectory: URL) {
        let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for (name, pixels) in sizes {
            guard let data = png(pixels: pixels) else {
                FileHandle.standardError.write(Data("Could not render \(name)\n".utf8))
                exit(1)
            }
            try? data.write(to: iconset.appendingPathComponent("\(name).png"))
        }
        print("Wrote \(sizes.count) icon sizes to \(iconset.path)")
        exit(0)
    }

    @MainActor static func png(pixels: Int) -> Data? {
        let renderer = ImageRenderer(content: AppIconView(simplified: pixels <= 32))
        renderer.scale = CGFloat(pixels) / 1024
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The Dock icon when running unbundled (`swift run`), where there's no .icns.
    @MainActor static func dockImage() -> NSImage? {
        guard let data = png(pixels: 512) else { return nil }
        return NSImage(data: data)
    }
}
