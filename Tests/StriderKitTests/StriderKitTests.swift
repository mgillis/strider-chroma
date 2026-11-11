import XCTest

@testable import StriderKit

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
}

/// The first eight bytes plus the meaningful arguments, in the notation
/// OpenRazer uses in its packet comments (status, transaction id, remaining
/// packets, protocol, data size, class, command, arguments).
private func wire(_ report: RazerReport) -> String {
    let bytes = report.bytes
    return hex(Array(bytes[0..<8])) + " " + hex(Array(bytes[8..<(8 + Int(report.dataSize))]))
}

final class ReportTests: XCTestCase {
    func testLayoutAndChecksum() {
        let bytes = Strider.reports(for: .solid(RGB(0xFF, 0, 0)))[0].bytes
        XCTAssertEqual(bytes.count, 90)
        // XOR of bytes 2...87: 09 ^ 0f ^ 02 ^ 01 ^ 01 ^ 01 ^ ff.
        XCTAssertEqual(bytes[88], 0xFA)
        XCTAssertEqual(bytes[89], 0)
        XCTAssertTrue(bytes[17..<88].allSatisfy { $0 == 0 }, "unused arguments must be zero")
    }

    func testChecksumIgnoresStatusAndTransactionID() {
        var report = Strider.reports(for: .spectrum)[0]
        let before = report.bytes[88]
        report.status = 0x02
        report.transactionID = 0x1F
        XCTAssertEqual(report.bytes[88], before)
    }

    func testParsesAResponse() throws {
        // A firmware version reply as the mat sends it: status 02, version 1.0.
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[0] = 0x02
        bytes[1] = 0x3F
        bytes[5] = 0x02
        bytes[7] = 0x81
        bytes[8] = 0x01
        bytes[88] = 0x02 ^ 0x81 ^ 0x01
        let response = try XCTUnwrap(RazerReport(bytes: bytes))
        XCTAssertEqual(RazerStatus(rawValue: response.status), .successful)
        XCTAssertTrue(response.answers(Strider.getFirmwareVersion()))
        XCTAssertFalse(response.answers(Strider.getSerial()))
        XCTAssertEqual(Strider.firmwareVersion(from: response), "v1.0")
        XCTAssertEqual(response.bytes, bytes, "a parsed report must serialise back to the same bytes")
    }

    func testRejectsWrongLengthAndBadChecksum() {
        var bytes = Strider.getSerial().bytes
        XCTAssertNil(RazerReport(bytes: Array(bytes.dropLast())))
        bytes[20] ^= 0x01
        XCTAssertNil(RazerReport(bytes: bytes))
    }

    func testSerialStopsAtTheFirstNul() {
        var bytes = Strider.getSerial().bytes
        bytes.replaceSubrange(8..<12, with: Array("AB12".utf8))
        bytes[88] = RazerReport.checksum(of: bytes)
        XCTAssertEqual(Strider.serial(from: RazerReport(bytes: bytes)!), "AB12")
    }
}

/// Expected packets are OpenRazer's documented ones for the extended matrix
/// commands, with the LED id changed from 05 (keyboard backlight) to 00,
/// which is what OpenRazer sends to the Strider.
final class EffectPacketTests: XCTestCase {
    func testOff() {
        XCTAssertEqual(wire(Strider.reports(for: .off)[0]), "003f000000060f02 010000000000")
    }

    func testSolid() {
        XCTAssertEqual(wire(Strider.reports(for: .solid(RGB(0, 0x80, 0)))[0]), "003f000000090f02 010001000001008000")
    }

    func testBreathe() {
        XCTAssertEqual(wire(Strider.reports(for: .breathe([]))[0]), "003f000000060f02 010002000000")
        XCTAssertEqual(
            wire(Strider.reports(for: .breathe([RGB(0, 0xFF, 0)]))[0]), "003f000000090f02 01000201000100ff00")
        XCTAssertEqual(
            wire(Strider.reports(for: .breathe([RGB(0, 0xFF, 0), RGB(0xFF, 0, 0)]))[0]),
            "003f0000000c0f02 01000202000200ff00ff0000")
    }

    func testSpectrumAndWave() {
        XCTAssertEqual(wire(Strider.reports(for: .spectrum)[0]), "003f000000060f02 010003000000")
        XCTAssertEqual(wire(Strider.reports(for: .wave(.anticlockwise, delay: 0x28))[0]), "003f000000060f02 010004022800")
        XCTAssertEqual(wire(Strider.reports(for: .wave(.clockwise, delay: 0xC8))[0]), "003f000000060f02 01000401c800")
    }

    func testTemporaryStorageClearsTheStoreByte() {
        XCTAssertEqual(wire(Strider.reports(for: .spectrum, storage: .temporary)[0]), "003f000000060f02 000003000000")
        XCTAssertEqual(wire(Strider.setBrightness(0xB7, storage: .temporary)), "003f000000030f04 0000b7")
    }

