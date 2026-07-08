import SetuIOSCore
import SwiftUI

struct PublicCollectionDetailView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let collectionID: Int

    @State private var infoState: LoadState<CollectionInfo> = .idle
    @State private var itemsState: LoadState<CollectionItemPage> = .idle
    @State private var actionMessage: String?
    @State private var previewItem: CollectionImagePreviewItem?
    @State private var page = 1
    private let pageSize = 24

    var body: some View {
        List {
            if let actionMessage {
                SetuCard {
                    Label(actionMessage, systemImage: "checkmark.circle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .setuListRow()
            }

            switch infoState {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载公开收藏夹", message: "正在同步收藏夹信息与分享状态。", systemImage: "rectangle.stack", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(title: "公开收藏夹加载失败", message: message, systemImage: "rectangle.stack.badge.minus")
            case .loaded(let info):
                headerSection(info)
                publicActionSection(info)
            }

            switch itemsState {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载图片", message: "图片列表马上就好。", systemImage: "photo.on.rectangle", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(title: "图片加载失败", message: message, systemImage: "photo.on.rectangle.angled")
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentImageStateSection(title: "暂无图片", message: "这个公开收藏夹还没有可展示的图片。", systemImage: "photo")
                } else {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "共 \(page.total) 张", subtitle: "公开图片")
                            ForEach(Array(page.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Divider()
                                        .overlay(SetuColor.separator)
                                }
                                PublicCollectionImageRow(item: item) {
                                    previewItem = CollectionImagePreviewItem(item: item)
                                }
                            }
                        }
                    }
                    .setuListRow()
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle(title)
        .sheet(item: $previewItem) { item in
            CollectionImagePreviewSheet(item: item)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: CollectionItemPage) -> some View {
        SetuCard {
            HStack {
                Button {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()

                Button {
                    Task {
                        page += 1
                        await load()
                    }
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .frame(minHeight: 44)
                }
                .disabled(result.page * result.size >= result.total)
            }
            .font(SetuTypography.body)
        }
        .setuListRow()
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
                ImageThumbnailView(urlString: info.coverUrl ?? info.previewImages?.first?.bestURLString)
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
                            Label(info.ownerNickname ?? "用户#\(info.userId)", systemImage: "person.crop.circle")
                                .font(SetuTypography.caption)
                        }
                        .buttonStyle(.borderless)
                        HStack(spacing: SetuSpacing.md) {
                            SetuPill(text: "\(info.itemCount ?? 0) 张", systemImage: "photo", tone: .info)
                            SetuPill(text: "\(info.shareViewCount ?? 0)", systemImage: "eye", tone: .muted)
                            SetuPill(text: "\(info.likeCount ?? info.shareLikeCount ?? 0)", systemImage: "hand.thumbsup", tone: .brand)
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
        .setuListRow()
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
        .setuListRow()
    }

    private func publicShareURL(for info: CollectionInfo) -> URL {
        environment.config.siteBaseURL
            .appendingPathComponent("c")
            .appendingPathComponent(String(info.id))
    }

    private func copyShareLink(_ info: CollectionInfo) {
        PlatformClipboard.copy(publicShareURL(for: info).absoluteString)
        actionMessage = "分享链接已复制"
    }

    private func load() async {
        actionMessage = nil
        infoState = .loading
        itemsState = .loading
        do {
            async let info = environment.collectionClient.squareDetail(id: collectionID)
            async let items = environment.collectionClient.items(collectionID: collectionID, page: page, size: pageSize)
            infoState = .loaded(try await info)
            itemsState = .loaded(try await items)
        } catch {
            let message = error.localizedDescription
            if case .loading = infoState {
                infoState = .failed(message)
            }
            if case .loading = itemsState {
                itemsState = .failed(message)
            }
        }
    }

    private func like(_ info: CollectionInfo) async {
        do {
            try await environment.collectionClient.likeSquareCollection(id: info.id, liked: info.likedByMe != true)
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func favorite(_ info: CollectionInfo) async {
        do {
            try await environment.collectionClient.favoriteSquareCollection(id: info.id, favorited: info.favoritedByMe != true)
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct PublicCollectionImageRow: View {
    let item: CollectionItem
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            ImageThumbnailView(urlString: item.image?.urlSmall ?? item.image?.urlRegular ?? item.image?.urlOriginal)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(item.image?.title ?? "PID \(item.pid)")
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.image?.author ?? "未知作者")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.p)", systemImage: "number")
                    if let image = item.image {
                        Label("\(image.width)x\(image.height)", systemImage: "aspectratio")
                    }
                }
                .font(.caption2)
                .foregroundStyle(SetuColor.textTertiary)

                if item.image != nil {
                    Button {
                        onPreview()
                    } label: {
                        Label("查看图片", systemImage: "eye")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .font(SetuTypography.caption)
                }
            }
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}
