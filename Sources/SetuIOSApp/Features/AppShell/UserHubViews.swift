import SetuIOSCore
import SwiftUI

struct AiHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "AI 绘画",
                    subtitle: "输入提示词、选择尺寸和模型，直接创建新的绘图任务。",
                    systemImage: "paintbrush.pointed",
                    tint: .purple
                ) {
                    router.navigate(to: .aiDraw)
                }
            }

            Section("我的创作") {
                HubNavigationRow(title: "AI 绘画历史", subtitle: "查看任务状态、结果图和复用参数", systemImage: "clock.arrow.circlepath") {
                    router.navigate(to: .aiHistory)
                }
                HubNavigationRow(title: "我的删除记录", subtitle: "查看已提交的 AI 作品删除申请", systemImage: "xmark.bin") {
                    router.navigate(to: .aiDeleteRequests)
                }
            }

            Section("公开内容") {
                HubNavigationRow(title: "AI 绘图广场", subtitle: "浏览公开的 AI 作品", systemImage: "sparkles.rectangle.stack") {
                    router.navigate(to: .aiSquare)
                }
            }
        }
        .navigationTitle("AI")
    }
}

struct ImageHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var pointsState: LoadState<PointsBalance> = .idle

    private let costPerCall = 20

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "随机图片",
                    subtitle: "使用积分调用图片接口，上下或左右滑动获取新图片。",
                    systemImage: "photo.on.rectangle.angled",
                    tint: .pink
                ) {
                    router.navigate(to: .imageSwipe)
                }
            }

            Section("本次刷图") {
                ImageUsageOverviewRow(pointsState: pointsState, costPerCall: costPerCall) {
                    Task { await loadPoints() }
                }
                LabeledContent("默认内容", value: "非 R18")
                LabeledContent("图片尺寸", value: "regular")
                LabeledContent("AI 图片", value: "默认排除")
                Button {
                    router.navigate(to: .imageSwipe)
                } label: {
                    Label("开始刷图", systemImage: "hand.draw")
                }
            }

            Section("图片工具") {
                HubNavigationRow(title: "积分调用", subtitle: "配置 R18、尺寸、关键词、标签等参数", systemImage: "bolt.circle") {
                    router.navigate(to: .points)
                }
                HubNavigationRow(title: "积分流水", subtitle: "查看积分消耗和接口调用记录", systemImage: "list.bullet.rectangle") {
                    router.navigate(to: .pointsLogs)
                }
                HubNavigationRow(title: "图库投稿", subtitle: "上传图片并查看投稿批次", systemImage: "square.and.arrow.up") {
                    router.navigate(to: .galleryUploads)
                }
                HubNavigationRow(title: "我的删除申请", subtitle: "查看图片删除申请状态", systemImage: "trash") {
                    router.navigate(to: .imageDeleteRequests)
                }
            }
        }
        .navigationTitle("图片")
        .task { await loadPoints() }
        .refreshable { await loadPoints() }
    }

    private func loadPoints() async {
        pointsState = .loading
        do {
            pointsState = .loaded(try await environment.pointsClient.balance())
        } catch {
            pointsState = .failed(error.localizedDescription)
        }
    }
}

struct SquareHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "广场",
                    subtitle: "集中浏览用户公开内容，后续会把图片预览做成更沉浸的瀑布流。",
                    systemImage: "rectangle.stack.fill",
                    tint: .blue
                ) {
                    router.navigate(to: .collectionSquare)
                }
            }

            Section("内容广场") {
                HubNavigationRow(title: "收藏夹广场", subtitle: "查看公开收藏夹和图片集合", systemImage: "rectangle.stack") {
                    router.navigate(to: .collectionSquare)
                }
                HubNavigationRow(title: "AI 绘图广场", subtitle: "查看公开 AI 生成作品", systemImage: "sparkles") {
                    router.navigate(to: .aiSquare)
                }
            }

            Section("我的内容") {
                HubNavigationRow(title: "我的收藏夹", subtitle: "管理自己的图片收藏", systemImage: "heart.rectangle") {
                    router.navigate(to: .collections)
                }
                HubNavigationRow(title: "我的收藏", subtitle: "查看默认收藏图片", systemImage: "heart.fill") {
                    router.navigate(to: .favorites)
                }
            }
        }
        .navigationTitle("广场")
    }
}

private struct HubHeroRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct HubNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.pink)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

private struct ImageUsageOverviewRow: View {
    let pointsState: LoadState<PointsBalance>
    let costPerCall: Int
    let onRetry: () -> Void

    var body: some View {
        switch pointsState {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("正在加载积分")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("积分加载失败", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Button("重试", action: onRetry)
            }
        case .loaded(let balance):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(balance.points)", systemImage: "bolt.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.pink)
                    Text("当前积分")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("单次 \(costPerCall)")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.pink.opacity(0.12), in: Capsule())
                        .foregroundStyle(.pink)
                }

                ProgressView(value: min(Double(balance.points) / Double(max(costPerCall * 10, 1)), 1))
                    .tint(.pink)

                Text(balance.points >= costPerCall ? "积分充足，可以直接滑动获取新图片。" : "积分不足，至少需要 \(costPerCall) 积分。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
    }
}
