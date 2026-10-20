import Foundation
import IOKit
import IOKit.ps

enum BatteryReader {
    static func read() async -> BatterySnapshot {
        var snapshot = readPublicPowerSource()
        if let details = await readSmartBatteryRegistry() {
            snapshot.temperatureCelsius = details.temperature.map { value in
                // AppleSmartBattery reports temperature in hundredths of a degree Celsius.
                value > 1_000 ? value / 100 : value
            }
            snapshot.cycleCount = details.cycleCount
            snapshot.designCapacity = details.designCapacity
            snapshot.maxCapacity = details.maxCapacity
            snapshot.currentCapacity = details.currentCapacity
            snapshot.voltageMillivolts = details.voltage
            snapshot.amperageMilliamps = details.amperage
            snapshot.serialNumber = details.serialNumber
        }
        return snapshot
    }

    private static func readPublicPowerSource() -> BatterySnapshot {
        var result = BatterySnapshot()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return result }

        for source in list {
            guard let dictionary = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  dictionary[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = dictionary[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = dictionary[kIOPSMaxCapacityKey] as? Int ?? 100
            result.percentage = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : 0
            result.isCharging = dictionary[kIOPSIsChargingKey] as? Bool ?? false
            result.isPluggedIn = (dictionary[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            result.isFullyCharged = dictionary[kIOPSIsChargedKey] as? Bool ?? false
            let time = dictionary[kIOPSTimeToEmptyKey] as? Int
            result.timeRemainingMinutes = (time ?? -1) >= 0 ? time : nil
            break
        }
        return result
    }

    private struct SmartBatteryData: Sendable {
        let temperature: Double?
        let cycleCount: Int?
        let designCapacity: Int?
        let maxCapacity: Int?
        let currentCapacity: Int?
        let voltage: Int?
        let amperage: Int?
        let serialNumber: String?
    }

    private static func readSmartBatteryRegistry() async -> SmartBatteryData? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            process.arguments = ["-a", "-r", "-n", "AppleSmartBattery"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
                else { return nil }
                guard let details = plist.first else { return nil }
                let dictionaries = flattenedDictionaries(in: details)
                func value(for keys: [String]) -> Any? {
                    for key in keys {
                        if let value = dictionaries.lazy.compactMap({ $0[key] }).first {
                            return value
                        }
                    }
                    return nil
                }
                return SmartBatteryData(
                    temperature: double(value(for: ["Temperature", "VirtualTemperature"])) ?? registryTemperature(),
                    cycleCount: int(value(for: ["CycleCount"])),
                    designCapacity: int(value(for: ["DesignCapacity"])),
                    maxCapacity: int(value(for: ["AppleRawMaxCapacity", "FullChargeCapacity"])),
                    currentCapacity: int(value(for: ["AppleRawCurrentCapacity", "RemainingCapacity"])),
                    voltage: int(value(for: ["Voltage", "AppleRawBatteryVoltage"])),
                    amperage: int(value(for: ["InstantAmperage", "Amperage"])),
                    serialNumber: value(for: ["Serial", "BatterySerialNumber"]) as? String
                )
            } catch {
                return nil
            }
        }.value
    }

    /// macOS 27 exposes sensor values in descendant registry nodes, while the
    /// public capacities remain on the parent AppleSmartBattery node.
    private static func flattenedDictionaries(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap(flattenedDictionaries)
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenedDictionaries)
        }
        return []
    }

    private static func registryTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            service,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(child, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any]
            else { continue }
            let battery = properties["BatteryData"] as? [String: Any] ?? [:]
            if let temperature = double(battery["Temperature"] ?? properties["Temperature"]) {
                return temperature
            }
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
