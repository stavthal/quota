import AppKit
import QuotaCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var session: AppSession

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibilityText)
    }

    private var pinnedStatusText: String? {
        MenuBarStatusFormatter.statusText(
            pins: session.preferences.orderedMenuBarPins,
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
