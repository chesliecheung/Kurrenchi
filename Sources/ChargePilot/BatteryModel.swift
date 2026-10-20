import AppKit
import Combine
import Foundation
import KurrenchiShared
import ServiceManagement

struct AppSettings: Codable, Sendable {
    var chargeLimit = 80
    var hardwareControlEnabled = false
    var sailingEnabled = true
    var sailingRange = 5
    var heatProtectionEnabled = true
    var temperatureLimit = 35.0
    var automaticDischarge = false
    var protectDuringSleep = true
    var showPercentage = true
    var refreshInterval = 15.0
    var launchAtLogin = false

    private enum CodingKeys: String, CodingKey {
        case chargeLimit, hardwareControlEnabled, sailingEnabled, sailingRange
        case heatProtectionEnabled, temperatureLimit, automaticDischarge
        case protectDuringSleep, showPercentage, refreshInterval, launchAtLogin
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        chargeLimit = try values.decodeIfPresent(Int.self, forKey: .chargeLimit) ?? 80
        hardwareControlEnabled = try values.decodeIfPresent(Bool.self, forKey: .hardwareControlEnabled) ?? false
        sailingEnabled = try values.decodeIfPresent(Bool.self, forKey: .sailingEnabled) ?? true
        sailingRange = try values.decodeIfPresent(Int.self, forKey: .sailingRange) ?? 5
        heatProtectionEnabled = try values.decodeIfPresent(Bool.self, forKey: .heatProtectionEnabled) ?? true
        temperatureLimit = try values.decodeIfPresent(Double.self, forKey: .temperatureLimit) ?? 35
        automaticDischarge = try values.decodeIfPresent(Bool.self, forKey: .automaticDischarge) ?? false
        protectDuringSleep = try values.decodeIfPresent(Bool.self, forKey: .protectDuringSleep) ?? true
        showPercentage = try values.decodeIfPresent(Bool.self, forKey: .showPercentage) ?? true
        refreshInterval = try values.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 15
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}

@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot()
    @Published private(set) var chargeState: ChargeState = .unavailable
    @Published var settings: AppSettings {
        didSet {
            saveSettings()
            syncHardwareConfig()
            if oldValue.launchAtLogin != settings.launchAtLogin { updateLaunchAtLogin() }
            if oldValue.refreshInterval != settings.refreshInterval { scheduleTimer() }
        }
    }
    @Published var calibrationPhase: CalibrationPhase = .idle
    @Published var isControlSimulation = true
    @Published var lastUpdated: Date?
    @Published private(set) var history: [BatterySample] = []
    @Published private(set) var hardwareStatus: KurrenchiHardwareStatus?
    @Published private(set) var helperInstalled = HelperInstaller.isInstalled
    @Published var controlMessage: String?

    private let controller: any ChargeControlling
    private var timer: Timer?
    private var refreshInFlight = false

    init(controller: any ChargeControlling = MonitoringChargeController()) {
        self.controller = controller
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        if let data = UserDefaults.standard.data(forKey: "batteryHistory"),
           let saved = try? JSONDecoder().decode([BatterySample].self, from: data) {
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            history = saved.filter { $0.date >= cutoff }
        }
        startMonitoring()
    }

    var menuBarText: String { settings.showPercentage ? "\(snapshot.percentage)%" : "" }
    var menuBarSymbol: String {
        if snapshot.isCharging { return "battery.100percent.bolt" }
        if snapshot.percentage <= 20 { return "battery.25percent" }
        if snapshot.percentage <= 50 { return "battery.50percent" }
        if snapshot.percentage <= 75 { return "battery.75percent" }
        return "battery.100percent"
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        Task {
            defer { refreshInFlight = false }
            let value = await BatteryReader.read()
            snapshot = value
            lastUpdated = Date()
            recordSample(value)
            loadHardwareState()
            await applyPolicy()
        }
    }

    func startCalibration() {
        guard helperInstalled else {
            controlMessage = "请先安装充电控制组件。"
            return
        }
        calibrationPhase = .chargingToFull
        updateHardwareConfig {
            $0.calibrationPhase = .chargingToFull
            $0.calibrationPhaseStartedAt = Date()
        }
    }

    func cancelCalibration() {
        calibrationPhase = .idle
        updateHardwareConfig {
            $0.calibrationPhase = .idle
            $0.calibrationPhaseStartedAt = nil
        }
    }

    func installHelper() {
        do {
            try HelperInstaller.install()
            helperInstalled = true
            isControlSimulation = false
            syncHardwareConfig()
            controlMessage = "控制组件安装成功。"
        } catch {
            controlMessage = error.localizedDescription
        }
    }

