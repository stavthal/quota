import Foundation

public struct QuotaPreferences: Codable, Sendable, Equatable {
    public var warnThreshold: Double
    public var criticalThreshold: Double
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var launchAtLogin: Bool

    public var cursorTrackingEnabled: Bool
    public var codexTrackingEnabled: Bool
    public var copilotTrackingEnabled: Bool

    public var cursorHidden: Bool
    public var codexHidden: Bool
    public var copilotHidden: Bool

    public static let defaults = QuotaPreferences()

    public init(
        warnThreshold: Double = 0.8,
        criticalThreshold: Double = 0.9,
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        launchAtLogin: Bool = false,
        cursorTrackingEnabled: Bool = false,
        codexTrackingEnabled: Bool = false,
        copilotTrackingEnabled: Bool = false,
        cursorHidden: Bool = false,
        codexHidden: Bool = false,
        copilotHidden: Bool = false
    ) {
        self.warnThreshold = warnThreshold
        self.criticalThreshold = criticalThreshold
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.launchAtLogin = launchAtLogin
        self.cursorTrackingEnabled = cursorTrackingEnabled
        self.codexTrackingEnabled = codexTrackingEnabled
        self.copilotTrackingEnabled = copilotTrackingEnabled
        self.cursorHidden = cursorHidden
        self.codexHidden = codexHidden
        self.copilotHidden = copilotHidden
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
        copilotTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .copilotTrackingEnabled) ?? false
        cursorHidden = try container.decodeIfPresent(Bool.self, forKey: .cursorHidden) ?? false
        codexHidden = try container.decodeIfPresent(Bool.self, forKey: .codexHidden) ?? false
        copilotHidden = try container.decodeIfPresent(Bool.self, forKey: .copilotHidden) ?? false
    }

    public var thresholds: AlertThresholds {
        AlertThresholds(warn: warnThreshold, critical: criticalThreshold)
    }

    public func isTrackingEnabled(for id: ProviderID) -> Bool {
        switch id {
        case .cursor: cursorTrackingEnabled
        case .codex: codexTrackingEnabled
        case .copilot: copilotTrackingEnabled
        }
    }

    public func isHidden(for id: ProviderID) -> Bool {
        switch id {
        case .cursor: cursorHidden
        case .codex: codexHidden
        case .copilot: copilotHidden
        }
    }

    public mutating func setTracking(_ id: ProviderID, enabled: Bool) {
        switch id {
        case .cursor: cursorTrackingEnabled = enabled
        case .codex: codexTrackingEnabled = enabled
        case .copilot: copilotTrackingEnabled = enabled
        }
    }

    public mutating func setHidden(_ id: ProviderID, hidden: Bool) {
        switch id {
        case .cursor: cursorHidden = hidden
        case .codex: codexHidden = hidden
        case .copilot: copilotHidden = hidden
        }
    }

    public var visibleProviderIDs: [ProviderID] {
        ProviderID.allCases.filter { !isHidden(for: $0) }
    }
}
