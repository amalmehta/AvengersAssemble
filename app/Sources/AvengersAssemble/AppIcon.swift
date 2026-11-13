import AppKit
import AvengersAssembleCore
import SwiftUI

/// The app icon: a team of heroes. The lead (the CEO) in a red cape in front, two teammates in blue beside them,
/// seen from behind with capes in the wind, over faint comic-book rays. Our own drawing, unlike any comic's logo.
/// Drawn on Apple's macOS icon grid: a 824-point rounded square centred on a 1024-point canvas.
struct AppIconView: View {
    /// Small sizes (16 and 32 px) draw only the lead, larger and without rays, so the shape still reads.
    var simplified = false

    private static let canvas: CGFloat = 1024
    private static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let tileShape = Path(roundedRect: tile, cornerRadius: 185.4, style: .continuous)
    private static let tileTop = Color(hex: 0x1F2840), tileBottom = Color(hex: 0x141A2B)
    private static let teammate = Color(hex: 0x7E9CC4), lead = Color(hex: 0xD9573B)

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / Self.canvas, y: size.height / Self.canvas)
            drawTile(&ctx)
            if simplified {
                drawHero(&ctx, at: CGPoint(x: 470, y: 290), scale: 1.45, color: Self.lead)
            } else {
                drawRays(&ctx, from: CGPoint(x: 512, y: 380))
                drawHero(&ctx, at: CGPoint(x: 340, y: 340), scale: 0.95, color: Self.teammate)
                drawHero(&ctx, at: CGPoint(x: 650, y: 340), scale: 0.95, color: Self.teammate)
                drawHero(&ctx, at: CGPoint(x: 480, y: 370), scale: 1.25, color: Self.lead)
            }
        }
        .frame(width: Self.canvas, height: Self.canvas)
    }

    private func drawTile(_ ctx: inout GraphicsContext) {
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8))
        shadowed.fill(Self.tileShape, with: .color(Self.tileBottom))
        ctx.fill(Self.tileShape, with: .linearGradient(Gradient(colors: [Self.tileTop, Self.tileBottom]),
                                                       startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
    }

    /// Sixteen faint wedges fanning out from behind the team, clipped to the tile.
    private func drawRays(_ ctx: inout GraphicsContext, from c: CGPoint) {
        var rays = Path()
        for i in 0..<16 {
            let a0 = Double(i) * .pi / 8, a1 = a0 + .pi / 16
            rays.move(to: c)
            rays.addLine(to: CGPoint(x: c.x + 900 * cos(a0), y: c.y + 900 * sin(a0)))
            rays.addLine(to: CGPoint(x: c.x + 900 * cos(a1), y: c.y + 900 * sin(a1)))
            rays.closeSubpath()
        }
        var clipped = ctx
        clipped.clip(to: Self.tileShape)
        clipped.fill(rays, with: .color(.white.opacity(0.04)))
    }

    /// One hero seen from behind: a head, and a cape from the shoulders flaring out and blowing right.
    /// `head` is the head's centre; a dark outline separates overlapping heroes.
    private func drawHero(_ ctx: inout GraphicsContext, at head: CGPoint, scale s: CGFloat, color: Color) {
        func pt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: head.x + dx * s, y: head.y + dy * s) }
        var cape = Path()
        cape.move(to: pt(-70, 70))
        cape.addCurve(to: pt(70, 70), control1: pt(-30, 55), control2: pt(30, 55))
        cape.addCurve(to: pt(230, 330), control1: pt(130, 150), control2: pt(180, 250))
        cape.addQuadCurve(to: pt(90, 340), control: pt(160, 300))
        cape.addQuadCurve(to: pt(-40, 370), control: pt(20, 380))
        cape.addQuadCurve(to: pt(-150, 345), control: pt(-100, 330))
        cape.addCurve(to: pt(-70, 70), control1: pt(-140, 230), control2: pt(-110, 130))
        cape.closeSubpath()
        let r = 58 * s
        let headShape = Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2))
        let outline = StrokeStyle(lineWidth: 26, lineJoin: .round)
        for shape in [cape, headShape] {
            ctx.fill(shape.strokedPath(outline), with: .color(Self.tileBottom))
            ctx.fill(shape, with: .color(color))
        }
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
