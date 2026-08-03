import QuotaCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var session: AppSession

    var body: some View {
        Image(systemName: QuotaTheme.symbol(for: session.aggregateSeverity))
            .accessibilityLabel("Headroom \(session.aggregateSeverity.rawValue)")
    }
}
