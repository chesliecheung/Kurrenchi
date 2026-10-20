import Foundation
import IOKit.pwr_mgt
import KurrenchiShared

final class HelperController: @unchecked Sendable {
    private var lastAction: HardwareAction = .normal
    private var backend: HardwareBackend = .unknown
    private var powerPort: io_connect_t = 0
    nonisolated(unsafe) private static var retainedSignalSource: DispatchSourceSignal?
    private let interval: TimeInterval = 2

    func run() {
        KurrenchiSMC.reset()
        installSignalHandler()
        installSleepHandler()
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run()
    }

    private func tick() {
        var config = KurrenchiStore.readConfig()
        guard let battery = BatteryProbe.current() else {
            publish(error: "无法读取内置电池数据", action: .normal)
            KurrenchiSMC.reset()
            return
        }
        updateCalibration(&config, battery: battery)

        if config.topUpToFull, battery.percent >= 100 {
            config.topUpToFull = false
            try? KurrenchiStore.writeConfig(config)
        }
        if config.forceDischarge, battery.percent <= max(config.upperLimit, KurrenchiConfig.dischargeFloor) {
            config.forceDischarge = false
            try? KurrenchiStore.writeConfig(config)
        }

        var action = config.action(
            percent: battery.percent,
            temperature: battery.temperature,
            pluggedIn: battery.pluggedIn,
            currentlyInhibited: lastAction != .normal
        )
        // Absolute safety floor: adapter fallback uses the battery for both
        // inhibit and discharge, so every non-normal action must stop here.
        if battery.percent <= KurrenchiConfig.dischargeFloor { action = .normal }

        do {
            backend = try KurrenchiSMC.apply(action)
            lastAction = action
            publish(error: nil, action: action)
        } catch {
            KurrenchiSMC.reset()
            lastAction = .normal
            backend = .unavailable
            publish(error: String(describing: error), action: .normal)
        }
    }

    private func updateCalibration(_ config: inout KurrenchiConfig, battery: HelperBatteryStatus) {
        switch config.calibrationPhase {
        case .chargingToFull where battery.percent >= 100:
            config.calibrationPhase = .holdingFull
            config.calibrationPhaseStartedAt = Date()
            try? KurrenchiStore.writeConfig(config)
        case .holdingFull:
            if Date().timeIntervalSince(config.calibrationPhaseStartedAt ?? Date()) >= 2 * 60 * 60 {
                config.calibrationPhase = .discharging
                config.calibrationPhaseStartedAt = Date()
                try? KurrenchiStore.writeConfig(config)
            }
        case .discharging where battery.percent <= KurrenchiConfig.dischargeFloor:
            config.calibrationPhase = .recharging
            config.calibrationPhaseStartedAt = Date()
            try? KurrenchiStore.writeConfig(config)
        case .recharging where battery.percent >= 100:
            config.calibrationPhase = .complete
            config.calibrationPhaseStartedAt = Date()
            try? KurrenchiStore.writeConfig(config)
        default:
            break
        }
    }

    private func publish(error: String?, action: HardwareAction) {
        var status = KurrenchiHardwareStatus()
        status.backend = backend
        status.action = action
        status.helperRunning = true
        status.lastUpdated = Date()
        status.lastError = error
        status.sleepProtectionAvailable = backend == .directSMC
        try? KurrenchiStore.writeStatus(status)
    }

    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { KurrenchiSMC.reset(); exit(0) }
        source.resume()
        Self.retainedSignalSource = source
    }

    private func installSleepHandler() {
        var notifier: io_object_t = 0
        var port: IONotificationPortRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerPort = IORegisterForSystemPower(context, &port, { context, _, type, argument in
            guard let context else { return }
            Unmanaged<HelperController>.fromOpaque(context).takeUnretainedValue().handlePower(type, argument)
        }, &notifier)
        if let port {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        }
    }

    private func handlePower(_ type: natural_t, _ argument: UnsafeMutableRawPointer?) {
        let canSleep: natural_t = 0xE000_0270
        let willSleep: natural_t = 0xE000_0280
        let didWake: natural_t = 0xE000_0300
        if type == canSleep {
            IOAllowPowerChange(powerPort, Int(bitPattern: argument))
        } else if type == willSleep {
            let config = KurrenchiStore.readConfig()
            backend = KurrenchiSMC.prepareForSleep(protectionEnabled: config.enabled && config.protectDuringSleep && !config.topUpToFull)
            IOAllowPowerChange(powerPort, Int(bitPattern: argument))
        } else if type == didWake {
            tick()
        }
    }
}
