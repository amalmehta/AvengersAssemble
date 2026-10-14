import AppKit
import SuiteCore
import SwiftUI

/// The app icon: a team assembling. A central node (the CEO) is joined to a ring of agents in the app's
/// three kind families: warm for business, green for engineering, blue for science.
/// Drawn on Apple's macOS icon grid: a 824-point rounded square centred on a 1024-point canvas.
struct AppIconView: View {
    /// Small sizes (16 and 32 px) drop the faint ring and draw thicker, so the shape still reads.
    var simplified = false

    private static let canvas: CGFloat = 1024
    private static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let nodes: [(degrees: Double, kind: String)] = [
        (120, "strategy"), (60, "marketing"),   // business: top
        (0, "software"), (-60, "robotics"),     // engineering: right
        (-120, "ai"), (180, "research"),        // science: left
    ]

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
        shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 10))
        shadowed.fill(shape, with: .color(Color(hex: 0x0B1022)))
        ctx.fill(shape, with: .linearGradient(
            Gradient(colors: [Color(hex: 0x2A3A6B), Color(hex: 0x111832), Color(hex: 0x0A0F20)]),
            startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
        // A soft light behind the team, and a hairline highlight along the top edge.
        ctx.fill(shape, with: .radialGradient(Gradient(colors: [Color.white.opacity(0.16), .clear]),
                                              center: CGPoint(x: 512, y: 500), startRadius: 0, endRadius: 400))
        ctx.stroke(shape, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.22), .clear]),
                                                startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 400)),
                   lineWidth: 3)
    }

    private func drawTeam(_ ctx: inout GraphicsContext) {
        let center = CGPoint(x: 512, y: 512)
        let ring: CGFloat = simplified ? 268 : 262
        let nodeRadius: CGFloat = simplified ? 82 : 60
        let hubRadius: CGFloat = simplified ? 110 : 88
        let points = Self.nodes.map { node -> (CGPoint, Color) in
            let a = node.degrees * .pi / 180
            let p = CGPoint(x: center.x + ring * cos(a), y: center.y - ring * sin(a))
            return (p, Color(rgb: KindPalette.swatch(for: node.kind).dark))
        }

        if !simplified {  // the team's circle
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)),
                       with: .color(.white.opacity(0.13)), lineWidth: 6)
        }
        for (p, color) in points {  // spokes from the hub to each agent
            var line = Path()
            line.move(to: center)
            line.addLine(to: p)
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.9), color]),
                                                   startPoint: center, endPoint: p),
                       style: StrokeStyle(lineWidth: simplified ? 30 : 15, lineCap: .round))
        }
        for (p, color) in points {
            drawNode(&ctx, at: p, radius: nodeRadius, color: color, glow: simplified ? 0 : 34)
        }
        drawNode(&ctx, at: center, radius: hubRadius, color: Color(hex: 0xF4F7FF), glow: simplified ? 0 : 60,
                 core: Color.white)
    }

    private func drawNode(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color, glow: CGFloat,
                          core: Color? = nil) {
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        if glow > 0 {
            var glowing = ctx
            glowing.addFilter(.shadow(color: color.opacity(0.85), radius: glow))
            glowing.fill(disc, with: .color(color))
        }
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [core ?? color.opacity(0.75), color]),
                                             center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.35),
                                             startRadius: 0, endRadius: r * 1.4))
        ctx.stroke(disc, with: .color(.white.opacity(0.35)), lineWidth: r * 0.06)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(rgb: RGB(hex: hex))
    }

    init(rgb: RGB) {
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
