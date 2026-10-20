import Foundation

struct BatterySnapshot: Sendable {
    var percentage = 0
    var isCharging = false
    var isPluggedIn = false
    var isFullyCharged = false
    var temperatureCelsius: Double?
    var cycleCount: Int?
    var designCapacity: Int?
    var maxCapacity: Int?
    var currentCapacity: Int?
    var voltageMillivolts: Int?
    var amperageMilliamps: Int?
    var timeRemainingMinutes: Int?
    var serialNumber: String?

    var healthPercent: Int? {
        guard let designCapacity, let maxCapacity, designCapacity > 0 else { return nil }
        return Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())
    }

    var powerWatts: Double? {
        guard let voltageMillivolts, let amperageMilliamps else { return nil }
        return Double(voltageMillivolts) * Double(amperageMilliamps) / 1_000_000
    }
}

enum ChargeState: String, Sendable {
    case charging = "充电中"
    case discharging = "放电中"
    case holding = "保持"
    case heatPaused = "温度保护"
    case sailing = "Sailing"
    case calibration = "校准中"
    case unavailable = "不可用"
}

enum CalibrationPhase: String, Codable, CaseIterable {
    case idle = "未运行"
    case chargingToFull = "充至 100%"
    case holdingFull = "满电静置"
    case discharging = "放电至 20%"
    case recharging = "重新充满"
    case complete = "已完成"
}

struct BatterySample: Identifiable, Sendable, Codable {
    let id: UUID
    let date: Date
    let percentage: Double
    let powerWatts: Double
    let temperature: Double?
    let isCharging: Bool

    init(id: UUID = UUID(), date: Date, percentage: Double, powerWatts: Double,
         temperature: Double?, isCharging: Bool) {
        self.id = id
        self.date = date
        self.percentage = percentage
        self.powerWatts = powerWatts
        self.temperature = temperature
        self.isCharging = isCharging
    }
}
