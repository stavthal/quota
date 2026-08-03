import Foundation

/// Builds the compact status-item text for pinned usage windows.
public enum MenuBarStatusFormatter {
    public static let maxPins = QuotaPreferences.maxMenuBarPins

    /// Returns `nil` when no pinned windows have live data.
    public static func statusText(
        pins: [MenuBarPin],
        snapshots: [ProviderID: UsageSnapshot]
    ) -> String? {
        var parts: [String] = []
        for pin in pins.prefix(maxPins) {
            guard let snapshot = snapshots[pin.providerID],
                  let window = snapshot.windows.first(where: { $0.kind == pin.windowKind })
            else { continue }
            parts.append(segment(provider: pin.providerID, window: window))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    public static func providerCode(for id: ProviderID) -> String {
        switch id {
        case .cursor: "Cur"
        case .codex: "GPT"
        case .copilot: "Cop"
        case .grok: "Grk"
        case .opencode: "OC"
        }
    }

    public static func windowCode(for kind: UsageWindowKind) -> String {
        switch kind {
        case .cursorAuto: "M"
        case .cursorAPI: "API"
        case .fiveHour: "5h"
        case .weekly: "Wk"
        case .monthly: "Mo"
        case .copilotCredits: "Cr"
        case .custom: "Od"
        }
    }

    public static func valueLabel(for window: UsageWindow) -> String {
        if window.limit > 0 {
            return "\(Int((window.utilization * 100).rounded()))%"
        }
        if window.unit == .credits {
            if window.used != floor(window.used) {
                return String(format: "$%.1f", window.used)
            }
            return String(format: "$%.0f", window.used)
        }
        return "—"
    }

    private static func segment(provider: ProviderID, window: UsageWindow) -> String {
        "\(providerCode(for: provider))·\(windowCode(for: window.kind)) \(valueLabel(for: window))"
    }
}
