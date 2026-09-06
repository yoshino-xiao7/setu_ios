import SetuIOSCore
import SwiftUI

struct SquareHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var collectionPreviewState: LoadState<[CollectionInfo]> = .idle
    @State private var aiPreviewState: LoadState<[AiPublicWork]> = .idle

    var body: some View {
        SetuBoard {
            SquareLandingHeader {
                router.navigate(to: .collectionSquare)
            } openAiSquare: {
                router.navigate(to: .aiSquare)
            }

            SquarePreviewSection(title: "收藏夹广场", state: collectionPreviewState,
                                 emptyTitle: "暂无公开收藏夹", openAll: { router.navigate(to: .collectionSquare) }) { collections in
                SetuShelf(title: "收藏夹广场", actionTitle: "查看全部", action: {
                    router.navigate(to: .collectionSquare)
                }, items: Array(collections)) { collection in
                    SetuShelfCard(
                        title: collection.name, footnote: "\(collection.itemCount ?? 0) 张",
                        imageURLString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString,
                        aspectRatio: CGFloat(collection.previewImages?.first?.width ?? 1) / CGFloat(max(1, collection.previewImages?.first?.height ?? 1))
                    ) {
                        router.navigate(to: .publicCollectionDetail(collection.id))
                    }
                    .accessibilityIdentifier("square.collection.\(collection.id)")
                }
            }

            SquarePreviewSection(title: "AI 绘画广场", state: aiPreviewState,
                                 emptyTitle: "暂无公开 AI 作品", openAll: { router.navigate(to: .aiSquare) }) { jobs in
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "AI 绘画广场", actionTitle: "查看全部") {
                        router.navigate(to: .aiSquare)
                    }
                    SetuMosaic(items: Array(jobs), aspectRatio: { CGFloat($0.width) / CGFloat(max(1, $0.height)) }) { job in
                        SetuShelfCard(title: job.promptCn, footnote: "\(job.width)×\(job.height)",
                                      imageURLString: job.imageUrl, aspectRatio: CGFloat(job.width) / CGFloat(max(1, job.height))) {
                            router.navigate(to: .publicAiWork(PublicAiWorkSnapshot(work: job)))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "我的内容")
                SetuBento(items: SquarePersonalEntry.allCases, span: { _ in .small }) { entry in
                    SetuBentoTile(title: entry.title, subtitle: entry.subtitle, systemImage: entry.systemImage) {
                        router.navigate(to: entry.route)
                    }
                    .accessibilityIdentifier("square.personal.\(entry.id)")
                }
            }
        }
        .accessibilityIdentifier("square.hub.page")
        .setuActionDock {
            SetuPrimaryButton { router.navigate(to: .collectionSquare) } label: {
                Label("浏览全部", systemImage: "square.grid.2x2")
            }
        }
        .navigationTitle("广场")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                squareToolbarLogo
            }
            #else
            ToolbarItem(placement: .automatic) {
                squareToolbarLogo
            }
            #endif
        }
        .task { await loadPreviews() }
        .refreshable { await loadPreviews() }
    }

    private var squareToolbarLogo: some View {
        SetuToolbarLogo(assetName: "SquareLogo", accessibilityLabel: "扣扣广场")
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
            collectionPreviewState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func loadAiPreviews() async {
        aiPreviewState = .loading
        do {
            let page = try await environment.aiGenerationClient.square(category: "GENERAL", page: 1, pageSize: 6)
            aiPreviewState = .loaded(page.list)
        } catch {
            aiPreviewState = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

private enum SquarePersonalEntry: String, CaseIterable, Identifiable {
    case collections, favorites
    var id: Self { self }
    var title: String { self == .collections ? "我的收藏夹" : "默认收藏" }
    var subtitle: String { self == .collections ? "管理自己的图片收藏" : "查看默认收藏图片" }
    var systemImage: String { self == .collections ? "heart.rectangle" : "heart.fill" }
    var route: AppRoute { self == .collections ? .collections : .favorites }
}

private struct SquareLandingHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let openCollections: () -> Void
    let openAiSquare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.lg) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        squareIcon
                        squareCopy
                    }
                } else {
                    HStack(spacing: SetuSpacing.lg) {
                        squareIcon
                        squareCopy
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: SetuSpacing.md) {
                    collectionsButton
                    aiSquareButton
                }
                VStack(spacing: SetuSpacing.sm) {
                    collectionsButton
                    aiSquareButton
                }
            }
            .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(SetuSpacing.xl)
        .background(SetuColor.heroGradient, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .setuElevation(.hero)
    }

    private var squareIcon: some View {
        Image(systemName: "rectangle.stack.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
            .accessibilityHidden(true)
    }

    private var squareCopy: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text("广场")
                .font(SetuTypography.title)
            Text("浏览公开收藏夹和 AI 绘画作品，直接进入你感兴趣的内容。")
                .font(SetuTypography.caption)
                .opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var collectionsButton: some View {
        Button(action: openCollections) {
            Label("收藏夹", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }

    private var aiSquareButton: some View {
        Button(action: openAiSquare) {
            Label("AI 绘画", systemImage: "sparkles")
                .foregroundStyle(SetuColor.brandOnLight)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
    }
}

private struct SquarePreviewSection<Items: RandomAccessCollection, Content: View>: View where Items.Element: Identifiable {
    let title: String
    let state: LoadState<Items>
    let emptyTitle: String
    let openAll: () -> Void
    @ViewBuilder let content: (Items) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                SetuSkeletonTile(aspectRatio: 2, title: "正在加载\(title)")
            }
        case .failed(let error):
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(error: error, retry: openAll)
                }
            }
        case .loaded(let items) where items.isEmpty:
            SetuCard {
                SetuEmptyState(title: emptyTitle, systemImage: "rectangle.stack", actionTitle: "查看全部", action: openAll)
            }
        case .loaded(let items):
            content(items)
        }
    }
}
