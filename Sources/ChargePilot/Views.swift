import AppKit
import Charts
import SwiftUI

private enum KurrenchiTheme {
    static let amber = Color(red: 1.00, green: 0.47, blue: 0.10)
    static let mint = Color(red: 0.12, green: 0.76, blue: 0.58)
    static let cyan = Color(red: 0.18, green: 0.68, blue: 0.91)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
}

private let pilotGreen = KurrenchiTheme.mint

private extension View {
    func kurrenchiSurface(radius: CGFloat = 20) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(0.035))
                    .blur(radius: 0.4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var model: BatteryModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            AmbientGlow().opacity(0.62)

            VStack(spacing: 15) {
                HStack {
                    HStack(spacing: 9) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Kurrenchi").font(.headline.weight(.bold))
                            Text("电池控制台").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusCapsule(text: model.chargeState.rawValue, active: !model.isControlSimulation)
                }

                HStack(alignment: .center, spacing: 18) {
                    BatteryRing(percentage: model.snapshot.percentage, charging: model.snapshot.isCharging)
                        .frame(width: 102, height: 102)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.snapshot.isPluggedIn ? "外接能源在线" : "移动能源模式")
                            .font(.title3.weight(.semibold))
                        Label(
                            model.snapshot.isPluggedIn ? "适配器已连接" : "正在使用内置电池",
                            systemImage: model.snapshot.isPluggedIn ? "powerplug.fill" : "bolt.slash.fill"
                        ).font(.caption).foregroundStyle(.secondary)
                        if let temperature = model.snapshot.temperatureCelsius {
                            Label(String(format: "核心温度 %.1f °C", temperature), systemImage: "thermometer.medium")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                VStack(spacing: 9) {
                    HStack {
                        Label("能量边界", systemImage: "scope").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(model.settings.chargeLimit)%")
                            .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                            .foregroundStyle(KurrenchiTheme.amber)
                    }
                    Slider(value: Binding(get: { Double(model.settings.chargeLimit) },
                                          set: { model.settings.chargeLimit = Int($0) }),
                           in: 20...100, step: 1).tint(KurrenchiTheme.amber)
                    HStack {
                        Text("20").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text("100").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(14).kurrenchiSurface(radius: 16)

                if model.history.count > 1 {
                    MiniBatteryChart(samples: model.history).frame(height: 48)
                        .padding(.horizontal, 4)
                }

                HStack(spacing: 9) {
                    CompactMetric(title: "健康", value: model.snapshot.healthPercent.map { "\($0)%" } ?? "—", icon: "heart.fill")
                    CompactMetric(title: "循环", value: model.snapshot.cycleCount.map(String.init) ?? "—", icon: "repeat")
                    CompactMetric(title: "功耗", value: model.snapshot.powerWatts.map { String(format: "%+.1fW", $0) } ?? "—", icon: "waveform.path.ecg")
                }

                if model.isControlSimulation {
                    HStack(spacing: 9) {
                        Image(systemName: "shield.lefthalf.filled").foregroundStyle(KurrenchiTheme.amber)
                        Text("当前为安全监测模式 · 安装控制组件后启用能源策略")
                        Spacer()
                    }
                    .font(.caption).padding(11)
                    .background(KurrenchiTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }

                if model.helperInstalled {
                    HStack(spacing: 9) {
                        QuickAction(title: "释放能量", icon: "arrow.down.right.circle.fill", tint: KurrenchiTheme.amber) {
                            model.toggleForceDischarge()
                        }
                        QuickAction(title: "临时满航", icon: "bolt.circle.fill", tint: KurrenchiTheme.mint) {
                            model.topUpToFull()
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        openWindow(id: "dashboard")
                        NSApplication.shared.activate()
                    } label: { Label("打开 Energy Studio", systemImage: "sparkles.rectangle.stack.fill") }
                    .buttonStyle(.borderedProminent).tint(KurrenchiTheme.ink)
                    Spacer()
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    Button { openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                    Button { model.quit() } label: { Image(systemName: "power") }.help("退出")
                }.buttonStyle(.borderless)
            }
            .padding(18)
        }
        .frame(width: 404)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: BatteryModel
    @State private var chartMetric: ChartMetric = .level

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            AmbientGlow().opacity(0.78).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable().frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kurrenchi").font(.title2.bold())
                            Text("智能电池控制台").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusCapsule(text: model.chargeState.rawValue, active: !model.isControlSimulation)
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        BatteryHeroCard().frame(width: 300)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                            MetricCard(title: "健康度", value: model.snapshot.healthPercent.map { "\($0)%" } ?? "—", icon: "heart.fill", tint: .pink)
                            MetricCard(title: "循环次数", value: model.snapshot.cycleCount.map(String.init) ?? "—", icon: "repeat", tint: KurrenchiTheme.cyan)
                            MetricCard(title: "电池温度", value: model.snapshot.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—", icon: "thermometer.medium", tint: KurrenchiTheme.amber)
                            MetricCard(title: "实时功耗", value: model.snapshot.powerWatts.map { String(format: "%+.1f W", $0) } ?? "—", icon: "bolt.fill", tint: KurrenchiTheme.mint)
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("能量轨迹").font(.title3.bold())
                                    Text("最近 24 小时的本地采样").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("指标", selection: $chartMetric) {
                                    ForEach(ChartMetric.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented).frame(width: 250)
                            }
                            HistoryChart(samples: model.history, metric: chartMetric).frame(height: 230)
                        }
                        .padding(18).frame(maxWidth: .infinity).kurrenchiSurface()

                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Label("能量边界", systemImage: "scope").font(.headline)
                                Spacer()
                                Text("\(model.settings.chargeLimit)%")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(KurrenchiTheme.amber)
                            }
                            Slider(value: Binding(get: { Double(model.settings.chargeLimit) },
                                                  set: { model.settings.chargeLimit = Int($0) }),
                                   in: 20...100, step: 1).tint(KurrenchiTheme.amber)
                            Divider()
                            StrategyToggle(title: "航行缓冲", icon: "water.waves", isOn: $model.settings.sailingEnabled)
                            StrategyToggle(title: "温度护盾", icon: "thermometer.high", isOn: $model.settings.heatProtectionEnabled)
                            StrategyToggle(title: "硬件控制", icon: "cpu", isOn: $model.settings.hardwareControlEnabled)
                            StrategyToggle(title: "自动释放", icon: "arrow.down.to.line", isOn: $model.settings.automaticDischarge)
                            StrategyToggle(title: "睡眠保护", icon: "moon.zzz", isOn: $model.settings.protectDuringSleep)
                        }
                        .padding(18).frame(width: 300).kurrenchiSurface()
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        MetricCard(title: "充电电流", value: currentText(charging: true), icon: "arrow.down.to.line", tint: KurrenchiTheme.mint)
                        MetricCard(title: "放电电流", value: currentText(charging: false), icon: "arrow.up.to.line", tint: KurrenchiTheme.amber)
                        MetricCard(title: "设计容量", value: model.snapshot.designCapacity.map { "\($0) mAh" } ?? "—", icon: "shippingbox.fill", tint: .purple)
                        MetricCard(title: "最大容量", value: model.snapshot.maxCapacity.map { "\($0) mAh" } ?? "—", icon: "gauge.with.dots.needle.67percent", tint: KurrenchiTheme.cyan)
                        MetricCard(title: "电池电压", value: model.snapshot.voltageMillivolts.map { String(format: "%.2f V", Double($0) / 1000) } ?? "—", icon: "waveform", tint: .blue)
                        MetricCard(title: "硬件序列号", value: model.snapshot.serialNumber ?? "—", icon: "number", tint: .secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .font(.title2).foregroundStyle(KurrenchiTheme.amber)
                                VStack(alignment: .leading) {
                                    Text("精准校准").font(.headline)
                                    Text(model.calibrationPhase.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            CalibrationSteps(active: model.calibrationPhase)
                            HStack {
                                Text("以完整充放电闭环重新对齐 BMS 计量").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if model.calibrationPhase == .idle || model.calibrationPhase == .complete {
                                    Button("开始校准") { model.startCalibration() }.buttonStyle(.borderedProminent).tint(KurrenchiTheme.ink)
                                } else {
                                    Button("取消校准", role: .destructive) { model.cancelCalibration() }
                                }
                            }
                        }
                        .padding(18).frame(maxWidth: .infinity).kurrenchiSurface()

                        SystemControlCard().frame(maxWidth: .infinity)
                    }
                }.padding(24)
            }
        }
        .containerBackground(.ultraThinMaterial, for: .window)
    }

    private func currentText(charging: Bool) -> String {
        guard let current = model.snapshot.amperageMilliamps else { return "—" }
        let value = charging ? max(0, current) : abs(min(0, current))
        return "\(value) mA"
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: BatteryModel
    @State private var confirmsUninstall = false
    var body: some View {
        TabView {
            Form {
                Section("充电") {
                    Stepper("充电上限：\(model.settings.chargeLimit)%", value: $model.settings.chargeLimit, in: 20...100)
                    Toggle("启用硬件充电控制", isOn: $model.settings.hardwareControlEnabled)
                    Toggle("启用 Sailing Mode", isOn: $model.settings.sailingEnabled)
                    Stepper("Sailing 区间：\(model.settings.sailingRange)%", value: $model.settings.sailingRange, in: 1...20)
                    Toggle("自动放电至新上限", isOn: $model.settings.automaticDischarge)
                    Toggle("睡眠前写入安全状态", isOn: $model.settings.protectDuringSleep)
                }
                Section("温度保护") {
                    Toggle("超过阈值后暂停充电", isOn: $model.settings.heatProtectionEnabled)
                    HStack {
                        Slider(value: $model.settings.temperatureLimit, in: 30...50, step: 1)
                        Text("\(Int(model.settings.temperatureLimit)) °C").monospacedDigit()
                    }
                }
            }.tabItem { Label("电池", systemImage: "battery.75percent") }

            Form {
                Toggle("在菜单栏显示百分比", isOn: $model.settings.showPercentage)
                Toggle("登录时自动启动", isOn: $model.settings.launchAtLogin)
                LabeledContent("启动方式", value: "仅菜单栏，不自动打开窗口")
                Button("打开 macOS 电池设置") { openChargingSettings() }
                if model.helperInstalled {
                    LabeledContent("Helper 状态", value: "已安装")
                    Button("卸载 Helper 组件…", role: .destructive) { confirmsUninstall = true }
                } else {
                    Button("安装充电控制组件…") { model.installHelper() }
                }
                if let message = model.controlMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }.tabItem { Label("通用", systemImage: "gearshape") }

            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 88, height: 88)
                Text("Kurrenchi").font(.title2.bold())
                Text("macOS 电池健康与充电控制工具\nSMC 控制能力取决于当前固件")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(AmbientGlow().opacity(0.36))
        .alert("卸载 Kurrenchi Helper？", isPresented: $confirmsUninstall) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) { model.uninstallHelper() }
        } message: {
            Text("后台服务与控制配置会被移除，充电立即恢复为系统默认。")
        }
    }
}

