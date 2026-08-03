import QuotaCore
import SwiftUI

/// Provider marks on a dark plate. Non-Cursor icons use a white tint.
struct ProviderIconView: View {
    let providerID: ProviderID
    var size: CGFloat = 22

    var body: some View {
        Group {
            if providerID.usesWhiteTintedIcon {
                Image(providerID.assetIconName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(providerID.assetIconName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .padding(size * 0.14)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .accessibilityHidden(true)
    }
}
