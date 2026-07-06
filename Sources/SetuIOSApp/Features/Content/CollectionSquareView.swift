import SetuIOSCore
import SwiftUI

struct CollectionSquareView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<CollectionInfo>> = .idle
    @State private var sort = "hot"
    @State private var actionMessage: String?

    var body: some View {
        List {
            Picker("排序", selection: $sort) {
                Text("热门").tag("hot")
                Text("最新").tag("new")
                Text("点赞").tag("like")
            }
            .pickerStyle(.segmented)
            .onChange(of: sort) {
                Task { await load() }
            }

            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("广场加载失败", systemImage: "globe.asia.australia", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无公开收藏夹", systemImage: "rectangle.stack")
                } else {
                    Section("共 \(page.total) 个") {
                        ForEach(page.list) { collection in
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
                        }
                    }
                }
            }
        }
        .navigationTitle("收藏夹广场")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        actionMessage = nil
        do {
            state = .loaded(try await environment.collectionClient.square(sort: sort))
        } catch {
            state = .failed(error.localizedDescription)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ImageThumbnailView(urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString)
                VStack(alignment: .leading, spacing: 5) {
                    Text(collection.name)
                        .font(.headline)
                    if let description = collection.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Button(action: onOwner) {
                        Label(collection.ownerNickname ?? "匿名分享者", systemImage: "person.crop.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let previews = collection.previewImages, !previews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(previews.prefix(5)) { image in
                            ImageThumbnailView(urlString: image.bestURLString)
                                .frame(width: 48, height: 48)
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
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button(collection.likedByMe == true ? "取消点赞" : "点赞", action: onLike)
                Spacer()
                Button(collection.favoritedByMe == true ? "取消收藏" : "收藏", action: onFavorite)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
    }
}