private struct BatteryHeroCard: View {
    @EnvironmentObject private var model: BatteryModel

    var body: some View {
        HStack(spacing: 18) {
            BatteryRing(percentage: model.snapshot.percentage, charging: model.snapshot.isCharging)
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.snapshot.isPluggedIn ? "已连接适配器" : "正在使用电池")
                    .font(.headline)
                Label(model.chargeState.rawValue, systemImage: model.snapshot.isPluggedIn ? "powerplug.fill" : "bolt.slash.fill")
                    .font(.caption).foregroundStyle(.secondary)
                if let updated = model.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .kurrenchiSurface(radius: 24)
    }
}

private struct AmbientGlow: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(KurrenchiTheme.amber.opacity(0.22))
                    .frame(width: proxy.size.width * 0.48)
                    .blur(radius: 90)
                    .offset(x: -proxy.size.width * 0.30, y: -proxy.size.height * 0.20)
                Circle()
                    .fill(KurrenchiTheme.cyan.opacity(0.13))
                    .frame(width: proxy.size.width * 0.42)
                    .blur(radius: 110)
                    .offset(x: proxy.size.width * 0.34, y: proxy.size.height * 0.30)
                RoundedRectangle(cornerRadius: 200)
                    .fill(KurrenchiTheme.mint.opacity(0.08))
                    .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 0.24)
                    .blur(radius: 95)
                    .rotationEffect(.degrees(-12))
                    .offset(y: proxy.size.height * 0.08)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct StatusCapsule: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(active ? KurrenchiTheme.mint : KurrenchiTheme.amber)
                .frame(width: 6, height: 6)
                .shadow(color: active ? KurrenchiTheme.mint : KurrenchiTheme.amber, radius: 4)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.primary.opacity(0.06), in: Capsule())
    }
}

