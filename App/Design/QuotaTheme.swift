import QuotaCore
import SwiftUI

enum QuotaTheme {
    static let accent = Color(red: 0.20, green: 0.72, blue: 0.65)
    static let warn = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let critical = Color(red: 0.92, green: 0.35, blue: 0.30)
    static let muted = Color.secondary

    static func color(for severity: AlertSeverity) -> Color {
        switch severity {
        case .ok: accent
        case .warn: warn
        case .critical: critical
        }
    }

    static func symbol(for severity: AlertSeverity) -> String {
        switch severity {
        case .ok: "gauge.with.dots.needle.67percent"
        case .warn: "gauge.with.dots.needle.50percent"
        case .critical: "gauge.with.dots.needle.100percent"
        }
    }
}
