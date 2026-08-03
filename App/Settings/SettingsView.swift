import QuotaCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var session: AppSession
    @State private var statusMessage: String?
    @State private var connecting: Set<ProviderID> = []

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(ProviderID.allCases) { id in
                    providerBlock(id)
                }
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
                    "Quota is local-only. Cursor → Cursor app, ChatGPT → ~/.codex/auth.json, Copilot → `gh` CLI. Tokens are not copied into the macOS Keychain. Brand marks are for identification in this open-source tool."
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
        .frame(minWidth: 460, minHeight: 560)
    }

    @ViewBuilder
    private func providerBlock(_ id: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(id.assetIconName)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 20, height: 20)
                Text(id.displayName)
                    .font(.headline)
                Spacer()
                Text(authLabel(for: id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(blurb(for: id))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle(
                "Show in menu bar",
                isOn: Binding(
                    get: { !session.preferences.isHidden(for: id) },
                    set: { visible in
                        Task { await session.setProviderHidden(id, hidden: !visible) }
                    }
                )
            )

            HStack {
                Button {
                    connect(id)
                } label: {
                    Text(connecting.contains(id) ? "Connecting…" : "Enable / Connect")
                }
                .buttonStyle(.borderedProminent)
                .disabled(connecting.contains(id))

                Button("Disable", role: .destructive) {
                    Task {
                        try? await session.clearAuth(id)
                        statusMessage = "\(id.displayName) disabled"
                    }
                }
                .buttonStyle(.bordered)
                .disabled(connecting.contains(id))
            }

            if let healthError = session.lastErrors[id] {
                Text(healthError)
                    .font(.caption2)
                    .foregroundStyle(QuotaTheme.critical)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func blurb(for id: ProviderID) -> String {
        switch id {
        case .cursor:
            "Reads your signed-in Cursor desktop session (Auto + API pools)."
        case .codex:
            "Reads ~/.codex/auth.json from Codex CLI (`codex login`)."
        case .copilot:
            "Reads Copilot credits via GitHub CLI (`gh auth login`)."
        }
    }

    private func connect(_ id: ProviderID) {
        connecting.insert(id)
        statusMessage = "Connecting \(id.displayName)…"
        Task {
            defer { connecting.remove(id) }
            do {
                try await session.authenticateFromLocalApp(id)
                if let error = session.lastErrors[id] {
                    statusMessage = "Connected, but usage fetch failed: \(error)"
                } else if let snap = session.snapshots[id] {
                    let parts = snap.windows.map { "\(shortLabel(for: $0.kind)) \(Int($0.utilization * 100))%" }
                    statusMessage = "\(id.displayName): " + parts.joined(separator: " · ")
                } else {
                    statusMessage = "\(id.displayName) connected"
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func shortLabel(for kind: UsageWindowKind) -> String {
        switch kind {
        case .cursorAuto: "Models"
        case .cursorAPI: "API"
        case .fiveHour: "5h"
        case .weekly: "Week"
        case .monthly: "Month"
        case .copilotCredits: "Credits"
        case .custom: "Usage"
        }
    }

    private func authLabel(for id: ProviderID) -> String {
        if !session.preferences.isTrackingEnabled(for: id) {
            return "Disabled"
        }
        switch session.authStatuses[id] ?? .signedOut {
        case .signedOut: return "Signed out"
        case .signedIn(let hint): return hint ?? "Signed in"
        case .expired: return "Expired"
        case .invalid: return "Invalid"
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
