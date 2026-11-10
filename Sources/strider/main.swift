import Foundation
import StriderKit

func run(_ invocation: Invocation) throws {
    switch invocation {
    case .help:
        print(Invocation.usage)

    case .colors:
        for (name, color) in RGB.named.sorted(by: { $0.key < $1.key }) {
            print("\(name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(color.hex)")
        }

    case .light(let effect, let brightness, let temporary):
        let change = SavedState(effect: effect, brightness: brightness)
        try StriderDevice.open().send(change.reports(storage: temporary ? .temporary : .saved))
        if !temporary {
            var state = try StateFile.load()
            state.record(effect: effect, brightness: brightness)
            try StateFile.save(state)
        }
        print(describe(change) + (temporary ? " (temporary)" : ""))

    case .showBrightness:
        // The mat does not answer a brightness query, so this is the last value set here.
        guard let brightness = try StateFile.load().brightness else {
            print("unknown: no brightness has been set with this tool yet")
            return
        }
        print("\(Brightness.percent(fromByte: brightness))%")

    case .info:
        let device = try StriderDevice.open()
        let firmware = Strider.firmwareVersion(from: try device.send(Strider.getFirmwareVersion()))
        let serial = Strider.serial(from: try device.send(Strider.getSerial()))
        print("device    Razer Strider Chroma (USB 1532:0c05)")
        print("firmware  \(firmware)")
        print("serial    \(serial)")
        print("setting   \(describe(try StateFile.load()))")

    case .apply:
        let state = try StateFile.load()
        guard !state.isEmpty else {
            throw DeviceError(description: "there is no saved setting to apply. Set the lighting first, for example \"strider warm\"")
        }
        try StriderDevice.open().send(state.reports(storage: .temporary))
        print(describe(state))

    case .watch:
        Watcher().run()

    case .agent(let action):
        try Agent.run(action)
    }
}

do {
    try run(try Invocation.parse(Array(CommandLine.arguments.dropFirst())))
} catch let error as UsageError {
    FileHandle.standardError.write(Data("strider: \(error)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("strider: \(error)\n".utf8))
    exit(1)
}
