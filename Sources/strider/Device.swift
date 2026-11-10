import Foundation
import IOKit
import IOKit.hid
import StriderKit

struct DeviceError: Error, CustomStringConvertible {
    let description: String
}

/// An open connection to the mat's control interface.
///
/// The mat presents three HID interfaces. Interface 0 (a mouse-type
/// interface) is the only one with a 90-byte feature report, and that report
/// carries every Razer command. The other two are keyboard-type interfaces,
/// which macOS will not let a process open without Input Monitoring
/// permission, so this never opens them.
final class StriderDevice {
    private let hid: IOHIDDevice

    /// Matches every HID interface of the mat.
    static func matchingDictionary() -> NSMutableDictionary {
        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        matching[kIOHIDVendorIDKey] = Strider.vendorID
        matching[kIOHIDProductIDKey] = Strider.productID
        return matching
    }

    static func isControlInterface(_ service: io_service_t) -> Bool {
        let size = IORegistryEntryCreateCFProperty(
            service, kIOHIDMaxFeatureReportSizeKey as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return (size as? Int) == RazerReport.length
    }

    static func open() throws -> StriderDevice {
        var iterator: io_iterator_t = 0
        let found = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary(), &iterator)
        guard found == KERN_SUCCESS else {
            throw DeviceError(description: "could not search the IO registry (\(describe(found)))")
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard isControlInterface(service) else { continue }
            guard let hid = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let opened = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else {
                throw DeviceError(description: "found the mat but could not open it (\(describe(opened)))")
            }
            return StriderDevice(hid: hid)
        }
        throw DeviceError(
            description: "no Razer Strider Chroma found (looked for USB 1532:0c05). Is it plugged in?"
        )
    }

    private init(hid: IOHIDDevice) {
        self.hid = hid
    }

    deinit {
        IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Sends a request and returns the device's successful response.
    ///
    /// The exchange is a SET_REPORT followed by a GET_REPORT on the same
    /// feature report. The device needs a short delay between the two, and
    /// answers "busy" if asked too soon, so this retries with a growing delay.
    @discardableResult
    func send(_ request: RazerReport) throws -> RazerReport {
        let out = request.bytes
        var problem = "no response"

        for attempt in 0..<6 {
            if attempt > 0 { usleep(UInt32(attempt) * 15_000) }

            let sent = IOHIDDeviceSetReport(hid, kIOHIDReportTypeFeature, 0, out, out.count)
            guard sent == kIOReturnSuccess else {
                problem = "could not send the request (\(describe(sent)))"
                continue
            }

            usleep(2_000)

            var buffer = [UInt8](repeating: 0, count: RazerReport.length)
            var length = buffer.count
            let received = IOHIDDeviceGetReport(hid, kIOHIDReportTypeFeature, 0, &buffer, &length)
            guard received == kIOReturnSuccess else {
                problem = "could not read the response (\(describe(received)))"
                continue
            }
            guard length == RazerReport.length, let response = RazerReport(bytes: buffer) else {
                problem = "the response was malformed"
                continue
            }
            guard response.answers(request) else {
                problem = "the response was for a different command"
                continue
            }

            switch RazerStatus(rawValue: response.status) {
            case .successful:
                return response
            case .notSupported:
                throw DeviceError(description: "the mat reports that it does not support this command")
            case .busy:
                problem = "the mat stayed busy"
            case .failure:
                problem = "the mat rejected the command"
            case .timeout:
                problem = "the mat timed out handling the command"
            case .new, .none:
                problem = "the mat returned status \(response.status)"
            }
        }
        throw DeviceError(description: problem)
    }
}

private func describe(_ code: IOReturn) -> String {
    let hex = "0x" + String(UInt32(bitPattern: code), radix: 16)
    switch code {
    case kIOReturnNotPermitted, kIOReturnNotPrivileged:
        return "not permitted, \(hex)"
    case kIOReturnExclusiveAccess:
        return "another program has exclusive access, \(hex)"
    case kIOReturnNoDevice, kIOReturnNotAttached:
        return "the device was disconnected, \(hex)"
    case kIOReturnTimeout:
        return "timed out, \(hex)"
    default:
        return hex
    }
}
