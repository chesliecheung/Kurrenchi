import SwiftUI

@main
struct KurrenchiApp: App {
    @StateObject private var model = BatteryModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: MenuBarIconRenderer.image(
                    percentage: model.snapshot.percentage,
                    charging: model.snapshot.isCharging,
                    paused: model.chargeState == .holding || model.chargeState == .sailing
                ))
                if model.settings.showPercentage {
                    Text(model.menuBarText).monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Kurrenchi", id: "dashboard") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--preview-dashboard") ? .presented : .suppressed)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 580, height: 540)
        }
    }
}
