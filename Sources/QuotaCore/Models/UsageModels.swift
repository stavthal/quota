import Foundation

public enum UsageWindowKind: String, Codable, Sendable, Equatable {
    case fiveHour
    case weekly
    case monthly
    case custom
}

public enum UsageUnit: String, Codable, Sendable, Equatable {
    case requests
    case tokens
    case credits
    case percent
}

public struct UsageWindow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kind.rawValue)-\(resetsAt.timeIntervalSince1970)" }
    public var kind: UsageWindowKind
    public var used: Double
    public var limit: Double
    public var unit: UsageUnit
    public var resetsAt: Date

    public init(kind: UsageWindowKind, used: Double, limit: Double, unit: UsageUnit, resetsAt: Date) {
        self.kind = kind
        self.used = used
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
    }

    public var utilization: Double {
        guard limit > 0 else { return 0 }
        return min(max(used / limit, 0), 1)
    }
}

public struct ModelBreakdown: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelID }
    public var modelID: String
    public var label: String
    public var amount: Double
    public var unit: UsageUnit

    public init(modelID: String, label: String, amount: Double, unit: UsageUnit) {
        self.modelID = modelID
        self.label = label
        self.amount = amount
        self.unit = unit
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var providerID: ProviderID
    public var fetchedAt: Date
    public var windows: [UsageWindow]
    public var models: [ModelBreakdown]
    public var diagnostics: Data?

    public init(
        providerID: ProviderID,
        fetchedAt: Date = Date(),
        windows: [UsageWindow],
        models: [ModelBreakdown] = [],
        diagnostics: Data? = nil
    ) {
        self.providerID = providerID
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.models = models
        self.diagnostics = diagnostics
    }
}
