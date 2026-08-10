import Foundation

public struct GeminiQuotaBucket: Sendable, Equatable {
    public var bucketID: String
    public var displayName: String
    public var groupName: String
    public var remainingFraction: Double
    public var resetTime: Date?
    public var windowHint: String?

    public init(
        bucketID: String,
        displayName: String,
        groupName: String,
        remainingFraction: Double,
        resetTime: Date? = nil,
        windowHint: String? = nil
    ) {
        self.bucketID = bucketID
        self.displayName = displayName
        self.groupName = groupName
        self.remainingFraction = remainingFraction
        self.resetTime = resetTime
        self.windowHint = windowHint
    }

    public var usedPercent: Double {
        let remaining = min(max(remainingFraction, 0), 1)
        return (1 - remaining) * 100
    }

    public var isGeminiGroup: Bool {
        let id = bucketID.lowercased()
        let group = groupName.lowercased()
        if id.contains("gemini") { return true }
        if group.contains("gemini") { return true }
        if id.hasPrefix("3p") || group.contains("claude") || group.contains("gpt") {
            return false
        }
        return true
    }

    public var isFiveHour: Bool {
        let id = bucketID.lowercased()
        let hint = (windowHint ?? displayName).lowercased()
        return id.contains("5h") || id.contains("five") || hint.contains("5") || hint.contains("five")
    }

    public var isWeekly: Bool {
        let id = bucketID.lowercased()
        let hint = (windowHint ?? displayName).lowercased()
        return id.contains("week") || hint.contains("week")
    }
}

public struct GeminiQuotaSummary: Sendable, Equatable {
    public var buckets: [GeminiQuotaBucket]
    public var projectID: String?
    public var planName: String?

    public init(buckets: [GeminiQuotaBucket], projectID: String? = nil, planName: String? = nil) {
        self.buckets = buckets
        self.projectID = projectID
        self.planName = planName
    }
}

public enum GeminiQuotaParser {
    public static func summary(from data: Data) throws -> GeminiQuotaSummary {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiProviderError.emptyUsage
        }
        return try summary(from: root)
    }

    public static func summary(from root: [String: Any]) throws -> GeminiQuotaSummary {
        let groups = root["groups"] as? [[String: Any]] ?? []
        var buckets: [GeminiQuotaBucket] = []

        for group in groups {
            let groupName = (group["displayName"] as? String)
                ?? (group["name"] as? String)
                ?? "Quota"
            let rawBuckets = group["buckets"] as? [[String: Any]] ?? []
            for bucket in rawBuckets {
                let remaining: Double = {
                    if let value = bucket["remainingFraction"] as? Double { return value }
                    if let value = bucket["remainingFraction"] as? Int { return Double(value) }
                    if let value = bucket["remaining_fraction"] as? Double { return value }
                    return 0
                }()
                let bucketID = (bucket["bucketId"] as? String)
                    ?? (bucket["bucket_id"] as? String)
                    ?? (bucket["displayName"] as? String)
                    ?? UUID().uuidString
                let displayName = (bucket["displayName"] as? String)
                    ?? (bucket["display_name"] as? String)
                    ?? bucketID
                let windowHint = bucket["window"] as? String
                let reset = parseISO8601(
                    (bucket["resetTime"] as? String) ?? (bucket["reset_time"] as? String)
                )

                buckets.append(
                    GeminiQuotaBucket(
                        bucketID: bucketID,
                        displayName: displayName,
                        groupName: groupName,
                        remainingFraction: remaining,
                        resetTime: reset,
                        windowHint: windowHint
                    )
                )
            }
        }

        guard !buckets.isEmpty else { throw GeminiProviderError.emptyUsage }

        let projectID = root["cloudaicompanionProject"] as? String
            ?? root["project"] as? String
        let planName = extractPlanName(from: root)

        return GeminiQuotaSummary(buckets: buckets, projectID: projectID, planName: planName)
    }

    public static func projectID(fromLoadCodeAssist data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let project = root["cloudaicompanionProject"] as? String, !project.isEmpty {
            return project
        }
        if let nested = root["cloudaicompanionProject"] as? [String: Any],
           let id = nested["id"] as? String ?? nested["name"] as? String,
           !id.isEmpty
        {
            return id
        }
        return nil
    }

    public static func planName(fromLoadCodeAssist data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return extractPlanName(from: root)
    }

    public static func snapshot(
        from summary: GeminiQuotaSummary,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        let gemini = summary.buckets.filter(\.isGeminiGroup)
        let thirdParty = summary.buckets.filter { !$0.isGeminiGroup }

        var windows: [UsageWindow] = []

        if let five = pickFiveHour(from: gemini) ?? pickFiveHour(from: summary.buckets) {
            windows.append(window(from: five, kind: .fiveHour, fetchedAt: fetchedAt))
        }
        if let week = pickWeekly(from: gemini) ?? pickWeekly(from: summary.buckets) {
            windows.append(window(from: week, kind: .weekly, fetchedAt: fetchedAt))
        }

        // Surface Claude/GPT pool as optional extra windows when Gemini buckets were missing one.
        if windows.count < 2, let five = pickFiveHour(from: thirdParty),
           !windows.contains(where: { $0.kind == .fiveHour })
        {
            windows.append(window(from: five, kind: .fiveHour, fetchedAt: fetchedAt))
        }
        if windows.count < 2, let week = pickWeekly(from: thirdParty),
           !windows.contains(where: { $0.kind == .weekly })
        {
            windows.append(window(from: week, kind: .weekly, fetchedAt: fetchedAt))
        }

        let models: [ModelBreakdown] = summary.buckets.map { bucket in
            ModelBreakdown(
                modelID: bucket.bucketID,
                label: "\(bucket.groupName) · \(bucket.displayName)",
                amount: bucket.usedPercent,
                unit: .percent
            )
        }

        return UsageSnapshot(
            providerID: .gemini,
            fetchedAt: fetchedAt,
            windows: windows,
            models: models
        )
    }

    private static func window(
        from bucket: GeminiQuotaBucket,
        kind: UsageWindowKind,
        fetchedAt: Date
    ) -> UsageWindow {
        let fallback: TimeInterval = kind == .fiveHour ? 5 * 3600 : 7 * 24 * 3600
        return UsageWindow(
            kind: kind,
            used: bucket.usedPercent,
            limit: 100,
            unit: .percent,
            resetsAt: bucket.resetTime ?? fetchedAt.addingTimeInterval(fallback)
        )
    }

    private static func pickFiveHour(from buckets: [GeminiQuotaBucket]) -> GeminiQuotaBucket? {
        buckets.first(where: \.isFiveHour)
    }

    private static func pickWeekly(from buckets: [GeminiQuotaBucket]) -> GeminiQuotaBucket? {
        buckets.first(where: \.isWeekly)
    }

    private static func extractPlanName(from root: [String: Any]) -> String? {
        // Cloud Code Assist may return currentTier/paidTier or plural *Tiers keys.
        for key in ["paidTier", "paidTiers", "currentTier", "currentTiers"] {
            if let tier = root[key] as? [String: Any] {
                if let name = tier["name"] as? String { return name }
                if let id = tier["id"] as? String { return id }
            }
        }
        if let plan = root["planInfo"] as? [String: Any] {
            if let name = plan["planName"] as? String { return name }
            if let type = plan["planType"] as? String { return type }
        }
        return nil
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFrac.date(from: raw) ?? plain.date(from: raw)
    }
}