private struct QuickAction: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(11).frame(maxWidth: .infinity)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct StrategyToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: icon).font(.subheadline)
        }
        .toggleStyle(.switch).tint(KurrenchiTheme.amber)
    }
}

private struct EnergyFlowBackdrop: View {
    var body: some View {
        Canvas { context, size in
            var primary = Path()
            primary.move(to: CGPoint(x: -40, y: size.height * 0.60))
            primary.addCurve(
                to: CGPoint(x: size.width + 40, y: size.height * 0.43),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.25),
                control2: CGPoint(x: size.width * 0.67, y: size.height * 0.82)
            )
            context.stroke(
                primary,
                with: .linearGradient(
                    Gradient(colors: [.clear, KurrenchiTheme.amber.opacity(0.55), .clear]),
                    startPoint: CGPoint(x: 0, y: size.height / 2),
                    endPoint: CGPoint(x: size.width, y: size.height / 2)
                ),
                lineWidth: 1.4
            )

            var secondary = Path()
            secondary.move(to: CGPoint(x: -20, y: size.height * 0.34))
            secondary.addCurve(
                to: CGPoint(x: size.width + 20, y: size.height * 0.68),
                control1: CGPoint(x: size.width * 0.32, y: size.height * 0.77),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.22)
            )
            context.stroke(secondary, with: .color(.primary.opacity(0.08)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct SystemControlCard: View {
    @EnvironmentObject private var model: BatteryModel
    @State private var confirmsUninstall = false

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "shield.checkered")
                .font(.title2).foregroundStyle(KurrenchiTheme.mint)
                .frame(width: 42, height: 42)
                .background(KurrenchiTheme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline)
                Text(statusDetail)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.helperInstalled {
                VStack(alignment: .trailing, spacing: 7) {
                    Button("系统电池设置") { openChargingSettings() }
                    Button("卸载 Helper…", role: .destructive) { confirmsUninstall = true }
                        .font(.caption)
                }
            } else {
                Button("安装控制组件…") { model.installHelper() }
            }
        }
        .padding(18).kurrenchiSurface()
        .alert("卸载 Kurrenchi Helper？", isPresented: $confirmsUninstall) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) { model.uninstallHelper() }
        } message: {
            Text("将恢复系统默认充电状态并移除后台控制组件。应用与电池历史不会删除。")
        }
    }

    private var statusTitle: String {
        guard model.helperInstalled else { return "硬件控制组件尚未安装" }
        switch model.hardwareStatus?.backend {
        case .directSMC: return "直接 SMC 充电控制"
        case .adapterFallback: return "适配器控制兼容模式"
        case .nativeLimit: return "macOS 原生充电上限"
        case .unavailable: return "当前固件不支持硬件控制"
        case .unknown, .none: return "正在检测硬件能力"
        }
    }

    private var statusDetail: String {
        if let error = model.hardwareStatus?.lastError { return error }
        switch model.hardwareStatus?.backend {
        case .directSMC:
            return "达到上限后停止充电并保持适配器供电；支持睡眠前写入限制。"
        case .adapterFallback:
            return "macOS 27 已限制直接充电键。达到上限后会切断适配器输入并由电池供电；关机后无法维持。"
        default:
            return "80–100% 可使用系统原生上限；20–79% 需 Helper，并会根据固件能力自动降级。"
        }
    }
}

