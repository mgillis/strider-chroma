/// The lighting most recently set through this tool.
///
/// The mat cannot be asked what it is currently showing, so this record is
/// the only way to report the current setting or to restore it after the mat
/// has lost power.
public struct SavedState: Codable, Equatable {
    public var effect: Strider.Effect?
    /// 0 to 255.
    public var brightness: UInt8?

    public init(effect: Strider.Effect? = nil, brightness: UInt8? = nil) {
        self.effect = effect
        self.brightness = brightness
    }

    public var isEmpty: Bool { effect == nil && brightness == nil }

    /// Overwrites the parts of the state that a command changed.
    public mutating func record(effect: Strider.Effect?, brightness: UInt8?) {
        if let effect { self.effect = effect }
        if let brightness { self.brightness = brightness }
    }

    /// The reports that bring the mat to this state. Brightness goes first so
    /// that a newly selected effect never shows at the old brightness.
    public func reports(storage: Strider.Storage) -> [RazerReport] {
        var out: [RazerReport] = []
        if let brightness { out.append(Strider.setBrightness(brightness, storage: storage)) }
        if let effect { out += Strider.reports(for: effect, storage: storage) }
        return out
    }
}

public enum Brightness {
    /// Converts a percentage (0 to 100) to the device's 0 to 255 scale.
    public static func byte(fromPercent percent: Int) -> UInt8 {
        UInt8((Double(min(max(percent, 0), 100)) * 255 / 100).rounded())
    }

    public static func percent(fromByte byte: UInt8) -> Int {
        Int((Double(byte) * 100 / 255).rounded())
    }
}

extension Strider.Effect: CustomStringConvertible {
    public var description: String {
        switch self {
        case .off:
            return "off"
        case .solid(let color):
            return "static \(color.hex)"
        case .breathe(let colors):
            return colors.isEmpty ? "breathe (random colours)" : "breathe " + colors.map(\.hex).joined(separator: " ")
        case .spectrum:
            return "spectrum"
        case .wave(let direction, let delay):
            return "wave \(direction == .clockwise ? "clockwise" : "anticlockwise")"
                + (delay == Strider.defaultWaveDelay ? "" : ", delay \(delay)")
        case .leds(let colors):
            guard let first = colors.first, let last = colors.last else { return "leds" }
            return colors.allSatisfy { $0 == first } ? "leds \(first.hex)" : "leds \(first.hex) to \(last.hex)"
        }
    }
}
