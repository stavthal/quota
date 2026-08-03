import QuotaCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: AppSession

    @State private var statusMessage: String?
    @State private var isConnectingCursor = false
    @State private var isConnectingCodex = false

    var body: some View {
        Form {
            Section("Providers") {
                cursorRow
                codexRow
            }

            Section("Alerts") {
                Toggle("Notifications", isOn: binding(\.notificationsEnabled))
                Toggle("Sound", isOn: binding(\.soundEnabled))
                VStack(alignment: .leading) {
                    Text("Warn at \(Int(session.preferences.warnThreshold * 100))%")
                    Slider(value: binding(\.warnThreshold), in: 0.5...0.95, step: 0.01)
                }
                VStack(alignment: .leading) {
                    Text("Critical at \(Int(session.preferences.criticalThreshold * 100))%")
                    Slider(value: binding(\.criticalThreshold), in: 0.55...0.99, step: 0.01)
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
            }

            Section("About") {
                Text(
                    "Quota is local-only. Cursor reads the Cursor app login; Codex reads ~/.codex/auth.json. Tokens are not copied into the macOS Keychain."
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
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 520)
    }

    private var cursorRow: some View {
        providerRow(
            title: "Cursor",
            providerID: .cursor,
            blurb: "Reads your signed-in Cursor desktop session (Auto + API pools).",
            connecting: isConnectingCursor,
            connectTitle: "Connect Cursor app",
            onConnect: connectCursor
        )
    }

    private var codexRow: some View {
        providerRow(
            title: "Codex",
            providerID: .codex,
            blurb: "Reads ~/.codex/auth.json from Codex CLI (`codex login`).",
            connecting: isConnectingCodex,
            connectTitle: "Connect Codex CLI",
            onConnect: connectCodex
        )
    }

    private func providerRow(
        title: String,
        providerID: ProviderID,
        blurb: String,
        connecting: Bool,
        connectTitle: String,
        onConnect: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(authLabel(for: providerID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(blurb)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    onConnect()
                } label: {
                    Text(connecting ? "Connecting…" : connectTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(connecting)

                Button("Disconnect", role: .destructive) {
                    Task {
                        try? await session.clearAuth(providerID)
                        statusMessage = "\(title) disconnected"
                    }
                }
                .buttonStyle(.bordered)
                .disabled(connecting)
            }
            if let healthError = session.lastErrors[providerID] {
                Text(healthError)
                    .font(.caption2)
                    .foregroundStyle(QuotaTheme.critical)
                    .textSelection(.enabled)
            }
        }
    }

    private func connectCursor() {
        isConnectingCursor = true
        statusMessage = "Reading Cursor app session…"
        Task {
            defer { isConnectingCursor = false }
            do {
                try await session.authenticateFromLocalApp(.cursor)
                statusMessage = connectedMessage(for: .cursor, title: "Cursor")
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func connectCodex() {
        isConnectingCodex = true
        statusMessage = "Reading ~/.codex/auth.json…"
        Task {
            defer { isConnectingCodex = false }
            do {
                try await session.authenticateFromLocalApp(.codex)
                statusMessage = connectedMessage(for: .codex, title: "Codex")
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func connectedMessage(for id: ProviderID, title: String) -> String {
        if let error = session.lastErrors[id] {
            return "Connected, but usage fetch failed: \(error)"
        }
        if let snap = session.snapshots[id] {
            let parts = snap.windows.map { "\(label(for: $0.kind)) \(Int($0.utilization * 100))%" }
            return "Connected. " + parts.joined(separator: " · ")
        }
        return "\(title) connected"
    }

    private func label(for kind: UsageWindowKind) -> String {
        switch kind {
        case .cursorAuto: "Cursor models"
        case .cursorAPI: "API models"
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .custom: "Custom"
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
