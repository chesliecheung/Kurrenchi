import Foundation
import Testing
@testable import Kurrenchi
@testable import KurrenchiShared

@Suite("Charge policy")
struct ChargePolicyTests {
    @Test("Charges below the sailing floor")
    func chargesBelowFloor() {
        var settings = AppSettings()
        settings.chargeLimit = 80
        settings.sailingRange = 5
        var snapshot = BatterySnapshot()
        snapshot.percentage = 74
        #expect(ChargePolicy.decide(snapshot: snapshot, settings: settings) == .allowCharging)
    }

    @Test("Holds inside the sailing band")
    func holdsInBand() {
        var settings = AppSettings()
        settings.chargeLimit = 80
        var snapshot = BatterySnapshot()
        snapshot.percentage = 78
        #expect(ChargePolicy.decide(snapshot: snapshot, settings: settings) == .stopCharging)
    }

    @Test("Discharges above the configured limit")
    func dischargesAboveLimit() {
        var settings = AppSettings()
        settings.chargeLimit = 80
        settings.automaticDischarge = true
        var snapshot = BatterySnapshot()
        snapshot.percentage = 83
        #expect(ChargePolicy.decide(snapshot: snapshot, settings: settings) == .discharge)
    }

    @Test("Does not force discharge unless automatic discharge is enabled")
    func doesNotDischargeWithoutPermission() {
        var settings = AppSettings()
        settings.chargeLimit = 80
        settings.automaticDischarge = false
        var snapshot = BatterySnapshot()
        snapshot.percentage = 83
        #expect(ChargePolicy.decide(snapshot: snapshot, settings: settings) == .stopCharging)
    }

    @Test("Heat protection stops charging")
    func heatProtection() {
        var settings = AppSettings()
        settings.temperatureLimit = 35
        var snapshot = BatterySnapshot()
        snapshot.percentage = 40
        snapshot.temperatureCelsius = 38
        #expect(ChargePolicy.decide(snapshot: snapshot, settings: settings) == .stopCharging)
    }
}

@Suite("Settings compatibility")
struct SettingsCompatibilityTests {
    @Test("Older settings keep defaults for newly added options")
    func migratesOlderSettings() throws {
        let data = Data(#"{"chargeLimit":72,"sailingEnabled":false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.chargeLimit == 72)
        #expect(settings.sailingEnabled == false)
        #expect(settings.heatProtectionEnabled == true)
        #expect(settings.protectDuringSleep == true)
        #expect(settings.refreshInterval == 15)
    }
}

@Suite("Hardware policy")
struct HardwarePolicyTests {
    @Test("Temperature protection outranks top-up")
    func heatOutranksTopUp() {
        var config = KurrenchiConfig()
        config.enabled = true
        config.topUpToFull = true
        config.temperatureLimit = 35
        #expect(config.action(percent: 60, temperature: 39, pluggedIn: true, currentlyInhibited: false) == .inhibit)
    }

    @Test("Top-up overrides the regular limit")
    func topUpOverridesLimit() {
        var config = KurrenchiConfig()
        config.enabled = true
        config.upperLimit = 60
        config.topUpToFull = true
        #expect(config.action(percent: 80, temperature: 25, pluggedIn: true, currentlyInhibited: true) == .normal)
    }

    @Test("Sailing mode holds until the lower boundary")
    func sailingHysteresis() {
        var config = KurrenchiConfig()
        config.enabled = true
        config.upperLimit = 80
        config.lowerLimit = 70
        #expect(config.action(percent: 75, temperature: 25, pluggedIn: true, currentlyInhibited: true) == .inhibit)
        #expect(config.action(percent: 70, temperature: 25, pluggedIn: true, currentlyInhibited: true) == .normal)
    }

    @Test("Configuration clamps limits to safe bounds")
    func normalization() {
        var config = KurrenchiConfig()
        config.upperLimit = 5
        config.lowerLimit = 1
        config.temperatureLimit = 99
        config.normalize()
        #expect(config.upperLimit == 20)
        #expect(config.lowerLimit == 20)
        #expect(config.temperatureLimit == 50)
    }
}
