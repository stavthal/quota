import QuotaCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: AppSession

    @State private var codexToken = ""
    @State private var statusMessage: String?
    @State private var isConnectingCursor = false

    var body: some View {
        Form {
            Section("Providers") {
                cursorRow
                codexRow
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
                    "Quota is local-only. Cursor usage is read from the Cursor app login on this Mac and Cursor’s unofficial usage API. Credentials stay on this Mac except when talking to Cursor."
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
                        .foregroundStyle(statusMessageColor)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 520)
    }

    private var statusMessageColor: Color {
        if statusMessage?.localizedCaseInsensitiveContains("fail") == true
            || statusMessage?.localizedCaseInsensitiveContains("error") == true
            || statusMessage?.localizedCaseInsensitiveContains("could") == true
        {
            return QuotaTheme.critical
        }
        return QuotaTheme.accent
    }

    private var cursorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cursor")
                Spacer()
                Text(authLabel(for: .cursor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Uses your signed-in Cursor desktop session (Auto + API pools).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    connectCursor()
                } label: {
                    if isConnectingCursor {
                        Text("Connecting…")
                    } else {
                        Text("Connect Cursor app")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnectingCursor)

                Button("Disconnect", role: .destructive) {
                    Task {
                        try? await session.clearAuth(.cursor)
                        statusMessage = "Cursor disconnected from Quota"
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isConnectingCursor)
            }
            if let healthError = session.lastErrors[.cursor] {
                Text(healthError)
                    .font(.caption2)
                    .foregroundStyle(QuotaTheme.critical)
                    .textSelection(.enabled)
            }
        }
    }

    private var codexRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Codex")
                Spacer()
                Text(authLabel(for: .codex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecureField("Session token (mock for now)", text: $codexToken)
            HStack {
                Button("Bind") {
                    Task {
                        do {
                            try await session.authenticate(.codex, token: codexToken)
                            codexToken = ""
                            statusMessage = "Codex bound"
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(codexToken.isEmpty)

                Button("Sign out", role: .destructive) {
                    Task {
                        try? await session.clearAuth(.codex)
                        statusMessage = "Codex signed out"
                    }
                }
                .buttonStyle(.bordered)
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
                if let error = session.lastErrors[.cursor] {
                    statusMessage = "Connected, but usage fetch failed: \(error)"
                } else if session.snapshots[.cursor] != nil {
                    let auto = session.snapshots[.cursor]?.windows.first { $0.kind == .cursorAuto }
                    let api = session.snapshots[.cursor]?.windows.first { $0.kind == .cursorAPI }
                    statusMessage =
                        "Connected. Cursor models \(Int((auto?.utilization ?? 0) * 100))% · API \(Int((api?.utilization ?? 0) * 100))%"
                } else {
                    statusMessage = "Connected from Cursor app"
                }
            } catch {
                statusMessage = error.localizedDescription
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
