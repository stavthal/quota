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

            statusItemSections

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
                    "Headroom is local-only. Cursor → Cursor app, ChatGPT → ~/.codex/auth.json, Copilot → `gh` CLI, Grok → ~/.grok/auth.json, OpenCode → ~/.local/share/opencode. Tokens are not copied into the macOS Keychain. Brand marks are for identification in this open-source tool. API-key auth for providers is on the roadmap."
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
        .padding(20)
        .frame(minWidth: 480, minHeight: 560)
        .navigationTitle("Headroom Settings")
    }

    @ViewBuilder
    private func providerBlock(_ id: ProviderID) -> some View {
        let tracking = session.preferences.isTrackingEnabled(for: id)
        let auth = session.authStatuses[id] ?? .signedOut
        let connected = tracking && isSignedIn(auth)
        let busy = connecting.contains(id)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderIconView(providerID: id, size: 24)
                Text(id.displayName)
                    .font(.headline)
                Spacer()
                connectionBadge(tracking: tracking, auth: auth)
            }

            if let account = accountHint(auth), tracking {
                Text(account)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(blurb(for: id))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle(
                "Show in popover",
                isOn: Binding(
                    get: { !session.preferences.isHidden(for: id) },
                    set: { visible in
                        Task { await session.setProviderHidden(id, hidden: !visible) }
                    }
                )
            )

            HStack {
                if connected {
                    Button {
                        connect(id)
                    } label: {
                        Text(busy ? "Reconnecting…" : "Reconnect")
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)

                    Button("Disable", role: .destructive) {
                        Task {
                            try? await session.clearAuth(id)
                            statusMessage = "\(id.displayName) disabled"
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                } else {
                    Button {
                        connect(id)
                    } label: {
                        Text(busy ? "Connecting…" : "Enable / Connect")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)

                    if tracking {
                        Button("Disable", role: .destructive) {
                            Task {
                                try? await session.clearAuth(id)
                                statusMessage = "\(id.displayName) disabled"
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                    }
                }
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

    @ViewBuilder
    private var statusItemSections: some View {
        let pinCount = session.preferences.menuBarPins.count
        let atCap = pinCount >= QuotaPreferences.maxMenuBarPins
        let pinnable = ProviderID.allCases.filter { id in
            session.preferences.isTrackingEnabled(for: id)
                && !(session.snapshots[id]?.windows.isEmpty ?? true)
        }

        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu bar preview")
                        .font(.body)
                    Text(menuBarPreviewText)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Text("\(pinCount)/\(QuotaPreferences.maxMenuBarPins)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(atCap ? QuotaTheme.warn : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (atCap ? QuotaTheme.warn : Color.secondary).opacity(0.14),
                        in: Capsule()
                    )
                    .accessibilityLabel("\(pinCount) of \(QuotaPreferences.maxMenuBarPins) pins used")
            }
            .padding(.vertical, 2)
        } header: {
            Text("Status item")
        } footer: {
            Text("Pinned limits show as text beside the Headroom icon — no click needed. Up to \(QuotaPreferences.maxMenuBarPins).")
        }

        if pinnable.isEmpty {
            Section {
                Text("Connect a provider first, then pin its limits here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        } else {
            ForEach(pinnable) { id in
                pinSection(for: id, atCap: atCap)
            }
        }
    }

    private var menuBarPreviewText: String {
        MenuBarStatusFormatter.statusText(
            pins: session.preferences.menuBarPins,
            snapshots: session.snapshots
        ) ?? "Icon only"
    }

    @ViewBuilder
    private func pinSection(for id: ProviderID, atCap: Bool) -> some View {
        let windows = session.snapshots[id]?.windows ?? []

        Section {
            ForEach(windows, id: \.kind) { window in
                pinToggleRow(providerID: id, window: window, atCap: atCap)
            }
        } header: {
            HStack(spacing: 6) {
                ProviderIconView(providerID: id, size: 14)
                Text(id.displayName)
            }
            .textCase(nil)
        }
    }

    private func pinToggleRow(providerID: ProviderID, window: UsageWindow, atCap: Bool) -> some View {
        let pin = MenuBarPin(providerID: providerID, windowKind: window.kind)
        let pinned = session.preferences.isMenuBarPinned(pin)

        return Toggle(isOn: Binding(
            get: { session.preferences.isMenuBarPinned(pin) },
            set: { enabled in
                var prefs = session.preferences
                let ok = prefs.setMenuBarPin(pin, enabled: enabled)
                if ok {
                    Task { await session.updatePreferences(prefs) }
                } else {
                    statusMessage = "Status item is full (\(QuotaPreferences.maxMenuBarPins) pins max). Unpin one first."
                }
            }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(shortLabel(for: window.kind))
                Spacer(minLength: 8)
                Text(MenuBarStatusFormatter.valueLabel(for: window))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!pinned && atCap)
    }

    private func connectionBadge(tracking: Bool, auth: AuthStatus) -> some View {
        let label: String
        let color: Color
        if !tracking {
            label = "Disabled"
            color = .secondary
        } else {
            switch auth {
            case .signedIn:
                label = "Connected"
                color = QuotaTheme.accent
            case .signedOut:
                label = "Signed out"
                color = .secondary
            case .expired:
                label = "Expired"
                color = QuotaTheme.warn
            case .invalid:
                label = "Invalid"
                color = QuotaTheme.critical
            }
        }

        return Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func isSignedIn(_ auth: AuthStatus) -> Bool {
        if case .signedIn = auth { return true }
        return false
    }

    private func accountHint(_ auth: AuthStatus) -> String? {
        if case .signedIn(let hint) = auth { return hint }
        return nil
    }

    private func blurb(for id: ProviderID) -> String {
        switch id {
        case .cursor:
            "Reads your signed-in Cursor desktop session (Auto + API pools)."
        case .codex:
            "Reads ~/.codex/auth.json from Codex CLI (`codex login`)."
        case .copilot:
            "Reads Copilot credits via GitHub CLI (`gh auth login`)."
        case .grok:
            "Reads ~/.grok/auth.json from Grok CLI (`grok login`) — SuperGrok weekly pool."
        case .opencode:
            "Reads ~/.local/share/opencode (auth + local DB). Shows OpenCode Go or Zen, plus up to 3 highest-spend backends used inside OpenCode (e.g. OpenRouter). Go caps $12/5h · $30/wk · $60/mo."
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
        case .custom: "On-demand"
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
