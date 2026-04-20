import SwiftUI
import UserNotifications

struct SettingsView: View {
    let firstRun: Bool

    @EnvironmentObject var settings: Settings
    @EnvironmentObject var push: PushRegistrar
    @Environment(\.dismiss) private var dismiss

    @State private var urlDraft: String = ""
    @State private var tokenDraft: String = ""
    @State private var cfIdDraft: String = ""
    @State private var cfSecretDraft: String = ""
    @State private var testing = false
    @State private var testResult: TestResult?

    enum TestResult {
        case ok(String)
        case fail(String)
    }

    var body: some View {
        Form {
            Section("Backend") {
                TextField("https://unraid.example.pl", text: $urlDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                SecureField("API token", text: $tokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                TextField("CF-Access-Client-Id", text: $cfIdDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                SecureField("CF-Access-Client-Secret", text: $cfSecretDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
            } header: {
                Text("Cloudflare Access (optional)")
            } footer: {
                Text("Required if your backend sits behind Cloudflare Zero Trust with a service-token policy.")
            }

            Section {
                Button(action: save) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
                .disabled(urlDraft.isEmpty || tokenDraft.isEmpty)

                Button(action: { Task { await test() } }) {
                    HStack {
                        if testing { ProgressView() }
                        Text(testing ? "Testing…" : "Test connection")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(testing || urlDraft.isEmpty || tokenDraft.isEmpty)
            }

            if let result = testResult {
                Section {
                    switch result {
                    case .ok(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .fail(let msg):
                        Label(msg, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
            }

            Section("Notifications") {
                HStack {
                    Text("Permission")
                    Spacer()
                    Text(permissionLabel).foregroundStyle(.secondary)
                }
                Button {
                    Task { await push.requestAuthorizationAndRegister() }
                } label: {
                    Text(push.permission == .authorized ? "Re-register device" : "Enable push")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!settings.isConfigured)
                if let token = push.lastRegisteredToken {
                    Text("Token: \(token.prefix(8))…\(token.suffix(4))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let err = push.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(firstRun ? "Setup" : "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            urlDraft = settings.baseURL
            tokenDraft = settings.token
            cfIdDraft = settings.cfAccessClientId
            cfSecretDraft = settings.cfAccessClientSecret
        }
    }

    private var permissionLabel: String {
        switch push.permission {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
    }

    private func save() {
        settings.baseURL = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.cfAccessClientId = cfIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.cfAccessClientSecret = cfSecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firstRun { dismiss() }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let api = APIClient()
        let url = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfId = cfIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfSec = cfSecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        var headers = ["Authorization": "Bearer \(tok)"]
        if !cfId.isEmpty && !cfSec.isEmpty {
            headers["CF-Access-Client-Id"] = cfId
            headers["CF-Access-Client-Secret"] = cfSec
        }
        do {
            let ping = try await api.pingWith(baseURL: url, headers: headers)
            testResult = .ok("Connected. Server time: \(ping.ts)")
        } catch {
            let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
            testResult = .fail(msg)
        }
    }
}
