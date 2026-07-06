import SetuIOSCore
import SwiftUI

struct FeatureMapView: View {
    @Environment(RouterPath.self) private var router

    var body: some View {
        List {
            ForEach(AppFeatureGroup.allCases, id: \.self) { group in
                let features = AppFeatureCatalog.features(in: group)
                if !features.isEmpty {
                    Section(group.title) {
                        ForEach(features) { feature in
                            Button {
                                router.navigate(to: .feature(feature.id))
                            } label: {
                                FeatureListRow(feature: feature)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("功能")
    }
}

private struct FeatureListRow: View {
    let feature: AppFeature

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.systemImage)
                .foregroundStyle(.pink)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(feature.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}
