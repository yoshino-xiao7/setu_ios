import SetuIOSCore
import SwiftUI

struct DashboardView: View {
    @Bindable var environment: AppEnvironment
    @Environment(RouterPath.self) private var router

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("雪涼云")
                        .font(.largeTitle.bold())
                    Text("原生 iOS 控制台基础框架")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("常用功能") {
                FeatureRow(title: "API Keys", systemImage: "key") {
                    router.navigate(to: .apiKeys)
                }
                FeatureRow(title: "积分流水", systemImage: "list.bullet.rectangle") {
                    router.navigate(to: .pointsLogs)
                }
                FeatureRow(title: "通知中心", systemImage: "bell") {
                    router.navigate(to: .notifications)
                }
            }

            Section("创作与内容") {
                FeatureRow(title: "AI 绘图历史", systemImage: "clock") {
                    router.navigate(to: .aiHistory)
                }
                FeatureRow(title: "收藏夹广场", systemImage: "globe.asia.australia") {
                    router.navigate(to: .collectionSquare)
                }
                FeatureRow(title: "音乐歌单", systemImage: "music.note.list") {
                    router.navigate(to: .playlists)
                }
            }
        }
        .navigationTitle("首页")
    }
}

private struct FeatureRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}
