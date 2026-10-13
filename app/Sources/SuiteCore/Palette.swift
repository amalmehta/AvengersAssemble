import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Kinds

public enum KindFamily: String, Sendable, CaseIterable, Codable {
    case business, engineering, science, other

    public var displayName: String {
        switch self {
        case .business: return "Business"
        case .engineering: return "Engineering"
        case .science: return "Science"
        case .other: return "Other"
        }
    }
}

public enum KindCatalog {
    /// Kinds in display order, grouped by family.
    public static let defaults: [KindInfo] = [
        KindInfo(id: "strategy", name: "Strategy", family: .business),
        KindInfo(id: "marketing", name: "Marketing", family: .business),
        KindInfo(id: "product", name: "Product", family: .business),
        KindInfo(id: "software", name: "Software", family: .engineering),
        KindInfo(id: "hardware", name: "Hardware", family: .engineering),
        KindInfo(id: "robotics", name: "Robotics", family: .engineering),
        KindInfo(id: "research", name: "Research", family: .science),
        KindInfo(id: "ai", name: "AI", family: .science),
        KindInfo(id: "math", name: "Math", family: .science),
        KindInfo(id: "physics", name: "Physics", family: .science),
    ]

    public static func info(_ id: String) -> KindInfo? { defaults.first { $0.id == id } }

    public static func displayName(_ id: String) -> String {
        info(id)?.name ?? Naming.humanize(id)
    }

    public static func family(of id: String) -> KindFamily {
        info(id)?.family ?? .other
    }

    /// Sort key: family order, then catalog order, then name.
    public static func order(_ id: String) -> Int {
        defaults.firstIndex { $0.id == id } ?? 1000
    }
}

// MARK: - Colour

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double

    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// Hue in degrees (0..<360), saturation and brightness in 0...1.
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// Relative luminance (WCAG).
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func distance(to o: RGB) -> Double {
        ((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)).squareRoot()
    }

    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}

public struct KindSwatch: Equatable, Sendable {
    /// Tuned for light appearance: dark enough to read as text on a light background.
    public var light: RGB
    /// Tuned for dark appearance: bright enough to read as text on a dark background.
    public var dark: RGB
}

/// Colours for task kinds. Related kinds share a hue family:
/// business = warm (red-orange, orange, amber), engineering = greens (green, olive-lime, mint),
/// science = blues/purples (sky, blue, indigo, purple).
public enum KindPalette {
    public static let swatches: [String: KindSwatch] = [
        // Business: warm
        "strategy":  KindSwatch(light: RGB(hex: 0xD63C1E), dark: RGB(hex: 0xFF7058)), // red-orange
        "marketing": KindSwatch(light: RGB(hex: 0xE8730C), dark: RGB(hex: 0xFF9036)), // orange
        "product":   KindSwatch(light: RGB(hex: 0xB58600), dark: RGB(hex: 0xF2CC3D)), // amber
        // Engineering: greens
        "software":  KindSwatch(light: RGB(hex: 0x2B9348), dark: RGB(hex: 0x5AD27A)), // green
        "hardware":  KindSwatch(light: RGB(hex: 0x7A9612), dark: RGB(hex: 0xB8D94A)), // olive-lime
        "robotics":  KindSwatch(light: RGB(hex: 0x0E9F86), dark: RGB(hex: 0x4FD8BE)), // mint / teal-green
        // Science: blues and purples
        "research":  KindSwatch(light: RGB(hex: 0x1A8FD0), dark: RGB(hex: 0x5BC0F5)), // sky
        "ai":        KindSwatch(light: RGB(hex: 0x2F64E0), dark: RGB(hex: 0x6F9BFF)), // blue
        "math":      KindSwatch(light: RGB(hex: 0x5A46D6), dark: RGB(hex: 0x9A8CFF)), // indigo
        "physics":   KindSwatch(light: RGB(hex: 0x9A3BC9), dark: RGB(hex: 0xCB86F0)), // purple
    ]

    public static let neutral = KindSwatch(light: RGB(hex: 0x6E6E73), dark: RGB(hex: 0xA1A1A6))

    /// The hue range (degrees) every member of a family falls into. Families don't overlap.
    public static let familyHueRanges: [KindFamily: ClosedRange<Double>] = [
        .business: 0...50,
        .engineering: 65...180,
        .science: 190...290,
    ]

    /// Fallback colour for an unknown kind that still belongs to a known family.
    static let familyFallback: [KindFamily: String] = [
        .business: "marketing", .engineering: "software", .science: "ai",
    ]

    public static func swatch(for kind: String, family: KindFamily? = nil) -> KindSwatch {
        if let s = swatches[kind] { return s }
        let fam = family ?? KindCatalog.family(of: kind)
        if let fallback = familyFallback[fam], let s = swatches[fallback] { return s }
        return neutral
    }

    #if canImport(AppKit)
    /// A dynamic NSColor that switches between the tuned light and dark values.
    public static func nsColor(for kind: String, family: KindFamily? = nil) -> NSColor {
        let s = swatch(for: kind, family: family)
        return NSColor(name: NSColor.Name("SuiteKind.\(kind)")) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]) == .darkAqua
                || appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]) == .vibrantDark
            let c = isDark ? s.dark : s.light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
    }
    #endif
}
