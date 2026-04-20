import Foundation
import Combine

/// Backend connection settings persisted between launches.
/// URL goes to UserDefaults (non-sensitive), token goes to Keychain.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let urlKey = "backend.url"

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: urlKey) }
    }
    @Published var token: String {
        didSet { KeychainStore.set(token, for: .apiToken) }
    }
    @Published var cfAccessClientId: String {
        didSet { KeychainStore.set(cfAccessClientId, for: .cfAccessClientId) }
    }
    @Published var cfAccessClientSecret: String {
        didSet { KeychainStore.set(cfAccessClientSecret, for: .cfAccessClientSecret) }
    }

    var isConfigured: Bool {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else { return false }
        return !token.isEmpty
    }

    /// Headers every authenticated request should carry: our app Bearer plus,
    /// if configured, the Cloudflare Access service-token pair that unlocks
    /// the tunnel before the request ever reaches our backend.
    func authHeaders() -> [String: String] {
        var h = ["Authorization": "Bearer \(token)"]
        if !cfAccessClientId.isEmpty && !cfAccessClientSecret.isEmpty {
            h["CF-Access-Client-Id"] = cfAccessClientId
            h["CF-Access-Client-Secret"] = cfAccessClientSecret
        }
        return h
    }

    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: urlKey) ?? ""
        self.token = KeychainStore.get(.apiToken) ?? ""
        self.cfAccessClientId = KeychainStore.get(.cfAccessClientId) ?? ""
        self.cfAccessClientSecret = KeychainStore.get(.cfAccessClientSecret) ?? ""
    }
}
