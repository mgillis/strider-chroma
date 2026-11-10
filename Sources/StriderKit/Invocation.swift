public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum AgentAction: String, Equatable {
    case install, uninstall, status
}

/// What a command line asks for.
public enum Invocation: Equatable {
    /// Change the effect, the brightness, or both.
    case light(effect: Strider.Effect?, brightness: UInt8?, temporary: Bool)
    case showBrightness
    case info
    case colors
    case apply
    case watch
    case agent(AgentAction)
    case help

    public static let usage = """
        strider: lighting control for the Razer Strider Chroma mouse mat

        Usage:
          strider <colour>                   solid colour (short for "static")
          strider static <colour>
          strider off
          strider breathe [colour] [colour]  fade in and out: random colours, one colour, or two alternating
          strider spectrum                   cycle the whole border slowly through all colours
          strider wave [cw|ccw]              rainbow travelling around the border (the factory default)
          strider leds <colour>...           per-LED colours: 2 or more are blended into a gradient
                                             along the \(Strider.ledCount) LEDs, \(Strider.ledCount) are used as given
          strider brightness [0-100]         set the brightness, or print the last one set

          strider info                       firmware, serial number and the current setting
          strider colors                     list the colour names
          strider apply                      send the current setting to the mat again
          strider watch                      stay running and re-apply the setting whenever the mat
                                             is attached or the Mac wakes
          strider agent install|uninstall|status
                                             run "strider watch" in the background from login

        Options:
          -b, --brightness <0-100>           set the brightness along with an effect
          --temporary                        do not store the change in the mat or in the saved setting

        A colour is a name (see "strider colors"), hex such as ff8800 or #f80, or decimal r,g,b.
        """

    public static func parse(_ arguments: [String]) throws -> Invocation {
        var positional: [String] = []
        var brightness: UInt8?
        var temporary = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "-h", "--help":
                return .help
            case "--temporary":
                temporary = true
            case "-b", "--brightness":
                guard index < arguments.count else { throw UsageError("\(argument) needs a value from 0 to 100") }
                brightness = try parsePercent(arguments[index])
                index += 1
            case _ where argument.hasPrefix("--brightness="):
                brightness = try parsePercent(String(argument.dropFirst("--brightness=".count)))
            case _ where argument.hasPrefix("-") && argument.count > 1:
                throw UsageError("unknown option \(argument)")
            default:
                positional.append(argument)
            }
        }

        guard let command = positional.first?.lowercased() else {
            // "strider -b 40" on its own is a brightness change.
            return brightness == nil ? .help : .light(effect: nil, brightness: brightness, temporary: temporary)
        }
        let rest = Array(positional.dropFirst())

        func light(_ effect: Strider.Effect?) -> Invocation {
            .light(effect: effect, brightness: brightness, temporary: temporary)
        }
        func expectNoArguments() throws {
            guard rest.isEmpty else { throw UsageError("\"\(command)\" takes no arguments") }
        }
        /// For commands that do not change the lighting.
        func plain(_ invocation: Invocation) throws -> Invocation {
            try expectNoArguments()
            guard brightness == nil, !temporary else {
                throw UsageError("\"\(command)\" does not take lighting options")
            }
            return invocation
        }

        switch command {
        case "static", "solid", "color", "colour":
            guard rest.count == 1 else { throw UsageError("\"\(command)\" takes exactly one colour") }
            return light(.solid(try parseColor(rest[0])))
        case "off":
            try expectNoArguments()
            return light(.off)
        case "breathe", "breathing":
            guard rest.count <= 2 else { throw UsageError("\"\(command)\" takes at most two colours") }
            return light(.breathe(try rest.map(parseColor)))
        case "spectrum":
            try expectNoArguments()
            return light(.spectrum)
        case "wave":
            guard rest.count <= 1 else { throw UsageError("\"wave\" takes at most a direction: cw or ccw") }
            return light(.wave(try parseDirection(rest.first ?? "cw")))
        case "leds", "gradient":
            guard !rest.isEmpty else { throw UsageError("\"\(command)\" needs at least one colour") }
            guard rest.count <= Strider.ledCount else {
                throw UsageError("the mat has \(Strider.ledCount) LEDs, but \(rest.count) colours were given")
            }
            return light(.leds(RGB.spread(try rest.map(parseColor), across: Strider.ledCount)))
        case "brightness":
            guard rest.count <= 1 else { throw UsageError("\"brightness\" takes one value from 0 to 100") }
            if let value = rest.first {
                guard brightness == nil else { throw UsageError("brightness was given twice") }
                return .light(effect: nil, brightness: try parsePercent(value), temporary: temporary)
            }
            return brightness == nil ? try plain(.showBrightness) : light(nil)
        case "info", "status":
            return try plain(.info)
        case "colors", "colours":
            return try plain(.colors)
        case "apply":
            return try plain(.apply)
        case "watch":
            return try plain(.watch)
        case "agent":
            guard rest.count == 1, let action = AgentAction(rawValue: rest[0].lowercased()) else {
                throw UsageError("usage: strider agent install|uninstall|status")
            }
            guard brightness == nil, !temporary else { throw UsageError("\"agent\" does not take lighting options") }
            return .agent(action)
        case "help":
            return .help
        default:
            // A bare colour is a solid colour.
            if rest.isEmpty, let color = RGB(parsing: command) { return light(.solid(color)) }
            throw UsageError("unknown command \"\(positional[0])\". Run \"strider help\" for usage")
        }
    }

    static func parseColor(_ text: String) throws -> RGB {
        guard let color = RGB(parsing: text) else {
            throw UsageError("\"\(text)\" is not a colour. Use a name, hex such as ff8800, or r,g,b")
        }
        return color
    }

    static func parsePercent(_ text: String) throws -> UInt8 {
        let digits = text.hasSuffix("%") ? String(text.dropLast()) : text
        guard let percent = Int(digits), (0...100).contains(percent) else {
            throw UsageError("brightness must be a whole number from 0 to 100, not \"\(text)\"")
        }
        return Brightness.byte(fromPercent: percent)
    }

    static func parseDirection(_ text: String) throws -> Strider.WaveDirection {
        switch text.lowercased() {
        case "cw", "clockwise", "right": return .clockwise
        case "ccw", "anticlockwise", "counterclockwise", "left": return .anticlockwise
        default: throw UsageError("wave direction must be cw or ccw, not \"\(text)\"")
        }
    }
}
