import Foundation

public struct QuotaPreferences: Codable, Sendable, Equatable {
    public var warnThreshold: Double
    public var criticalThreshold: Double
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var launchAtLogin: Bool

    public static let defaults = QuotaPreferences(
        warnThreshold: 0.8,
        criticalThreshold: 0.9,
        notificationsEnabled: true,
        soundEnabled: true,
        launchAtLogin: false
    )

    public init(
        warnThreshold: Double = 0.8,
        criticalThreshold: Double = 0.9,
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.warnThreshold = warnThreshold
        self.criticalThreshold = criticalThreshold
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.launchAtLogin = launchAtLogin
    }

    public var thresholds: AlertThresholds {
        AlertThresholds(warn: warnThreshold, critical: criticalThreshold)
    }
}