    func testBrightness() {
        XCTAssertEqual(wire(Strider.setBrightness(0xB7)), "003f000000030f04 0100b7")
    }

    func testLedsSendsAFrameThenShowsIt() {
        let colors = (0..<Strider.ledCount).map { RGB(UInt8($0), 0, 0xFF) }
        let reports = Strider.reports(for: .leds(colors))
        XCTAssertEqual(reports.count, 2)

        let frame = reports[0]
        XCTAssertEqual(hex(Array(frame.bytes[0..<8])), "003f000000470f03")
        // Row 0, columns 0 through 18, then three bytes per LED.
        XCTAssertEqual(Array(frame.arguments[0..<5]), [0, 0, 0, 0, 18])
        XCTAssertEqual(Array(frame.arguments[5..<8]), [0, 0, 0xFF])
        XCTAssertEqual(Array(frame.arguments[59..<62]), [18, 0, 0xFF])
        XCTAssertTrue(frame.arguments[62...].allSatisfy { $0 == 0 })

        XCTAssertEqual(wire(reports[1]), "003f0000000c0f02 000008000000000000000000")
    }
}

final class RGBTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(RGB(parsing: "ff8800"), RGB(255, 136, 0))
        XCTAssertEqual(RGB(parsing: "#FF8800"), RGB(255, 136, 0))
        XCTAssertEqual(RGB(parsing: "#f80"), RGB(255, 136, 0))
        XCTAssertEqual(RGB(parsing: "255,136,0"), RGB(255, 136, 0))
        XCTAssertEqual(RGB(parsing: "255, 136, 0"), RGB(255, 136, 0))
        XCTAssertEqual(RGB(parsing: "Red"), RGB(255, 0, 0))
    }

    func testRejectsInvalidColours() {
        for text in ["", "#", "ff88", "gg0000", "256,0,0", "1,2", "1,2,3,4", "notacolour", "#ff88001"] {
            XCTAssertNil(RGB(parsing: text), "\"\(text)\" should not parse")
        }
    }

    func testSpread() {
        let red = RGB(255, 0, 0)
        let blue = RGB(0, 0, 255)
        XCTAssertEqual(RGB.spread([red], across: 19), [RGB](repeating: red, count: 19))

        let gradient = RGB.spread([red, blue], across: 19)
        XCTAssertEqual(gradient.count, 19)
        XCTAssertEqual(gradient.first, red)
        XCTAssertEqual(gradient.last, blue)
        XCTAssertEqual(gradient[9], RGB(128, 0, 128))

        // Three stops put the middle stop exactly on the middle LED.
        let green = RGB(0, 255, 0)
        XCTAssertEqual(RGB.spread([red, green, blue], across: 19)[9], green)

        // One colour per LED is passed through unchanged.
        let exact = (0..<19).map { RGB(UInt8($0 * 10), 7, 9) }
        XCTAssertEqual(RGB.spread(exact, across: 19), exact)
    }

    func testHex() {
        XCTAssertEqual(RGB(1, 0xAB, 0).hex, "#01ab00")
    }

    func testEveryNamedColourIsDistinctAndParses() {
        XCTAssertEqual(Set(RGB.palette.map(\.name)).count, RGB.palette.count, "a name is listed twice")
        XCTAssertEqual(Set(RGB.palette.map(\.color.hex)).count, RGB.palette.count, "two names share a value")
        for entry in RGB.palette {
            XCTAssertEqual(RGB(parsing: entry.name), entry.color)
            XCTAssertEqual(entry.name, entry.name.lowercased(), "names are matched in lower case")
            // A name made only of hex digits would be ambiguous with a hex colour.
            XCTAssertFalse(
                [3, 6].contains(entry.name.count) && entry.name.allSatisfy(\.isHexDigit),
                "\"\(entry.name)\" could also be read as hex")
        }
    }
}

final class InvocationTests: XCTestCase {
    private func parse(_ line: String) throws -> Invocation {
        try Invocation.parse(line.split(separator: " ").map(String.init))
    }

    func testEffects() throws {
        XCTAssertEqual(try parse("static red"), .light(effect: .solid(RGB(255, 0, 0)), brightness: nil, temporary: false))
        XCTAssertEqual(try parse("ff8800"), .light(effect: .solid(RGB(255, 136, 0)), brightness: nil, temporary: false))
        XCTAssertEqual(try parse("off"), .light(effect: .off, brightness: nil, temporary: false))
        XCTAssertEqual(try parse("spectrum"), .light(effect: .spectrum, brightness: nil, temporary: false))
        XCTAssertEqual(try parse("wave"), .light(effect: .wave(.clockwise, delay: 0x28), brightness: nil, temporary: false))
        XCTAssertEqual(try parse("wave --delay 200"), .light(effect: .wave(.clockwise, delay: 200), brightness: nil, temporary: false))
        XCTAssertEqual(try parse("wave ccw"), .light(effect: .wave(.anticlockwise, delay: 0x28), brightness: nil, temporary: false))
        XCTAssertEqual(try parse("breathe"), .light(effect: .breathe([]), brightness: nil, temporary: false))
        XCTAssertEqual(
            try parse("breathe red blue"),
            .light(effect: .breathe([RGB(255, 0, 0), RGB(0, 0, 255)]), brightness: nil, temporary: false))
    }

