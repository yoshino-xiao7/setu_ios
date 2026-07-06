import SetuIOSCore
import SwiftUI

struct FeatureDetailView: View {
    let feature: AppFeature

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: feature.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.pink)
                    Text(feature.title)
                        .font(.title.bold())
                    Text(feature.subtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("来源") {
                LabeledContent("前端路由", value: feature.webRoute)
                LabeledContent("模块", value: feature.group.title)
            }

            Section {
                Text("此模块已纳入 iOS 开发清单。下一步会按前端 API 先补 Core client 和 DTO，再实现原生 SwiftUI 页面。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(feature.title)
    }
}
