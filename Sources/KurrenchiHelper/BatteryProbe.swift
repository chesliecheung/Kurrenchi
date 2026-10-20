import Foundation
import IOKit

struct HelperBatteryStatus {
    let percent: Int
    let temperature: Double?
    let pluggedIn: Bool
}

enum BatteryProbe {
    static func current() -> HelperBatteryStatus? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return nil }
        let battery = properties["BatteryData"] as? [String: Any] ?? [:]
        let percent = number(properties["CurrentCapacity"] ?? battery["CurrentCapacity"])?.intValue ?? 0
        let rawTemperature = number(battery["Temperature"] ?? properties["Temperature"])?.doubleValue
            ?? descendantTemperature(from: service)
        let temperature = rawTemperature.map { $0 > 1_000 ? $0 / 100 : $0 }
        let pluggedIn = (properties["ExternalConnected"] as? Bool)
            ?? number(properties["ExternalConnected"])?.boolValue
            ?? false
        return HelperBatteryStatus(percent: percent, temperature: temperature, pluggedIn: pluggedIn)
    }

    private static func descendantTemperature(from service: io_registry_entry_t) -> Double? {
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
            if let temperature = number(battery["Temperature"] ?? properties["Temperature"])?.doubleValue {
                return temperature
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> NSNumber? {
        if let value = value as? NSNumber { return value }
        if let value = value as? Int { return NSNumber(value: value) }
        return nil
    }
}
