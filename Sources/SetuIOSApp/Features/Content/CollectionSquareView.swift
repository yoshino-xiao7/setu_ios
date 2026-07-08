import SetuIOSCore
import SwiftUI

struct CollectionSquareView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<CollectionInfo>> = .idle
    @State private var sort = "hot"
    @State private var searchText = ""
    @State private var keyword = ""
    @State private var page = 1
    @State private var actionMessage: String?
    private let pageSize = 20

    var body: some View {
        List {
            SetuCard {
                Picker("排序", selection: $sort) {
                    Text("热门").tag("hot")
                    Text("最新").tag("new")
                    Text("点赞").tag("like")
                }
                .pickerStyle(.segmented)
            }
            .setuListRow()
            .onChange(of: sort) {
                Task {
                    page = 1
                    await load()
                }
            }

            if let actionMessage {
                SetuCard {
                    Label(actionMessage, systemImage: "checkmark.circle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .setuListRow()
            }

            switch state {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载收藏夹广场", message: "正在整理公开收藏夹。", systemImage: "globe.asia.australia", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(title: "广场加载失败", message: message, systemImage: "globe.asia.australia")
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentImageStateSection(title: "暂无公开收藏夹", message: "换个关键词或排序方式再试试。", systemImage: "rectangle.stack")
                } else {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "共 \(page.total) 个", subtitle: "公开收藏夹")
                            ForEach(Array(page.list.enumerated()), id: \.element.id) { index, collection in
                                if index > 0 {
                                    Divider()
                                        .overlay(SetuColor.separator)
                                }
                                Button {
                                    router.navigate(to: .publicCollectionDetail(collection.id))
                                } label: {
                                    CollectionSquareRow(collection: collection) {
                                        Task { await like(collection) }
                                    } onFavorite: {
                                        Task { await favorite(collection) }
                                    } onOwner: {
                                        router.navigate(to: .publicUserProfile(collection.userId))
                                    }
                                }
                                .buttonStyle(.plain)
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
        .navigationTitle("收藏夹广场")
        .searchable(text: $searchText, prompt: "搜索收藏夹")
        .onSubmit(of: .search) {
            Task { await submitSearch() }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty, !keyword.isEmpty {
                Task {
                    keyword = ""
                    page = 1
                    await load()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PageResult<CollectionInfo>) -> some View {
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
                .disabled(result.page * result.pageSize >= result.total)
            }
            .font(SetuTypography.body)
        }
        .setuListRow()
    }

    private func load() async {
        state = .loading
        actionMessage = nil
        do {
            state = .loaded(try await environment.collectionClient.square(page: page, size: pageSize, sort: sort, keyword: keyword))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func submitSearch() async {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        page = 1
        await load()
    }

    private func like(_ collection: CollectionInfo) async {
        do {
            try await environment.collectionClient.likeSquareCollection(id: collection.id, liked: collection.likedByMe != true)
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func favorite(_ collection: CollectionInfo) async {
        do {
            try await environment.collectionClient.favoriteSquareCollection(id: collection.id, favorited: collection.favoritedByMe != true)
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct CollectionSquareRow: View {
    let collection: CollectionInfo
    let onLike: () -> Void
    let onFavorite: () -> Void
    let onOwner: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            HStack(alignment: .top, spacing: SetuSpacing.md) {
                ImageThumbnailView(urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(collection.name)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    if let description = collection.description, !description.isEmpty {
                        Text(description)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .lineLimit(2)
                    }
                    Button(action: onOwner) {
                        Label(collection.ownerNickname ?? "匿名分享者", systemImage: "person.crop.circle")
                            .font(SetuTypography.caption)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let previews = collection.previewImages, !previews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(previews.prefix(5)) { image in
                            ImageThumbnailView(urlString: image.bestURLString, width: 48, height: 48)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Label("\(collection.itemCount ?? 0) 张", systemImage: "photo")
                Label("\(collection.shareViewCount ?? 0)", systemImage: "eye")
                Label("\(collection.likeCount ?? collection.shareLikeCount ?? 0)", systemImage: "hand.thumbsup")
                Label("\(collection.favoriteCount ?? collection.shareFavCount ?? 0)", systemImage: "star")
            }
            .font(.caption2)
            .foregroundStyle(SetuColor.textTertiary)

            HStack {
                Button(action: onLike) {
                    Label(collection.likedByMe == true ? "取消点赞" : "点赞", systemImage: "hand.thumbsup")
                        .frame(minHeight: 44)
                }
                Spacer()
                Button(action: onFavorite) {
                    Label(collection.favoritedByMe == true ? "取消收藏" : "收藏", systemImage: "star")
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.borderless)
            .font(SetuTypography.caption)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}
