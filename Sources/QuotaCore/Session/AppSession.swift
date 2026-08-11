import Foundation

@MainActor
public final class AppSession: ObservableObject {
    @Published public private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    @Published public private(set) var aggregateSeverity: AlertSeverity = .ok
    @Published public private(set) var lastErrors: [ProviderID: String] = [:]
    @Published public private(set) var pendingAlertEvents: [AlertEvent] = []
    @Published public private(set) var preferences: QuotaPreferences
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var authStatuses: [ProviderID: AuthStatus] = [:]
    /// Top backends used inside OpenCode (max 3), shown as separate popover cards.
    @Published public private(set) var openCodeBackends: [OpenCodeBackendUsage] = []
    @Published public private(set) var openCodeSubscriptionLabel: String = "OpenCode"

    private let providers: [any Provider]
    private let usageStore: UsageStore
    private let secretsStore: any SecretsStore
    private let alertEngine: AlertEngine
    private let scheduler: RefreshScheduler
    private var cooldown: AlertCooldownState

    public init(
        providers: [any Provider],
        usageStore: UsageStore,
        secretsStore: any SecretsStore,
        alertEngine: AlertEngine = AlertEngine(),
        scheduler: RefreshScheduler = RefreshScheduler(),
        preferences: QuotaPreferences = .defaults
    ) {
        self.providers = providers
        self.usageStore = usageStore
        self.secretsStore = secretsStore
        self.alertEngine = alertEngine
        self.scheduler = scheduler
        self.preferences = preferences
        self.cooldown = AlertCooldownState()
    }

    public static func makeDefault() async throws -> AppSession {
        let store = try UsageStore.onDisk(url: Self.defaultDatabaseURL())
        // Wipe legacy provider Keychain copies that caused infinite ACL prompts.
        let secrets = KeychainSecretsStore()
        try? await secrets.delete(.cursor)
        try? await secrets.delete(.codex)

        let preferences = (try? await store.loadPreferences()) ?? .defaults
        let providers: [any Provider] = [
            CursorProvider(trackingEnabled: preferences.cursorTrackingEnabled),
            CodexProvider(trackingEnabled: preferences.codexTrackingEnabled),
            ClaudeProvider(trackingEnabled: preferences.claudeTrackingEnabled),
            CopilotProvider(trackingEnabled: preferences.copilotTrackingEnabled),
            GrokProvider(trackingEnabled: preferences.grokTrackingEnabled),
            OpenCodeProvider(trackingEnabled: preferences.opencodeTrackingEnabled),
            GeminiProvider(trackingEnabled: preferences.geminiTrackingEnabled),
        ]

        let session = AppSession(
            providers: providers,
            usageStore: store,
            secretsStore: secrets,
            preferences: preferences
        )
        session.cooldown = (try? await store.loadCooldown()) ?? AlertCooldownState()
        return session
    }

    public static func defaultDatabaseURL() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Quota", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage.sqlite")
    }

    public func start() {
        Task {
            await refreshAuthStatuses()
            await refreshAll()
            await scheduler.start { [weak self] in
                await self?.refreshAll()
            }
        }
    }

    public func stop() {
        Task { await scheduler.stop() }
    }

    public func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        for provider in providers {
            do {
                let status = await provider.authStatus()
                authStatuses[provider.id] = status
                guard case .signedIn = status else {
                    snapshots[provider.id] = nil
                    if provider.id == .opencode {
                        openCodeBackends = []
                        openCodeSubscriptionLabel = "OpenCode"
                    }
                    continue
                }

                if let openCode = provider as? OpenCodeProvider {
                    let result = try await openCode.fetchSnapshotAndBackends()
                    try await usageStore.save(result.snapshot)
                    snapshots[.opencode] = result.snapshot
                    openCodeBackends = result.backends
                    openCodeSubscriptionLabel = result.label
                    authStatuses[.opencode] = .signedIn(accountHint: result.label)
                    lastErrors.removeValue(forKey: .opencode)
                } else {
                    let snap = try await provider.fetchSnapshot()
                    try await usageStore.save(snap)
                    snapshots[provider.id] = snap
                    lastErrors.removeValue(forKey: provider.id)
                }
            } catch {
                lastErrors[provider.id] = error.localizedDescription
                if provider.id == .opencode {
                    openCodeBackends = []
                }
            }
        }

        let ordered = ProviderID.allCases.compactMap { snapshots[$0] }
        let result = alertEngine.evaluate(
            snapshots: ordered,
            thresholds: preferences.thresholds,
            cooldown: &cooldown
        )
        aggregateSeverity = result.severity
        pendingAlertEvents = result.events
        try? await usageStore.saveCooldown(cooldown)
    }

    public func consumeAlertEvents() -> [AlertEvent] {
        let events = pendingAlertEvents
        pendingAlertEvents = []
        return events
    }

    public func authenticate(_ providerID: ProviderID, token: String) async throws {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        try await provider.authenticate(using: .sessionToken(token))
        await setProviderTracking(providerID, enabled: true)
        await refreshAuthStatuses()
        await refreshAll()
    }

    public func authenticateFromLocalApp(_ providerID: ProviderID) async throws {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        try await provider.authenticate(using: .localApp)
        await setProviderTracking(providerID, enabled: true)
        await refreshAuthStatuses()
        await refreshAll()
    }

    public func clearAuth(_ providerID: ProviderID) async throws {
        guard let provider = providers.first(where: { $0.id == providerID }) else { return }
        try await provider.clearAuth()
        await setProviderTracking(providerID, enabled: false)
        snapshots[providerID] = nil
        lastErrors.removeValue(forKey: providerID)
        if providerID == .opencode {
            openCodeBackends = []
            openCodeSubscriptionLabel = "OpenCode"
        }
        await refreshAuthStatuses()
        await refreshAll()
    }

    public func updatePreferences(_ preferences: QuotaPreferences) async {
        self.preferences = preferences
        try? await usageStore.savePreferences(preferences)
    }

    public func setProviderTracking(_ providerID: ProviderID, enabled: Bool) async {
        preferences.setTracking(providerID, enabled: enabled)
        try? await usageStore.savePreferences(preferences)
    }

    public func setProviderHidden(_ providerID: ProviderID, hidden: Bool) async {
        preferences.setHidden(providerID, hidden: hidden)
        try? await usageStore.savePreferences(preferences)
    }

    private func refreshAuthStatuses() async {
        for provider in providers {
            authStatuses[provider.id] = await provider.authStatus()
        }
    }
}
