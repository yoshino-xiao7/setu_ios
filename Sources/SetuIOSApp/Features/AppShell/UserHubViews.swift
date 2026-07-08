import SetuIOSCore
import SwiftUI

struct AiHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                SetuHeroCard(title: "AI 绘画", subtitle: "输入提示词、选择尺寸和模型，直接创建新的绘画任务。", systemImage: "paintbrush.pointed") {
                    router.navigate(to: .aiDraw)
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "我的创作")
                        HubNavigationRow(title: "AI 绘画历史", subtitle: "查看任务状态、结果图和复用参数", systemImage: "clock.arrow.circlepath") {
                            router.navigate(to: .aiHistory)
                        }
                        HubNavigationRow(title: "我的删除记录", subtitle: "查看已提交的 AI 作品删除申请", systemImage: "xmark.bin") {
                            router.navigate(to: .aiDeleteRequests)
                        }
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "公开内容")
                        HubNavigationRow(title: "AI 绘画广场", subtitle: "浏览公开的 AI 作品", systemImage: "sparkles.rectangle.stack") {
                            router.navigate(to: .aiSquare)
                        }
                    }
                }
            }
            .setuListRow()
        }
        .listStyle(.plain)
        .setuBackground()
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
                SetuHeroCard(title: "随机图片", subtitle: "进入后上下滑、左右滑即可不断刷图。", systemImage: "photo.on.rectangle.angled") {
                    router.navigate(to: .imageSwipe)
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "随机刷图")
                        ImageUsageOverviewRow(pointsState: pointsState, costPerCall: costPerCall) {
                            Task { await loadPoints() }
                        }
                        SetuPill(text: "非 R18 / regular / 排除 AI", systemImage: "slider.horizontal.3", tone: .brand)
                        Text("点击上方“随机图片”进入后可通过手势快速切换下一张。")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "图片工具")
                        HubNavigationRow(title: "积分调用", subtitle: "管理积分余额、参数和刷图批量获取", systemImage: "bolt.circle") {
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
            }
            .setuListRow()
        }
        .listStyle(.plain)
        .setuBackground()
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
                SquareLandingHeader {
                    router.navigate(to: .collectionSquare)
                } openAiSquare: {
                    router.navigate(to: .aiSquare)
                }
            }
            .setuListRow()

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
                title: "AI 绘画广场",
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

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "内容广场")
                        HubNavigationRow(title: "收藏夹广场", subtitle: "查看公开收藏夹和图片集合", systemImage: "rectangle.stack") {
                            router.navigate(to: .collectionSquare)
                        }
                        HubNavigationRow(title: "AI 绘画广场", subtitle: "查看公开 AI 绘画作品", systemImage: "sparkles") {
                            router.navigate(to: .aiSquare)
                        }
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "我的内容")
                        HubNavigationRow(title: "我的收藏夹", subtitle: "管理自己的图片收藏", systemImage: "heart.rectangle") {
                            router.navigate(to: .collections)
                        }
                        HubNavigationRow(title: "我的收藏", subtitle: "查看默认收藏图片", systemImage: "heart.fill") {
                            router.navigate(to: .favorites)
                        }
                    }
                }
            }
            .setuListRow()
        }
        .listStyle(.plain)
        .setuBackground()
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

private struct HubNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        SetuNavigationRow(title: title, subtitle: subtitle, systemImage: systemImage, action: action)
    }
}

private struct SquareLandingHeader: View {
    let openCollections: () -> Void
    let openAiSquare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.lg) {
            HStack(spacing: SetuSpacing.lg) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("广场")
                        .font(SetuTypography.title)
                    Text("浏览公开收藏夹和 AI 绘画作品，直接进入你感兴趣的内容。")
                        .font(SetuTypography.caption)
                        .opacity(0.9)
                }
            }

            HStack(spacing: SetuSpacing.md) {
                Button(action: openCollections) {
                    Label("收藏夹", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button(action: openAiSquare) {
                    Label("AI 绘画", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
            .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(SetuSpacing.xl)
        .background(SetuColor.heroGradient, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
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
                    .tint(SetuColor.brandPink)
                Text("正在加载积分")
                    .foregroundStyle(SetuColor.textSecondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("积分加载失败", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SetuColor.danger)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(3)
                Button("重试", action: onRetry)
            }
        case .loaded(let balance):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(balance.points)", systemImage: "bolt.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SetuColor.brandInk)
                    Text("当前积分")
                        .font(.footnote)
                        .foregroundStyle(SetuColor.textSecondary)
                    Spacer()
                    SetuPill(text: "单次 \(costPerCall)", tone: .brand)
                }

                ProgressView(value: min(Double(balance.points) / Double(max(costPerCall * 10, 1)), 1))
                    .tint(SetuColor.brandPink)

                Text(balance.points >= costPerCall ? "积分充足，可以直接滑动获取新图片。" : "积分不足，至少需要 \(costPerCall) 积分。")
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
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
                SetuCard {
                    HStack {
                        ProgressView()
                            .tint(SetuColor.brandPink)
                        Text("正在加载\(title)")
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
            case .failed(let message):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Label("\(title)加载失败", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(SetuColor.danger)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(SetuColor.textSecondary)
                            .lineLimit(2)
                        Button("进入完整页面", action: openAll)
                    }
                }
            case .loaded(let items):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: title, actionTitle: "查看全部", action: openAll)
                        if items.isEmpty {
                            SetuEmptyState(title: emptyTitle, systemImage: "rectangle.stack")
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: SetuSpacing.md) {
                                    content(items)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
        .setuListRow()
    }
}

private struct SquareCollectionPreviewCard: View {
    let collection: CollectionInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                SetuImageTile(urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString, aspectRatio: 132 / 92)
                    .frame(width: 132)

                Text(collection.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                    .frame(width: 132, alignment: .leading)

                Label("\(collection.itemCount ?? 0) 张", systemImage: "photo")
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textSecondary)
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
                SetuImageTile(urlString: job.imageUrl)
                    .frame(width: 132)

                Text(job.promptCn)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                    .frame(width: 132, alignment: .leading)

                Label("\(job.width)x\(job.height)", systemImage: "aspectratio")
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
