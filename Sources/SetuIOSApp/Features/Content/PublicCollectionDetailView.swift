import SetuIOSCore
import SwiftUI

struct PublicCollectionDetailView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    let collectionID: Int

    @State private var pager = PagingController<CollectionItem>(pageSize: 24)
    @State private var infoRevision = UUID()
    private var items: [CollectionItem] { pager.items }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    @State private var infoState: LoadState<CollectionInfo> = .idle
    @State private var feedback: SetuFeedback?
    @State private var previewItem: UserImagePreviewItem?
    private let pageSize = 24

    var body: some View {
        SetuBoard {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
            }

            if let initialError, !items.isEmpty {
                SetuLoadMoreFooter(state: .failed(initialError)) {
                    Task { await loadFirstPage() }
                }
            }

            switch infoState {
            case .idle, .loading:
                SetuCard {
                    SetuEmptyState(
                        title: "正在加载公开收藏夹",
                        message: "正在同步收藏夹信息与分享状态。",
                        systemImage: "rectangle.stack",
                        isLoading: true
                    )
                }
            case .failed(let message):
                SetuCard {
                    SetuEmptyState(title: "公开收藏夹加载失败", message: message, systemImage: "rectangle.stack.badge.minus")
                }
            case .loaded(let info):
                headerSection(info)
                publicActionSection(info)
            }

            if isInitialLoading {
                SetuCard {
                    SetuEmptyState(
                        title: "正在加载图片",
                        message: "图片列表马上就好。",
                        systemImage: "photo.on.rectangle",
                        isLoading: true
                    )
                }
            } else if items.isEmpty {
                itemEmptyState
            } else {
                SetuSectionHeader(title: "公开图片", subtitle: "共 \(total) 张")
                SetuMosaic(items: items, aspectRatio: { CGFloat($0.image?.width ?? 1) / CGFloat(max($0.image?.height ?? 1, 1)) }) { item in
                    PublicCollectionImageTile(item: item) {
                        previewItem = UserImagePreviewItem(collectionItem: item)
                    }
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await loadMore() }
                        }
                    }
                }
                SetuLoadMoreFooter(state: loadMoreFooterState) {
                    Task { await loadMore() }
                }
            }
        }
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .navigationTitle(title)
        .sheet(item: $previewItem) { item in
            UserImagePreviewSheet(item: item)
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    @ViewBuilder
    private var itemEmptyState: some View {
        if let initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "图片加载失败", message: initialError, systemImage: "photo.on.rectangle.angled")
                    Button("重试") {
                        Task { await loadFirstPage() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无图片", message: "这个公开收藏夹还没有可展示的图片。", systemImage: "photo")
            }
        }
    }

    private var hasMore: Bool { pager.hasMore }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadMoreError { return .failed(loadMoreError) }
        if !hasMore { return .complete("已加载全部 \(total) 张图片") }
        return .idle
    }

    private var title: String {
        if case .loaded(let info) = infoState {
            info.name
        } else {
            "公开收藏夹"
        }
    }

    @ViewBuilder
    private func headerSection(_ info: CollectionInfo) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                HStack(alignment: .top, spacing: SetuSpacing.md) {
                    SetuRemoteImage(
                        urlString: info.coverUrl ?? info.previewImages?.first?.bestURLString,
                        accessibilityLabel: "收藏夹「\(info.name)」封面"
                    )
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(info.name)
                            .font(SetuTypography.title)
                            .foregroundStyle(SetuColor.textPrimary)
                        if let description = info.description, !description.isEmpty {
                            Text(description)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                                .lineLimit(3)
                        }
                        Button {
                            router.navigate(to: .publicUserProfile(info.userId))
                        } label: {
                            Label(info.ownerNickname ?? "匿名分享者", systemImage: "person.crop.circle")
                                .font(SetuTypography.caption)
                        }
                        .buttonStyle(.borderless)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SetuSpacing.sm) {
                                SetuPill(text: "\(info.itemCount ?? 0) 张", systemImage: "photo", tone: .info)
                                SetuPill(text: "\(info.shareViewCount ?? 0)", systemImage: "eye", tone: .muted)
                                SetuPill(text: "\(info.likeCount ?? info.shareLikeCount ?? 0)", systemImage: "hand.thumbsup", tone: .brand)
                            }
                        }
                    }
                }

                if let tags = info.tags, !tags.isEmpty {
                    TagFlow(tags: tags)
                }

                if let note = info.curatorNote, !note.isEmpty {
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text("推荐语")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                        Text(note)
                            .font(SetuTypography.body)
                            .foregroundStyle(SetuColor.textPrimary)
                    }
                }
            }
        }
    }

    private func publicActionSection(_ info: CollectionInfo) -> some View {
        SetuCard {
            VStack(spacing: SetuSpacing.sm) {
                Button {
                    Task { await like(info) }
                } label: {
                    Label(info.likedByMe == true ? "取消点赞" : "点赞", systemImage: "hand.thumbsup")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                Divider()
                    .overlay(SetuColor.separator)

                Button {
                    Task { await favorite(info) }
                } label: {
                    Label(info.favoritedByMe == true ? "取消收藏" : "收藏", systemImage: "star")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                Divider()
                    .overlay(SetuColor.separator)

                Button {
                    copyShareLink(info)
                } label: {
                    Label("复制分享链接", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }

                Divider()
                    .overlay(SetuColor.separator)

                Link(destination: publicShareURL(for: info)) {
                    Label("打开公开预览", systemImage: "arrow.up.forward.square")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .font(SetuTypography.body)
        }
    }

    private func publicShareURL(for info: CollectionInfo) -> URL {
        environment.config.siteBaseURL
            .appendingPathComponent("c")
            .appendingPathComponent(String(info.id))
    }

    private func copyShareLink(_ info: CollectionInfo) {
        PlatformClipboard.copy(publicShareURL(for: info).absoluteString)
        feedback = .success("分享链接已复制")
    }

    private func loadFirstPage() async {
        let revision = UUID()
        infoRevision = revision
        if case .loaded = infoState {} else { infoState = .loading }
        async let page: Void = pager.loadFirstPage { page in
            let result = try await environment.collectionClient.items(collectionID: collectionID, page: page, size: pageSize)
            return .init(items: result.items, total: result.total)
        }
        do {
            let info = try await environment.collectionClient.squareDetail(id: collectionID)
            if revision == infoRevision { infoState = .loaded(info) }
        } catch {
            if revision == infoRevision { infoState = .failed(UserFacingErrorMapper.map(error)) }
        }
        await page
    }

    private func loadMore() async {
        await pager.loadMore { page in
            let result = try await environment.collectionClient.items(collectionID: collectionID, page: page, size: pageSize)
            return .init(items: result.items, total: result.total)
        }
    }

    private func like(_ info: CollectionInfo) async {
        feedback = nil
        do {
            let shouldLike = info.likedByMe != true
            try await environment.collectionClient.likeSquareCollection(id: info.id, liked: shouldLike)
            await loadFirstPage()
            feedback = .success(shouldLike ? "已点赞" : "已取消点赞")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func favorite(_ info: CollectionInfo) async {
        feedback = nil
        do {
            let shouldFavorite = info.favoritedByMe != true
            try await environment.collectionClient.favoriteSquareCollection(id: info.id, favorited: shouldFavorite)
            await loadFirstPage()
            feedback = .success(shouldFavorite ? "已收藏" : "已取消收藏")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private struct PublicCollectionImageTile: View {
    let item: CollectionItem
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            SetuCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ContentGridImageView(
                        urlString: item.image?.urlSmall ?? item.image?.urlRegular ?? item.image?.urlOriginal,
                        accessibilityLabel: item.image?.title ?? "未命名作品",
                        aspectRatio: CGFloat(item.image?.width ?? 1) / CGFloat(max(item.image?.height ?? 1, 1))
                    )

                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(item.image?.title ?? "未命名作品")
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.textPrimary)
                            .lineLimit(2)
                        Text(item.image?.author ?? "未知作者")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .lineLimit(1)
                        if let image = item.image {
                            Label("\(image.width)x\(image.height)", systemImage: "aspectratio")
                                .font(.caption2)
                                .foregroundStyle(SetuColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(SetuSpacing.md)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看 \(item.image?.title ?? "未命名作品")")
    }
}
