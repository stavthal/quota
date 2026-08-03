import QuotaCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var cursorToken = ""
    @State private var codexToken = ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Providers") {
                providerBindRow(
                    title: "Cursor",
                    providerID: .cursor,
                    token: $cursorToken
                )
                providerBindRow(
                    title: "Codex",
                    providerID: .codex,
                    token: $codexToken
                )
            }

            Section("Alerts") {
                Toggle(
                    "Notifications",
                    isOn: binding(\.notificationsEnabled)
                )
                Toggle(
                    "Sound",
                    isOn: binding(\.soundEnabled)
                )
                VStack(alignment: .leading) {
                    Text("Warn at \(Int(session.preferences.warnThreshold * 100))%")
                    Slider(
                        value: binding(\.warnThreshold),
                        in: 0.5...0.95,
                        step: 0.01
                    )
                }
                VStack(alignment: .leading) {
                    Text("Critical at \(Int(session.preferences.criticalThreshold * 100))%")
                    Slider(
                        value: binding(\.criticalThreshold),
                        in: 0.55...0.99,
                        step: 0.01
                    )
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
            }

            Section("About") {
                Text(
                    "Quota is local-only. Future live providers may use unofficial APIs that can break when vendors change backends. Credentials stay on this Mac except when talking to the vendor you bind."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Version \(QuotaCoreModule.version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(QuotaTheme.accent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420, height: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func providerBindRow(
        title: String,
        providerID: ProviderID,
        token: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(authLabel(for: providerID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecureField("Session token (mock accepts any)", text: token)
            HStack {
                Button("Bind") {
                    Task {
                        do {
                            try await session.authenticate(providerID, token: token.wrappedValue)
                            token.wrappedValue = ""
                            statusMessage = "\(title) bound"
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(token.wrappedValue.isEmpty)

                Button("Sign out", role: .destructive) {
                    Task {
                        try? await session.clearAuth(providerID)
                        statusMessage = "\(title) signed out"
                    }
                }
            }
            if let healthError = session.lastErrors[providerID] {
                Text(healthError)
                    .font(.caption2)
                    .foregroundStyle(QuotaTheme.critical)
            }
        }
    }

    private func authLabel(for id: ProviderID) -> String {
        switch session.authStatuses[id] ?? .signedOut {
        case .signedOut: "Signed out"
        case .signedIn(let hint): hint ?? "Signed in"
        case .expired: "Expired"
        case .invalid: "Invalid"
        }
    }

    private func binding(_ keyPath: WritableKeyPath<QuotaPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { session.preferences[keyPath: keyPath] },
            set: { newValue in
                var prefs = session.preferences
                prefs[keyPath: keyPath] = newValue
                Task { await session.updatePreferences(prefs) }
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<QuotaPreferences, Double>) -> Binding<Double> {
        Binding(
            get: { session.preferences[keyPath: keyPath] },
            set: { newValue in
                var prefs = session.preferences
                prefs[keyPath: keyPath] = newValue
                Task { await session.updatePreferences(prefs) }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { session.preferences.launchAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    var prefs = session.preferences
                    prefs.launchAtLogin = enabled
                    Task { await session.updatePreferences(prefs) }
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
        )
    }
}
