import UIKit

/// Minimal AppDelegate used only to receive APNs device token callbacks,
/// which SwiftUI's App lifecycle doesn't expose directly.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistrar.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistrar.shared.didFailToRegister(error: error)
        }
    }
}
