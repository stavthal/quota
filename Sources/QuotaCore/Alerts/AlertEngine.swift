import Foundation

public enum AlertSeverity: String, Codable, Sendable, Comparable {
    case ok
    case warn
    case critical

    private var rank: Int {
        switch self {
        case .ok: 0
        case .warn: 1
        case .critical: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct AlertThresholds: Codable, Sendable, Equatable {
    public var warn: Double
    public var critical: Double

    public static let defaults = AlertThresholds(warn: 0.8, critical: 0.9)

    public init(warn: Double = 0.8, critical: Double = 0.9) {
        self.warn = warn
        self.critical = critical
    }
}

public struct AlertEvent: Sendable, Equatable {
    public var providerID: ProviderID
    public var windowKind: UsageWindowKind
    public var severity: AlertSeverity
    public var utilization: Double

    public init(
        providerID: ProviderID,
        windowKind: UsageWindowKind,
        severity: AlertSeverity,
        utilization: Double
    ) {
        self.providerID = providerID
        self.windowKind = windowKind
        self.severity = severity
        self.utilization = utilization
    }
}

public struct AlertCooldownKey: Hashable, Codable, Sendable {
    public var providerID: ProviderID
    public var windowKind: UsageWindowKind
    public var severity: AlertSeverity
    public var windowResetsAt: Date

    public init(
        providerID: ProviderID,
        windowKind: UsageWindowKind,
        severity: AlertSeverity,
        windowResetsAt: Date
    ) {
        self.providerID = providerID
        self.windowKind = windowKind
        self.severity = severity
        self.windowResetsAt = windowResetsAt
    }
}

public struct AlertCooldownState: Codable, Sendable, Equatable {
    public var fired: Set<AlertCooldownKey>

    public init(fired: Set<AlertCooldownKey> = []) {
        self.fired = fired
    }
}

public struct AlertEngine: Sendable {
    public init() {}

    public func evaluate(
        snapshots: [UsageSnapshot],
        thresholds: AlertThresholds,
        cooldown: inout AlertCooldownState,
        now: Date = Date()
    ) -> (severity: AlertSeverity, events: [AlertEvent]) {
        var worst: AlertSeverity = .ok
        var events: [AlertEvent] = []

        for snap in snapshots {
            for window in snap.windows {
                let utilization = window.utilization
                let level: AlertSeverity
                if utilization >= thresholds.critical {
                    level = .critical
                } else if utilization >= thresholds.warn {
                    level = .warn
                } else {
                    level = .ok
                }

                if level > worst {
                    worst = level
                }

                guard level > .ok else { continue }

                let key = AlertCooldownKey(
                    providerID: snap.providerID,
                    windowKind: window.kind,
                    severity: level,
                    windowResetsAt: window.resetsAt
                )

                cooldown.fired = Set(
                    cooldown.fired.filter { existing in
                        !(existing.providerID == key.providerID
                            && existing.windowKind == key.windowKind
                            && existing.severity == key.severity
                            && existing.windowResetsAt < key.windowResetsAt)
                    }
                )

                if !cooldown.fired.contains(key) {
                    cooldown.fired.insert(key)
                    events.append(
                        AlertEvent(
                            providerID: snap.providerID,
                            windowKind: window.kind,
                            severity: level,
                            utilization: utilization
                        )
                    )
                }
            }
        }

        _ = now
        return (worst, events)
    }
}
