/// The 90-byte HID feature report that Razer devices use for both requests and responses.
///
/// Layout, from OpenRazer's `struct razer_report` (driver/razercommon.h):
///
///     offset  size  field
///     0       1     status (0 in a request)
///     1       1     transaction id
///     2       2     remaining packets, big endian
///     4       1     protocol type (always 0)
///     5       1     data size: how many argument bytes are meaningful
///     6       1     command class
///     7       1     command id (bit 7 set means "read")
///     8       80    arguments
///     88      1     checksum: XOR of bytes 2 through 87
///     89      1     reserved (0)
public struct RazerReport: Equatable {
    public static let length = 90
    public static let argumentCapacity = 80

    public var status: UInt8
    public var transactionID: UInt8
    public var remainingPackets: UInt16
    public var protocolType: UInt8
    public var dataSize: UInt8
    public var commandClass: UInt8
    public var commandID: UInt8
    /// Always exactly 80 bytes.
    public private(set) var arguments: [UInt8]

    public init(
        transactionID: UInt8,
        commandClass: UInt8,
        commandID: UInt8,
        dataSize: UInt8,
        arguments: [UInt8] = []
    ) {
        precondition(arguments.count <= Self.argumentCapacity, "too many argument bytes")
        precondition(Int(dataSize) <= Self.argumentCapacity, "data size exceeds argument capacity")
        self.status = 0
        self.transactionID = transactionID
        self.remainingPackets = 0
        self.protocolType = 0
        self.dataSize = dataSize
        self.commandClass = commandClass
        self.commandID = commandID
        self.arguments = arguments + [UInt8](repeating: 0, count: Self.argumentCapacity - arguments.count)
    }

    /// Parses a report read back from the device. Returns nil if the length or checksum is wrong.
    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.length else { return nil }
        guard Self.checksum(of: bytes) == bytes[88] else { return nil }
        status = bytes[0]
        transactionID = bytes[1]
        remainingPackets = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        protocolType = bytes[4]
        dataSize = bytes[5]
        commandClass = bytes[6]
        commandID = bytes[7]
        arguments = Array(bytes[8..<88])
    }

    /// The report as it is sent on the wire, with the checksum filled in.
    public var bytes: [UInt8] {
        var out = [UInt8](repeating: 0, count: Self.length)
        out[0] = status
        out[1] = transactionID
        out[2] = UInt8(remainingPackets >> 8)
        out[3] = UInt8(remainingPackets & 0xFF)
        out[4] = protocolType
        out[5] = dataSize
        out[6] = commandClass
        out[7] = commandID
        out.replaceSubrange(8..<88, with: arguments)
        out[88] = Self.checksum(of: out)
        return out
    }

    static func checksum(of bytes: [UInt8]) -> UInt8 {
        bytes[2..<88].reduce(0, ^)
    }

    /// The meaningful part of the arguments, as declared by `dataSize`.
    public var payload: [UInt8] {
        Array(arguments[0..<min(Int(dataSize), Self.argumentCapacity)])
    }
}

/// The status byte of a response.
public enum RazerStatus: UInt8 {
    case new = 0x00
    case busy = 0x01
    case successful = 0x02
    case failure = 0x03
    case timeout = 0x04
    case notSupported = 0x05
}

extension RazerReport {
    /// True when this response answers `request`: same command, and nothing else queued.
    public func answers(_ request: RazerReport) -> Bool {
        commandClass == request.commandClass
            && commandID == request.commandID
            && remainingPackets == request.remainingPackets
    }
}
