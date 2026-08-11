import Foundation

public struct QuotaPreferences: Codable, Sendable, Equatable {
    public static let maxMenuBarPins = 3

    public var warnThreshold: Double
    public var criticalThreshold: Double
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var launchAtLogin: Bool

    public var cursorTrackingEnabled: Bool
    public var codexTrackingEnabled: Bool
    public var claudeTrackingEnabled: Bool
    public var copilotTrackingEnabled: Bool
    public var grokTrackingEnabled: Bool
    public var opencodeTrackingEnabled: Bool
    public var geminiTrackingEnabled: Bool

    public var cursorHidden: Bool
    public var codexHidden: Bool
    public var claudeHidden: Bool
    public var copilotHidden: Bool
    public var grokHidden: Bool
    public var opencodeHidden: Bool
    public var geminiHidden: Bool

    /// Ordered pins shown as text beside the menu bar icon (max `maxMenuBarPins`).
    public var menuBarPins: [MenuBarPin]
    /// Ordered provider IDs used throughout the app UI and menu bar status item.
    public var providerOrder: [ProviderID]

    public static let defaults = QuotaPreferences()

    public init(
        warnThreshold: Double = 0.8,
        criticalThreshold: Double = 0.9,
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        launchAtLogin: Bool = false,
        cursorTrackingEnabled: Bool = false,
        codexTrackingEnabled: Bool = false,
        claudeTrackingEnabled: Bool = false,
        copilotTrackingEnabled: Bool = false,
        grokTrackingEnabled: Bool = false,
        opencodeTrackingEnabled: Bool = false,
        geminiTrackingEnabled: Bool = false,
        cursorHidden: Bool = false,
        codexHidden: Bool = false,
        claudeHidden: Bool = false,
        copilotHidden: Bool = false,
        grokHidden: Bool = false,
        opencodeHidden: Bool = false,
        geminiHidden: Bool = false,
        menuBarPins: [MenuBarPin] = [],
        providerOrder: [ProviderID] = ProviderID.allCases
    ) {
        self.warnThreshold = warnThreshold
        self.criticalThreshold = criticalThreshold
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.launchAtLogin = launchAtLogin
        self.cursorTrackingEnabled = cursorTrackingEnabled
        self.codexTrackingEnabled = codexTrackingEnabled
        self.claudeTrackingEnabled = claudeTrackingEnabled
        self.copilotTrackingEnabled = copilotTrackingEnabled
        self.grokTrackingEnabled = grokTrackingEnabled
        self.opencodeTrackingEnabled = opencodeTrackingEnabled
        self.geminiTrackingEnabled = geminiTrackingEnabled
        self.cursorHidden = cursorHidden
        self.codexHidden = codexHidden
        self.claudeHidden = claudeHidden
        self.copilotHidden = copilotHidden
        self.grokHidden = grokHidden
        self.opencodeHidden = opencodeHidden
        self.geminiHidden = geminiHidden
        self.menuBarPins = Array(menuBarPins.prefix(Self.maxMenuBarPins))
        self.providerOrder = Self.normalizedProviderOrder(providerOrder)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        warnThreshold = try container.decodeIfPresent(Double.self, forKey: .warnThreshold) ?? 0.8
        criticalThreshold = try container.decodeIfPresent(Double.self, forKey: .criticalThreshold) ?? 0.9
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        cursorTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .cursorTrackingEnabled) ?? false
        codexTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .codexTrackingEnabled) ?? false
        claudeTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .claudeTrackingEnabled) ?? false
        copilotTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .copilotTrackingEnabled) ?? false
        grokTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .grokTrackingEnabled) ?? false
        opencodeTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .opencodeTrackingEnabled) ?? false
        geminiTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .geminiTrackingEnabled) ?? false
        cursorHidden = try container.decodeIfPresent(Bool.self, forKey: .cursorHidden) ?? false
        codexHidden = try container.decodeIfPresent(Bool.self, forKey: .codexHidden) ?? false
        claudeHidden = try container.decodeIfPresent(Bool.self, forKey: .claudeHidden) ?? false
        copilotHidden = try container.decodeIfPresent(Bool.self, forKey: .copilotHidden) ?? false
        grokHidden = try container.decodeIfPresent(Bool.self, forKey: .grokHidden) ?? false
        opencodeHidden = try container.decodeIfPresent(Bool.self, forKey: .opencodeHidden) ?? false
        geminiHidden = try container.decodeIfPresent(Bool.self, forKey: .geminiHidden) ?? false
        // Decode pins and order leniently: a retired provider identifier (e.g. a dropped
        // provider) must be dropped silently rather than failing the whole preferences load.
        let storedPins = try container.decodeIfPresent([StoredMenuBarPin].self, forKey: .menuBarPins) ?? []
        menuBarPins = Array(storedPins.compactMap(\.menuBarPin).prefix(Self.maxMenuBarPins))
        let storedOrder = try container.decodeIfPresent([String].self, forKey: .providerOrder) ?? []
        providerOrder = Self.normalizedProviderOrder(storedOrder.compactMap { ProviderID(rawValue: $0) })
    }

    public var thresholds: AlertThresholds {
        AlertThresholds(warn: warnThreshold, critical: criticalThreshold)
    }

    public func isTrackingEnabled(for id: ProviderID) -> Bool {
        switch id {
        case .cursor: cursorTrackingEnabled
        case .codex: codexTrackingEnabled
        case .claude: claudeTrackingEnabled
        case .copilot: copilotTrackingEnabled
        case .grok: grokTrackingEnabled
        case .opencode: opencodeTrackingEnabled
        case .gemini: geminiTrackingEnabled
        }
    }

    public func isHidden(for id: ProviderID) -> Bool {
        switch id {
        case .cursor: cursorHidden
        case .codex: codexHidden
        case .claude: claudeHidden
        case .copilot: copilotHidden
        case .grok: grokHidden
        case .opencode: opencodeHidden
        case .gemini: geminiHidden
        }
    }

    public mutating func setTracking(_ id: ProviderID, enabled: Bool) {
        switch id {
        case .cursor: cursorTrackingEnabled = enabled
        case .codex: codexTrackingEnabled = enabled
        case .claude: claudeTrackingEnabled = enabled
        case .copilot: copilotTrackingEnabled = enabled
        case .grok: grokTrackingEnabled = enabled
        case .opencode: opencodeTrackingEnabled = enabled
        case .gemini: geminiTrackingEnabled = enabled
        }
    }

    public mutating func setHidden(_ id: ProviderID, hidden: Bool) {
        switch id {
        case .cursor: cursorHidden = hidden
        case .codex: codexHidden = hidden
        case .claude: claudeHidden = hidden
        case .copilot: copilotHidden = hidden
        case .grok: grokHidden = hidden
        case .opencode: opencodeHidden = hidden
        case .gemini: geminiHidden = hidden
        }
    }

    public func isMenuBarPinned(_ pin: MenuBarPin) -> Bool {
        menuBarPins.contains(pin)
    }

    /// Pins grouped in the same order as their providers appear in the app.
    public var orderedMenuBarPins: [MenuBarPin] {
        providerOrder.flatMap { providerID in
            menuBarPins.filter { $0.providerID == providerID }
        }
    }

    /// Updates the provider order while retaining every known provider exactly once.
    public mutating func setProviderOrder(_ providerOrder: [ProviderID]) {
        self.providerOrder = Self.normalizedProviderOrder(providerOrder)
    }

    /// Moves a provider to an explicit position in the persisted display order.
    @discardableResult
    public mutating func moveProvider(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard providerOrder.indices.contains(sourceIndex),
              providerOrder.indices.contains(destinationIndex),
              sourceIndex != destinationIndex
        else { return false }
        let providerID = providerOrder.remove(at: sourceIndex)
        providerOrder.insert(providerID, at: destinationIndex)
        return true
    }

    /// Enables or disables a pin. Enabling is a no-op when already at `maxMenuBarPins`.
    @discardableResult
    public mutating func setMenuBarPin(_ pin: MenuBarPin, enabled: Bool) -> Bool {
        if enabled {
            guard !menuBarPins.contains(pin) else { return true }
            guard menuBarPins.count < Self.maxMenuBarPins else { return false }
            menuBarPins.append(pin)
            return true
        }
        menuBarPins.removeAll { $0 == pin }
        return true
    }

    public var visibleProviderIDs: [ProviderID] {
        providerOrder.filter { !isHidden(for: $0) }
    }

    private static func normalizedProviderOrder(_ providerOrder: [ProviderID]) -> [ProviderID] {
        let unique = providerOrder.reduce(into: [ProviderID]()) { result, providerID in
            if !result.contains(providerID) {
                result.append(providerID)
            }
        }
        return unique + ProviderID.allCases.filter { !unique.contains($0) }
    }
}

private struct StoredMenuBarPin: Decodable {
    var providerID: String
    var windowKind: UsageWindowKind

    var menuBarPin: MenuBarPin? {
        guard let providerID = ProviderID(rawValue: providerID) else { return nil }
        return MenuBarPin(providerID: providerID, windowKind: windowKind)
    }
}
