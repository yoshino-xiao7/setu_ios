import SwiftUI

struct SetuToolbarLogo: View {
    let assetName: String
    let accessibilityLabel: String

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(
                width: SetuToolbarLogoMetrics.width,
                height: SetuToolbarLogoMetrics.height
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("hub.logo.\(assetName)")
    }
}
