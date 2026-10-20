import Foundation

public enum HardwareAction: String, Codable, Sendable {
    case normal
    case inhibit
    case discharge
}

public enum HardwareBackend: String, Codable, Sendable {
    case unknown
    case directSMC
    case adapterFallback
    case nativeLimit
    case unavailable
}

public enum HardwareCalibrationPhase: String, Codable, Sendable {
    case idle
    case chargingToFull
    case holdingFull
    case discharging
    case recharging
    case complete
}

public struct KurrenchiConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var upperLimit = 80
    public var lowerLimit = 75
    public var sailingEnabled = true
    public var heatProtectionEnabled = true
    public var temperatureLimit = 35.0
    public var automaticDischarge = false
    public var forceDischarge = false
    public var topUpToFull = false
    public var protectDuringSleep = true
    public var calibrationPhase: HardwareCalibrationPhase = .idle
    public var calibrationPhaseStartedAt: Date?

    public static let dischargeFloor = 20

    public init() {}

    public mutating func normalize() {
        upperLimit = min(100, max(20, upperLimit))
        lowerLimit = upperLimit == 20 ? 20 : min(upperLimit - 1, max(20, lowerLimit))
        temperatureLimit = min(50, max(30, temperatureLimit))
    }

    public func action(
        percent: Int,
        temperature: Double?,
        pluggedIn: Bool,
        currentlyInhibited: Bool
    ) -> HardwareAction {
        guard pluggedIn else { return .normal }

        // Temperature protection always wins, including over top-up/calibration.
        if heatProtectionEnabled,
           percent > Self.dischargeFloor,
           let temperature,
           temperature >= temperatureLimit {
            return .inhibit
        }

        switch calibrationPhase {
        case .chargingToFull, .holdingFull, .recharging:
            return .normal
        case .discharging:
            return percent > Self.dischargeFloor ? .discharge : .normal
        case .idle, .complete:
            break
        }

        if topUpToFull { return .normal }
        if forceDischarge { return percent > max(upperLimit, Self.dischargeFloor) ? .discharge : .inhibit }
        guard enabled else { return .normal }

        if automaticDischarge, percent > upperLimit { return .discharge }
        let resume = sailingEnabled ? lowerLimit : upperLimit - 1
        let shouldStop = currentlyInhibited ? percent > resume : percent >= upperLimit
        return shouldStop ? .inhibit : .normal
    }
}

public struct KurrenchiHardwareStatus: Codable, Sendable {
    public var backend: HardwareBackend = .unknown
    public var action: HardwareAction = .normal
    public var helperRunning = false
    public var lastUpdated = Date.distantPast
    public var lastError: String?
    public var sleepProtectionAvailable = false

    public init() {}
}

public enum KurrenchiStore {
    public static let directory = URL(fileURLWithPath: "/Library/Application Support/Kurrenchi", isDirectory: true)
    public static let configURL = directory.appendingPathComponent("config.json")
    public static let statusURL = directory.appendingPathComponent("status.json")

    public static func readConfig() -> KurrenchiConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(KurrenchiConfig.self, from: data)
        else { return KurrenchiConfig() }
        return config
    }

    public static func writeConfig(_ value: KurrenchiConfig) throws {
        var config = value
        config.normalize()
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)
    }

    public static func readStatus() -> KurrenchiHardwareStatus? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(KurrenchiHardwareStatus.self, from: data)
    }

    public static func writeStatus(_ value: KurrenchiHardwareStatus) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: statusURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: statusURL.path)
    }
}
