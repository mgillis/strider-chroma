import Foundation

public struct RGB: Equatable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hex: String {
        func pair(_ v: UInt8) -> String {
            let s = String(v, radix: 16)
            return s.count == 1 ? "0" + s : s
        }
        return "#" + pair(r) + pair(g) + pair(b)
    }

    /// The named colours accepted on the command line, in hue order, each
    /// with a description of how it looks on the mat.
    ///
    /// The values were chosen by eye on a Strider Chroma at 30% brightness,
    /// and they differ a lot from the sRGB colours of the same names. Mixed
    /// colours look far less saturated on the mat than on a screen, and a
    /// small amount of a second channel moves the hue a long way: #ff3200 is
    /// already a full orange, and #8c00ff is nearly magenta. A name is only
    /// listed if its colour can be recognised without a neighbour to compare
    /// it with.
    public static let palette: [(name: String, color: RGB, looksLike: String)] = [
        ("white", RGB(255, 255, 255), "neutral white"),
        ("soft", RGB(255, 180, 100), "cream, an off-white"),
        ("warm", RGB(255, 140, 40), "warm bulb white, slightly orange"),
        ("amber", RGB(255, 120, 0), "amber, like an amber terminal"),
        ("ember", RGB(255, 90, 10), "the orange of a glowing ember"),
        ("orange", RGB(255, 50, 0), "hazard orange"),
        ("red", RGB(255, 0, 0), "tomato red"),
        ("pink", RGB(255, 40, 120), "soft rose pink"),
        ("magenta", RGB(255, 0, 255), "vivid magenta"),
        ("purple", RGB(96, 0, 255), "purple"),
        ("violet", RGB(60, 0, 255), "flower-petal violet"),
        ("blue", RGB(0, 0, 255), "blue with a faint trace of purple"),
        ("sky", RGB(0, 255, 255), "light blue"),
        ("teal", RGB(0, 200, 140), "teal"),
        ("green", RGB(0, 255, 0), "pure green"),
        ("lemon", RGB(255, 200, 0), "lemon yellow, slightly green"),
        ("yellow", RGB(255, 170, 0), "yellow"),
        ("black", RGB(0, 0, 0), "unlit"),
    ]

    public static let named: [String: RGB] = Dictionary(
        uniqueKeysWithValues: palette.map { ($0.name, $0.color) })

    /// Parses `#rrggbb`, `rrggbb`, `#rgb`, `rgb`, `r,g,b` (decimal) or a name from `named`.
    public init?(parsing text: String) {
        let lower = text.lowercased()
        if let known = Self.named[lower] {
            self = known
            return
        }

        let parts = lower.split(separator: ",", omittingEmptySubsequences: false)
        if parts.count == 3 {
            let values = parts.compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count == 3 else { return nil }
            self.init(values[0], values[1], values[2])
            return
        }

        var digits = Substring(lower)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 6:
            guard let value = UInt32(digits, radix: 16) else { return nil }
            self.init(UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF))
        case 3:
            let nibbles = digits.compactMap { UInt8(String($0), radix: 16) }
            guard nibbles.count == 3 else { return nil }
            self.init(nibbles[0] * 17, nibbles[1] * 17, nibbles[2] * 17)
        default:
            return nil
        }
    }

    /// Linear interpolation between two colours. `t` is clamped to 0...1.
    public static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        func channel(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8((Double(x) + (Double(y) - Double(x)) * t).rounded())
        }
        return RGB(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b))
    }

    /// Spreads `stops` evenly across `count` LEDs, interpolating between neighbours.
    /// One stop gives a uniform colour. `count` stops are used unchanged.
    public static func spread(_ stops: [RGB], across count: Int) -> [RGB] {
        precondition(!stops.isEmpty && count > 0)
        if stops.count == 1 || count == 1 { return [RGB](repeating: stops[0], count: count) }
        return (0..<count).map { i in
            let position = Double(i) / Double(count - 1) * Double(stops.count - 1)
            let lower = min(Int(position), stops.count - 2)
            return mix(stops[lower], stops[lower + 1], position - Double(lower))
        }
    }
}