    func uninstallHelper() {
        do {
            updateHardwareConfig {
                $0.enabled = false
                $0.forceDischarge = false
                $0.topUpToFull = false
                $0.calibrationPhase = .idle
            }
            try HelperInstaller.uninstall()
            helperInstalled = false
            hardwareStatus = nil
            isControlSimulation = true
            controlMessage = "控制组件已移除，充电已恢复为系统默认。"
        } catch {
            controlMessage = error.localizedDescription
        }
    }

    func toggleForceDischarge() {
        updateHardwareConfig { $0.forceDischarge.toggle() }
    }

    func topUpToFull() {
        updateHardwareConfig {
            $0.topUpToFull = true
            $0.forceDischarge = false
        }
    }

    func cancelTopUp() { updateHardwareConfig { $0.topUpToFull = false } }

    func quit() { NSApplication.shared.terminate(nil) }

    private func startMonitoring() {
        refresh()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(2, settings.refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func applyPolicy() async {
        if helperInstalled,
           let status = hardwareStatus,
           Date().timeIntervalSince(status.lastUpdated) < 10 {
            isControlSimulation = false
            switch status.action {
            case .normal: chargeState = snapshot.isPluggedIn ? .charging : .discharging
            case .inhibit: chargeState = settings.heatProtectionEnabled && (snapshot.temperatureCelsius ?? 0) >= settings.temperatureLimit ? .heatPaused : .holding
            case .discharge: chargeState = .discharging
            }
            return
        }
        isControlSimulation = true
        if calibrationPhase != .idle && calibrationPhase != .complete {
            advanceCalibration()
            chargeState = .calibration
            return
        }

        let decision = ChargePolicy.decide(snapshot: snapshot, settings: settings)
        switch decision {
        case .allowCharging:
            try? await controller.requestDischarge(false)
            try? await controller.setChargingAllowed(true)
            chargeState = snapshot.isPluggedIn ? .charging : .discharging
        case .stopCharging:
            try? await controller.requestDischarge(false)
            try? await controller.setChargingAllowed(false)
            if settings.heatProtectionEnabled,
               (snapshot.temperatureCelsius ?? 0) >= settings.temperatureLimit {
                chargeState = .heatPaused
            } else {
                chargeState = settings.sailingEnabled ? .sailing : .holding
            }
        case .discharge:
            try? await controller.setChargingAllowed(false)
            try? await controller.requestDischarge(true)
            chargeState = .discharging
        }
    }

    private func advanceCalibration() {
        switch calibrationPhase {
        case .chargingToFull where snapshot.percentage >= 100:
            calibrationPhase = .holdingFull
        case .holdingFull:
            calibrationPhase = .discharging
            Task { try? await controller.requestDischarge(true) }
        case .discharging where snapshot.percentage <= 15:
            calibrationPhase = .recharging
            Task {
                try? await controller.requestDischarge(false)
                try? await controller.setChargingAllowed(true)
            }
        case .recharging where snapshot.percentage >= 100:
            calibrationPhase = .complete
        default: break
        }
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "settings")
    }

    private func updateLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            controlMessage = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    private func syncHardwareConfig() {
        guard HelperInstaller.isInstalled else { return }
        updateHardwareConfig {
            $0.enabled = settings.hardwareControlEnabled
            $0.upperLimit = settings.chargeLimit
            $0.lowerLimit = max(20, settings.chargeLimit - settings.sailingRange)
            $0.sailingEnabled = settings.sailingEnabled
            $0.heatProtectionEnabled = settings.heatProtectionEnabled
            $0.temperatureLimit = settings.temperatureLimit
            $0.automaticDischarge = settings.automaticDischarge
            $0.protectDuringSleep = settings.protectDuringSleep
        }
    }

    private func updateHardwareConfig(_ change: (inout KurrenchiConfig) -> Void) {
        guard HelperInstaller.isInstalled else {
            controlMessage = "请先安装充电控制组件。"
            return
        }
        var config = KurrenchiStore.readConfig()
        change(&config)
        do { try KurrenchiStore.writeConfig(config) }
        catch { controlMessage = "保存硬件策略失败：\(error.localizedDescription)" }
    }

    private func loadHardwareState() {
        helperInstalled = HelperInstaller.isInstalled
        hardwareStatus = KurrenchiStore.readStatus()
        let phase = KurrenchiStore.readConfig().calibrationPhase
        calibrationPhase = switch phase {
        case .idle: .idle
        case .chargingToFull: .chargingToFull
        case .holdingFull: .holdingFull
        case .discharging: .discharging
        case .recharging: .recharging
        case .complete: .complete
        }
    }

    private func recordSample(_ value: BatterySnapshot) {
        history.append(BatterySample(
            date: Date(),
            percentage: Double(value.percentage),
            powerWatts: value.powerWatts ?? 0,
            temperature: value.temperatureCelsius,
            isCharging: value.isCharging
        ))
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        history.removeAll { $0.date < cutoff }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "batteryHistory")
        }
    }
}
