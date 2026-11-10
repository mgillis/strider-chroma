import Foundation
import IOKit
import IOKit.pwr_mgt
import StriderKit

// IOKit declares these as C macros, which Swift does not import.
private let messageCanSystemSleep: UInt32 = 0xE000_0270
private let messageSystemWillSleep: UInt32 = 0xE000_0280
private let messageSystemHasPoweredOn: UInt32 = 0xE000_0300

/// Re-applies the saved setting whenever the mat is attached or the Mac wakes.
///
/// The mat keeps a stored effect and brightness through a loss of power, but
/// it cannot store a per-LED pattern, so after a replug (or a dock that
/// switches off during sleep) such a pattern has to be sent again.
final class Watcher {
    private var attachPort: IONotificationPortRef?
    private var attachIterator: io_iterator_t = 0
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var rootPowerDomain: io_connect_t = 0
    /// Incremented for every new request, so that an older retry sequence stops.
    private var generation = 0

    func run() -> Never {
        let context = Unmanaged.passUnretained(self).toOpaque()

        attachPort = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(attachPort, .main)
        let registered = IOServiceAddMatchingNotification(
            attachPort,
            kIOFirstMatchNotification,
            StriderDevice.matchingDictionary(),
            { context, iterator in
                Unmanaged<Watcher>.fromOpaque(context!).takeUnretainedValue().matAttached(iterator)
            },
            context,
            &attachIterator
        )
        guard registered == KERN_SUCCESS else {
            log("could not register for device notifications")
            exit(1)
        }
        // Reading the iterator to the end arms the notification. It also
        // reports a mat that is already attached, which is the case at login.
        matAttached(attachIterator)

        rootPowerDomain = IORegisterForSystemPower(
            context,
            &powerPort,
            { context, _, messageType, messageArgument in
                Unmanaged<Watcher>.fromOpaque(context!).takeUnretainedValue()
                    .powerChanged(messageType, messageArgument)
            },
            &powerNotifier
        )
        if rootPowerDomain != 0 {
            IONotificationPortSetDispatchQueue(powerPort, .main)
        } else {
            log("could not register for wake notifications. The setting will only be re-applied when the mat is attached")
        }

        log("watching for the mat")
        dispatchMain()
    }

    private func matAttached(_ iterator: io_iterator_t) {
        var sawControlInterface = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            if StriderDevice.isControlInterface(service) { sawControlInterface = true }
            IOObjectRelease(service)
        }
        if sawControlInterface { reapply(because: "mat attached") }
    }

    private func powerChanged(_ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case messageCanSystemSleep, messageSystemWillSleep:
            // The system waits up to 30 seconds for this acknowledgement before sleeping.
            IOAllowPowerChange(rootPowerDomain, Int(bitPattern: argument))
        case messageSystemHasPoweredOn:
            reapply(because: "woke from sleep")
        default:
            break
        }
    }

    /// The HID interface is announced slightly before it accepts reports, and
    /// USB devices behind a dock can take a few seconds to reappear after
    /// wake, so this retries for about 15 seconds before stopping.
    private func reapply(because reason: String) {
        generation += 1
        attempt(1, generation: generation, reason: reason)
    }

    private func attempt(_ number: Int, generation: Int, reason: String) {
        let delays: [Double] = [0.3, 1, 2, 4, 8]
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[number - 1]) { [self] in
            guard generation == self.generation else { return }
            do {
                let state = try StateFile.load()
                guard !state.isEmpty else {
                    log("\(reason), but no setting has been saved yet")
                    return
                }
                // The mat already holds whatever it is able to store, so this
                // does not ask it to write its memory again.
                try StriderDevice.open().send(state.reports(storage: .temporary))
                log("\(reason): applied \(describe(state))")
            } catch {
                if number < delays.count {
                    attempt(number + 1, generation: generation, reason: reason)
                } else {
                    log("\(reason): failed after \(number) attempts: \(error)")
                }
            }
        }
    }
}

func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    FileHandle.standardError.write(Data("\(formatter.string(from: Date())) \(message)\n".utf8))
}
