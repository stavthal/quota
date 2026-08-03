import QuotaCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var session: AppSession

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: QuotaTheme.symbol(for: session.aggregateSeverity))
            if let text = pinnedStatusText {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var pinnedStatusText: String? {
        MenuBarStatusFormatter.statusText(
            pins: session.preferences.menuBarPins,
            snapshots: session.snapshots
        )
    }

    private var accessibilityText: String {
        if let pinnedStatusText {
            return "Headroom \(session.aggregateSeverity.rawValue), \(pinnedStatusText)"
        }
        return "Headroom \(session.aggregateSeverity.rawValue)"
    }
}
