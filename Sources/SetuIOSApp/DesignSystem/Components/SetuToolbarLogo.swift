import SwiftUI

struct SetuToolbarLogo: View {
    let assetName: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: SetuSpacing.sm) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text("亦可 YK")
                .font(.headline)
        }
            .foregroundStyle(SetuColor.textPrimary)
            .frame(
                width: SetuToolbarLogoMetrics.width,
                height: SetuToolbarLogoMetrics.height
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("亦可 YK，\(accessibilityLabel)")
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("hub.logo.\(assetName)")
    }
}
