import Foundation
import IOKit
import KurrenchiShared

// Adapted from MlayKlayer/battery-limiter and SMCKit under the MIT license.
// See Sources/KurrenchiShared/LICENSE-MIT.txt.
typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

enum SMCError: Error, CustomStringConvertible {
    case driverNotFound, failedToOpen, keyNotFound, notPrivileged
    case unknown(kern_return_t, UInt8)

    var description: String {
        switch self {
        case .driverNotFound: "AppleSMC driver not found"
        case .failedToOpen: "Could not open AppleSMC"
        case .keyNotFound: "SMC key not found"
        case .notPrivileged: "SMC key requires Apple's private entitlement"
        case .unknown(let code, let result): "SMC error \(code)/\(result)"
        }
    }
}

private extension FourCharCode {
    init(fromStaticString string: StaticString) {
        precondition(string.utf8CodeUnitCount == 4)
        self = string.withUTF8Buffer {
            UInt32($0[0]) << 24 | UInt32($0[1]) << 16 | UInt32($0[2]) << 8 | UInt32($0[3])
        }
    }
}

private struct SMCParamStruct {
    struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct PLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var memory: UInt32 = 0 }
    struct KeyInfo { var size: UInt32 = 0; var type: UInt32 = 0; var attributes: UInt8 = 0 }
    var key: UInt32 = 0
    var version = Version()
    var limit = PLimit()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private enum SMCTransport {
    nonisolated(unsafe) static var connection: io_connect_t = 0

    static func open() throws {
        guard connection == 0 else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            throw SMCError.failedToOpen
        }
    }

    static func close() {
        if connection != 0 { IOServiceClose(connection) }
        connection = 0
    }

    static func write(_ key: FourCharCode, _ value: UInt8) throws {
        try open()
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.size = 1
        input.data8 = 6 // kSMCWriteKey
        input.bytes.0 = value
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        if result == kIOReturnNotPrivileged { throw SMCError.notPrivileged }
        guard result == kIOReturnSuccess else { throw SMCError.unknown(result, output.result) }
        if output.result == 132 { throw SMCError.keyNotFound }
        guard output.result == 0 else { throw SMCError.unknown(result, output.result) }
    }
}

enum KurrenchiSMC {
    private static let chargeB = FourCharCode(fromStaticString: "CH0B")
    private static let chargeC = FourCharCode(fromStaticString: "CH0C")
    private static let adapter = FourCharCode(fromStaticString: "CH0I")

    @discardableResult
    static func apply(_ action: HardwareAction) throws -> HardwareBackend {
        switch action {
        case .normal:
            try SMCTransport.write(adapter, 0)
            do {
                try SMCTransport.write(chargeB, 0)
                try SMCTransport.write(chargeC, 0)
                return .directSMC
            } catch {
                return .adapterFallback
            }
        case .inhibit:
            do {
                try SMCTransport.write(adapter, 0)
                try SMCTransport.write(chargeB, 2)
                try SMCTransport.write(chargeC, 2)
                return .directSMC
            } catch {
                // macOS 27 gates charge keys. Cutting adapter input is the only
                // remaining SMC fallback and means the Mac runs on battery.
                try SMCTransport.write(adapter, 1)
                return .adapterFallback
            }
        case .discharge:
            try? SMCTransport.write(chargeB, 2)
            try? SMCTransport.write(chargeC, 2)
            try SMCTransport.write(adapter, 1)
            return .adapterFallback
        }
    }

    static func prepareForSleep(protectionEnabled: Bool) -> HardwareBackend {
        // Never leave adapter cut armed while asleep; it could drain the pack.
        try? SMCTransport.write(adapter, 0)
        guard protectionEnabled else {
            try? SMCTransport.write(chargeB, 0)
            try? SMCTransport.write(chargeC, 0)
            return .unknown
        }
        do {
            try SMCTransport.write(chargeB, 2)
            try SMCTransport.write(chargeC, 2)
            return .directSMC
        } catch {
            return .adapterFallback
        }
    }

    static func reset() {
        try? SMCTransport.write(adapter, 0)
        try? SMCTransport.write(chargeB, 0)
        try? SMCTransport.write(chargeC, 0)
        SMCTransport.close()
    }
}