    func testLedsAlwaysProducesOneColourPerLed() throws {
        guard case .light(.leds(let colors)?, nil, false) = try parse("leds red blue") else {
            return XCTFail("expected a per-LED effect")
        }
        XCTAssertEqual(colors.count, Strider.ledCount)
        XCTAssertEqual(colors.first, RGB(255, 0, 0))
        XCTAssertEqual(colors.last, RGB(0, 0, 255))
    }

    func testBrightnessOption() throws {
        XCTAssertEqual(
            try parse("warm -b 30"),
            .light(effect: .solid(RGB.named["warm"]!), brightness: 77, temporary: false))
        XCTAssertEqual(try parse("--brightness=100 spectrum"), .light(effect: .spectrum, brightness: 255, temporary: false))
        XCTAssertEqual(try parse("brightness 50%"), .light(effect: nil, brightness: 128, temporary: false))
        XCTAssertEqual(try parse("-b 0"), .light(effect: nil, brightness: 0, temporary: false))
        XCTAssertEqual(try parse("brightness"), .showBrightness)
    }

    func testTemporary() throws {
        XCTAssertEqual(try parse("red --temporary"), .light(effect: .solid(RGB(255, 0, 0)), brightness: nil, temporary: true))
    }

    func testOtherCommands() throws {
        XCTAssertEqual(try parse(""), .help)
        XCTAssertEqual(try parse("static red --help"), .help)
        XCTAssertEqual(try parse("info"), .info)
        XCTAssertEqual(try parse("colours"), .colors)
        XCTAssertEqual(try parse("apply"), .apply)
        XCTAssertEqual(try parse("watch"), .watch)
        XCTAssertEqual(try parse("agent install"), .agent(.install))
    }

    func testUsageErrors() {
        let invalid = [
            "static", "static red blue", "static nope", "nope", "off red", "breathe red green blue",
            "wave sideways", "leds", "brightness 101", "brightness -1", "brightness abc", "brightness 10 -b 20",
            "-b", "--bogus", "red --delay 50", "--delay 50", "wave --delay 0", "wave --delay 256", "wave --delay", "info -b 10", "watch --temporary", "agent", "agent restart", "apply now",
            "leds " + [String](repeating: "red", count: 20).joined(separator: " "),
        ]
        for line in invalid {
            XCTAssertThrowsError(try parse(line), "\"\(line)\" should be rejected") { error in
                XCTAssertTrue(error is UsageError)
            }
        }
    }
}

final class SavedStateTests: XCTestCase {
    func testRecordKeepsWhatACommandDidNotChange() {
        var state = SavedState()
        XCTAssertTrue(state.isEmpty)
        state.record(effect: .spectrum, brightness: 100)
        state.record(effect: nil, brightness: 40)
        XCTAssertEqual(state, SavedState(effect: .spectrum, brightness: 40))
        state.record(effect: .off, brightness: nil)
        XCTAssertEqual(state, SavedState(effect: .off, brightness: 40))
    }

    func testReportsSendBrightnessBeforeTheEffect() {
        let state = SavedState(effect: .solid(RGB(1, 2, 3)), brightness: 40)
        XCTAssertEqual(
            state.reports(storage: .saved).map(wire),
            ["003f000000030f04 010028", "003f000000090f02 010001000001010203"])
        XCTAssertEqual(SavedState(brightness: 40).reports(storage: .saved).count, 1)
        XCTAssertTrue(SavedState().reports(storage: .saved).isEmpty)
    }

    func testSurvivesEncoding() throws {
        let effects: [Strider.Effect] = [
            .off, .solid(RGB(1, 2, 3)), .breathe([]), .breathe([RGB(1, 2, 3), RGB(4, 5, 6)]), .spectrum,
            .wave(.anticlockwise, delay: 200), .leds(RGB.spread([RGB(255, 0, 0), RGB(0, 0, 255)], across: Strider.ledCount)),
        ]
        for effect in effects {
            let state = SavedState(effect: effect, brightness: 77)
            let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
            XCTAssertEqual(decoded, state)
        }
    }

    func testPercentConversionRoundTrips() {
        for percent in 0...100 {
            XCTAssertEqual(Brightness.percent(fromByte: Brightness.byte(fromPercent: percent)), percent)
        }
        XCTAssertEqual(Brightness.byte(fromPercent: 100), 255)
        XCTAssertEqual(Brightness.byte(fromPercent: 0), 0)
    }
}