private struct BatteryRing: View {
    let percentage: Int
    let charging: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.075), lineWidth: 10)
            Circle().trim(from: 0, to: CGFloat(max(0, min(100, percentage))) / 100)
                .stroke(AngularGradient(colors: [KurrenchiTheme.amber, KurrenchiTheme.mint, KurrenchiTheme.cyan, KurrenchiTheme.amber], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: KurrenchiTheme.amber.opacity(0.25), radius: 7)
            VStack(spacing: 0) {
                Text("\(percentage)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                Text("%").font(.caption2).foregroundStyle(.secondary)
            }
            if charging { Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.yellow).offset(y: 30) }
        }
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.caption).foregroundStyle(KurrenchiTheme.amber)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Capsule().fill(tint.opacity(0.55)).frame(width: 22, height: 4)
            }
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.62)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(15)
        .kurrenchiSurface(radius: 17)
    }
}

private enum ChartMetric: String, CaseIterable, Identifiable {
    case level = "电量"
    case power = "功耗"
    case temperature = "温度"
    var id: Self { self }
}

private struct HistoryChart: View {
    let samples: [BatterySample]
    let metric: ChartMetric
    var body: some View {
        Chart(samples) { sample in
            LineMark(x: .value("时间", sample.date), y: .value(metric.rawValue, value(sample)))
                .interpolationMethod(.catmullRom).foregroundStyle(KurrenchiTheme.amber)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            AreaMark(x: .value("时间", sample.date), y: .value(metric.rawValue, value(sample)))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [KurrenchiTheme.amber.opacity(0.24), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
    }
    private func value(_ sample: BatterySample) -> Double {
        switch metric {
        case .level: sample.percentage
        case .power: sample.powerWatts
        case .temperature: sample.temperature ?? 0
        }
    }
}

private struct MiniBatteryChart: View {
    let samples: [BatterySample]
    var body: some View {
        Chart(samples) { sample in
            LineMark(x: .value("时间", sample.date), y: .value("电量", sample.percentage))
                .interpolationMethod(.catmullRom).foregroundStyle(KurrenchiTheme.amber)
            AreaMark(x: .value("时间", sample.date), y: .value("电量", sample.percentage))
                .foregroundStyle(KurrenchiTheme.amber.opacity(0.12))
        }.chartXAxis(.hidden).chartYAxis(.hidden)
    }
}

private struct CalibrationSteps: View {
    let active: CalibrationPhase
    private let phases: [CalibrationPhase] = [.chargingToFull, .holdingFull, .discharging, .recharging]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(phases, id: \.self) { phase in Capsule().fill(color(for: phase)).frame(height: 5) }
        }
    }
    private func color(for phase: CalibrationPhase) -> Color {
        guard let activeIndex = phases.firstIndex(of: active), let index = phases.firstIndex(of: phase) else {
            return .secondary.opacity(0.2)
        }
        return index <= activeIndex ? pilotGreen : .secondary.opacity(0.2)
    }
}

private func openChargingSettings() {
    let candidates = [
        "x-apple.systempreferences:com.apple.Battery-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.battery"
    ]
    for value in candidates {
        if let url = URL(string: value), NSWorkspace.shared.open(url) { return }
    }
}
