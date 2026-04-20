import SwiftUI

@main
struct UnraidMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = Settings.shared
    @StateObject private var push = PushRegistrar.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(push)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        NavigationStack {
            if settings.isConfigured {
                DashboardView()
            } else {
                SettingsView(firstRun: true)
            }
        }
    }
}
