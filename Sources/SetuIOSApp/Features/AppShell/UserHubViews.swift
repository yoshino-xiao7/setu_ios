import SetuIOSCore
import SwiftUI

struct SquareHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var collectionPreviewState: LoadState<[CollectionInfo]> = .idle
    @State private var aiPreviewState: LoadState<[AiPublicWork]> = .idle

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
                            router.navigate(to: .publicAiWork(PublicAiWorkSnapshot(work: job)))
                        }
                    }
                }
            )



            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "我的内容")
                        HubNavigationRow(title: "我的收藏夹", subtitle: "管理自己的图片收藏", systemImage: "heart.rectangle") {
                            router.navigate(to: .collections)
                        }
                        HubNavigationRow(title: "默认收藏", subtitle: "查看默认收藏图片", systemImage: "heart.fill") {
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
        .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
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
        Section {
            SetuCard {
                SetuStateView(
                    state: state,
                    loadingTitle: "正在加载\(title)",
                    loadingImage: "rectangle.stack",
                    failureTitle: "\(title)加载失败",
                    failureImage: "exclamationmark.triangle",
                    failureActionTitle: "进入完整页面",
                    failureAction: openAll,
                    emptyTitle: emptyTitle,
                    emptyImage: "rectangle.stack",
                    isEmpty: { $0.isEmpty }
                ) { items in
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: title, actionTitle: "查看全部", action: openAll)
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
        .setuListRow()
    }
}

private struct SquareCollectionPreviewCard: View {
    let collection: CollectionInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                SetuImageTile(
                    urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString,
                    accessibilityLabel: "收藏夹「\(collection.name)」封面",
                    aspectRatio: 132 / 92
                )
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
    let job: AiPublicWork
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                SetuImageTile(urlString: job.imageUrl, accessibilityLabel: "AI 作品：\(job.promptCn)")
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
