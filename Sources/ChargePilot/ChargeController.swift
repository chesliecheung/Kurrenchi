import Foundation

/// The control boundary is intentionally isolated. A production build can replace
/// `MonitoringChargeController` with a signed SMAppService helper implementation.
protocol ChargeControlling: Sendable {
    func setChargingAllowed(_ allowed: Bool) async throws
    func requestDischarge(_ enabled: Bool) async throws
    func reset() async throws
}

struct MonitoringChargeController: ChargeControlling {
    func setChargingAllowed(_ allowed: Bool) async throws {}
    func requestDischarge(_ enabled: Bool) async throws {}
    func reset() async throws {}
}

enum ChargeDecision: Equatable {
    case allowCharging
    case stopCharging
    case discharge
}

struct ChargePolicy {
    static func decide(snapshot: BatterySnapshot, settings: AppSettings) -> ChargeDecision {
        if settings.heatProtectionEnabled,
           let temperature = snapshot.temperatureCelsius,
           temperature >= settings.temperatureLimit,
           snapshot.percentage > 20 {
            return .stopCharging
        }

        if settings.sailingEnabled {
            let lower = max(20, settings.chargeLimit - settings.sailingRange)
            if snapshot.percentage > settings.chargeLimit {
                return settings.automaticDischarge ? .discharge : .stopCharging
            }
            if snapshot.percentage <= lower { return .allowCharging }
            return .stopCharging
        }

        if snapshot.percentage >= settings.chargeLimit { return .stopCharging }
        return .allowCharging
    }
}
