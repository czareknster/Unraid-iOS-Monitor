import Foundation
import UIKit
import UserNotifications

/// Singleton that owns push-notification lifecycle:
/// 1. Ask user permission (once), 2. register with APNs, 3. POST token to backend.
@MainActor
final class PushRegistrar: NSObject, ObservableObject {
    static let shared = PushRegistrar()

    @Published private(set) var permission: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastRegisteredToken: String?
    @Published private(set) var lastError: String?

    private let api = APIClient()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshPermission() }
    }

    func refreshPermission() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        self.permission = s.authorizationStatus
    }

    /// Request permission and, if granted, trigger APNs registration.
    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermission()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.lastRegisteredToken = hex
        Task { await self.postToBackend(token: hex) }
    }

    func didFailToRegister(error: Error) {
        self.lastError = error.localizedDescription
    }

    private func postToBackend(token: String) async {
        let settings = Settings.shared
        guard settings.isConfigured else { return }

        let env: String = {
            #if DEBUG
            return "sandbox"
            #else
            return "production"
            #endif
        }()

        let body: [String: Any] = [
            "deviceToken": token,
            "environment": env,
            "name": UIDevice.current.name,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        ]

        guard let baseURL = URL(string: settings.baseURL),
              let url = URL(string: "/api/devices", relativeTo: baseURL) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in settings.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                self.lastError = "Device registration failed: HTTP \(http.statusCode)"
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}

extension PushRegistrar: UNUserNotificationCenterDelegate {
    // Show banner + play sound even when app is foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
