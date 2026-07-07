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
        .navigationTitle("AI 绘画")
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
                    subtitle: "使用积分刷随机图片，上下或左右滑动获取新图片。",
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
                HubNavigationRow(title: "积分流水", subtitle: "查看积分获得和消耗记录", systemImage: "list.bullet.rectangle") {
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
    @State private var collectionPreviewState: LoadState<[CollectionInfo]> = .idle
    @State private var aiPreviewState: LoadState<[AiGenerationJob]> = .idle

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "广场",
                    subtitle: "浏览公开收藏夹和 AI 作品，直接进入你感兴趣的内容。",
                    systemImage: "rectangle.stack.fill",
                    tint: .blue
                ) {
                    router.navigate(to: .collectionSquare)
                }
            }

            SquarePreviewSection(
                title: "收藏夹广场",
                state: collectionPreviewState,
                emptyTitle: "暂无公开收藏夹",
                openAll: { router.navigate(to: .collectionSquare) },
                content: { collections in
                    ForEach(collections) { collection in
                        SquareCollectionPreviewCard(collection: collection) {
                            router.navigate(to: .publicCollectionDetail(collection.id))
                        }
                    }
                }
            )

            SquarePreviewSection(
                title: "AI 绘图广场",
                state: aiPreviewState,
                emptyTitle: "暂无公开 AI 作品",
                openAll: { router.navigate(to: .aiSquare) },
                content: { jobs in
                    ForEach(jobs) { job in
                        SquareAiPreviewCard(job: job) {
                            router.navigate(to: .aiGenerationDetail(job.id))
                        }
                    }
                }
            )

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
        .task { await loadPreviews() }
        .refreshable { await loadPreviews() }
    }

    private func loadPreviews() async {
        async let collections: Void = loadCollectionPreviews()
        async let jobs: Void = loadAiPreviews()
        _ = await (collections, jobs)
    }

    private func loadCollectionPreviews() async {
        collectionPreviewState = .loading
        do {
            let page = try await environment.collectionClient.square(page: 1, size: 6, sort: "hot")
            collectionPreviewState = .loaded(page.list)
        } catch {
            collectionPreviewState = .failed(error.localizedDescription)
        }
    }

    private func loadAiPreviews() async {
        aiPreviewState = .loading
        do {
            let page = try await environment.aiGenerationClient.square(category: "GENERAL", page: 1, pageSize: 6)
            aiPreviewState = .loaded(page.list)
        } catch {
            aiPreviewState = .failed(error.localizedDescription)
        }
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

private struct SquarePreviewSection<Items: RandomAccessCollection, Content: View>: View where Items.Element: Identifiable {
    let title: String
    let state: LoadState<Items>
    let emptyTitle: String
    let openAll: () -> Void
    @ViewBuilder let content: (Items) -> Content

    var body: some View {
        Section {
            switch state {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("正在加载\(title)")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(title)加载失败", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("进入完整页面", action: openAll)
                }
            case .loaded(let items):
                if items.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "rectangle.stack")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            content(items)
                        }
                        .padding(.vertical, 2)
                    }
                    Button(action: openAll) {
                        Label("查看全部", systemImage: "arrow.right.circle")
                    }
                }
            }
        } header: {
            Text(title)
        }
    }
}

private struct SquareCollectionPreviewCard: View {
    let collection: CollectionInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ImageThumbnailView(urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString)
                    .frame(width: 132, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(collection.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: 132, alignment: .leading)

                Label("\(collection.itemCount ?? 0) 张", systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct SquareAiPreviewCard: View {
    let job: AiGenerationJob
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ImageThumbnailView(urlString: job.imageUrl)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(job.promptCn)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: 132, alignment: .leading)

                Label("\(job.width)x\(job.height)", systemImage: "aspectratio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
