/// Requests understood by the Razer Strider Chroma (USB 1532:0C05).
///
/// The mat uses Razer's "extended matrix" command class (0x0F), the same one
/// as the Firefly V2. Packet contents follow OpenRazer's
/// driver/razerchromacommon.c and the Strider cases in
/// driver/razeraccessory_driver.c.
public enum Strider {
    public static let vendorID = 0x1532
    public static let productID = 0x0C05
    /// The lit border is one row of 19 individually addressable LEDs. The
    /// first is at the power pack on the left edge. From there the row runs
    /// anticlockwise seen from above: toward the user, right along the front
    /// edge, away along the right edge, and back along the far edge. The
    /// last LED is therefore next to the first.
    public static let ledCount = 19

    /// Transaction id for lighting commands and the firmware version query.
    static let lightingTransaction: UInt8 = 0x3F
    /// Transaction id for the serial number query.
    static let serialTransaction: UInt8 = 0xFF

    static let classExtendedMatrix: UInt8 = 0x0F
    static let commandEffect: UInt8 = 0x02
    static let commandFrame: UInt8 = 0x03
    static let commandBrightness: UInt8 = 0x04

    /// The mat has a single lighting zone, addressed as LED 0.
    static let led: UInt8 = 0x00

    /// Where the device should keep a setting.
    public enum Storage: UInt8 {
        /// Applies now and is forgotten when the mat loses power.
        case temporary = 0x00
        /// Written to the mat's own memory.
        case saved = 0x01
    }

    public enum WaveDirection: UInt8, Codable {
        case anticlockwise = 0x01
        case clockwise = 0x02
    }

    public enum Effect: Equatable, Codable {
        case off
        case solid(RGB)
        /// Fades in and out. No colours: random. One: that colour. Two: alternates.
        case breathe([RGB])
        /// Slowly cycles the whole border through the colour wheel.
        case spectrum
        /// A rainbow that travels around the border. This is the factory default.
        case wave(WaveDirection)
        /// One colour per LED, exactly `ledCount` of them. The mat does not
        /// store this itself, so it is lost when the mat loses power.
        case leds([RGB])
    }

    // The protocol also has a "reactive" effect (id 0x05). It only flashes when
    // the host sends a trigger packet, which Synapse does on mouse clicks, so
    // it is not offered here.

    /// The reports that put the mat into `effect`, in the order they must be sent.
    public static func reports(for effect: Effect, storage: Storage = .saved) -> [RazerReport] {
        if case .leds(let colors) = effect {
            return [setFrame(colors), showFrame()]
        }

        // Arguments: storage, led, effect id, then effect-specific bytes.
        // Bytes 3 and 4 are direction and speed, 5 is the colour count, colours follow.
        var args: [UInt8] = [storage.rawValue, led, 0, 0, 0, 0]
        switch effect {
        case .off:
            args[2] = 0x00
        case .solid(let color):
            args[2] = 0x01
            args[5] = 0x01
            args += [color.r, color.g, color.b]
        case .breathe(let colors):
            precondition(colors.count <= 2, "breathe takes at most two colours")
            args[2] = 0x02
            args[3] = UInt8(colors.count)
            args[5] = UInt8(colors.count)
            for color in colors { args += [color.r, color.g, color.b] }
        case .spectrum:
            args[2] = 0x03
        case .wave(let direction):
            args[2] = 0x04
            args[3] = direction.rawValue
            args[4] = 0x28
        case .leds:
            fatalError("handled above")
        }
        return [
            RazerReport(
                transactionID: lightingTransaction,
                commandClass: classExtendedMatrix,
                commandID: commandEffect,
                dataSize: UInt8(args.count),
                arguments: args
            )
        ]
    }

    /// Loads one colour per LED into the mat's frame buffer. Nothing changes
    /// visibly until `showFrame()` is sent.
    static func setFrame(_ colors: [RGB]) -> RazerReport {
        precondition(colors.count == ledCount, "the Strider Chroma has \(ledCount) LEDs")
        var args: [UInt8] = [0, 0, 0 /* row */, 0 /* first column */, UInt8(ledCount - 1) /* last column */]
        for color in colors { args += [color.r, color.g, color.b] }
        return RazerReport(
            transactionID: lightingTransaction,
            commandClass: classExtendedMatrix,
            commandID: commandFrame,
            // OpenRazer sends a fixed size here regardless of the column count.
            dataSize: 0x47,
            arguments: args
        )
    }

    /// Switches the mat to displaying the frame buffer.
    static func showFrame() -> RazerReport {
        RazerReport(
            transactionID: lightingTransaction,
            commandClass: classExtendedMatrix,
            commandID: commandEffect,
            dataSize: 0x0C,
            arguments: [Storage.temporary.rawValue, led, 0x08]
        )
    }

    /// Brightness is 0 to 255. The mat rejects the matching read command
    /// (0x84), so the current value cannot be queried.
    public static func setBrightness(_ value: UInt8, storage: Storage = .saved) -> RazerReport {
        RazerReport(
            transactionID: lightingTransaction,
            commandClass: classExtendedMatrix,
            commandID: commandBrightness,
            dataSize: 3,
            arguments: [storage.rawValue, led, value]
        )
    }

    public static func getFirmwareVersion() -> RazerReport {
        RazerReport(transactionID: lightingTransaction, commandClass: 0x00, commandID: 0x81, dataSize: 2)
    }

    public static func firmwareVersion(from response: RazerReport) -> String {
        "v\(response.arguments[0]).\(response.arguments[1])"
    }

    public static func getSerial() -> RazerReport {
        RazerReport(transactionID: serialTransaction, commandClass: 0x00, commandID: 0x82, dataSize: 0x16)
    }

    public static func serial(from response: RazerReport) -> String {
        let ascii = response.arguments.prefix(0x16).prefix { $0 != 0 }
        return String(decoding: ascii, as: UTF8.self)
    }
}
