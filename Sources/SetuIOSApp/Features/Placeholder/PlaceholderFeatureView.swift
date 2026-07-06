import SwiftUI

struct PlaceholderFeatureView: View {
    let title: String
    let systemImage: String
    let summary: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(summary)
        }
        .navigationTitle(title)
    }
}
