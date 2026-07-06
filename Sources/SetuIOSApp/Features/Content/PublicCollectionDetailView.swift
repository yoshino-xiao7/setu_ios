import SetuIOSCore
import SwiftUI

struct PublicCollectionDetailView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let collectionID: Int

    @State private var infoState: LoadState<CollectionInfo> = .idle
    @State private var itemsState: LoadState<CollectionItemPage> = .idle
    @State private var actionMessage: String?

    var body: some View {
        List {
            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            switch infoState {
            case .idle, .loading:
                ProgressView("正在加载公开收藏夹")
            case .failed(let message):
                ContentUnavailableView("公开收藏夹加载失败", systemImage: "rectangle.stack.badge.minus", description: Text(message))
            case .loaded(let info):
                headerSection(info)
                publicActionSection(info)
            }

            switch itemsState {
            case .idle, .loading:
                ProgressView("正在加载图片")
            case .failed(let message):
                ContentUnavailableView("图片加载失败", systemImage: "photo.on.rectangle.angled", description: Text(message))
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentUnavailableView("暂无图片", systemImage: "photo")
                } else {
                    Section("共 \(page.total) 张") {
                        ForEach(page.items) { item in
                            PublicCollectionImageRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
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
        Section {
            HStack(alignment: .top, spacing: 12) {
                ImageThumbnailView(urlString: info.coverUrl ?? info.previewImages?.first?.bestURLString)
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.name)
                        .font(.headline)
                    if let description = info.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        router.navigate(to: .publicUserProfile(info.userId))
                    } label: {
                        Label(info.ownerNickname ?? "用户#\(info.userId)", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.borderless)
                    HStack(spacing: 10) {
                        Label("\(info.itemCount ?? 0) 张", systemImage: "photo")
                        Label("\(info.shareViewCount ?? 0)", systemImage: "eye")
                        Label("\(info.likeCount ?? info.shareLikeCount ?? 0)", systemImage: "hand.thumbsup")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let tags = info.tags, !tags.isEmpty {
                TagFlow(tags: tags)
            }

            if let note = info.curatorNote, !note.isEmpty {
                LabeledContent("推荐语", value: note)
            }
        }
    }

    private func publicActionSection(_ info: CollectionInfo) -> some View {
        Section {
            Button {
                Task { await like(info) }
            } label: {
                Label(info.likedByMe == true ? "取消点赞" : "点赞", systemImage: "hand.thumbsup")
            }

            Button {
                Task { await favorite(info) }
            } label: {
                Label(info.favoritedByMe == true ? "取消收藏" : "收藏", systemImage: "star")
            }
        }
    }

    private func load() async {
        actionMessage = nil
        infoState = .loading
        itemsState = .loading
        do {
            async let info = environment.collectionClient.squareDetail(id: collectionID)
            async let items = environment.collectionClient.items(collectionID: collectionID)
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

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: item.image?.urlSmall ?? item.image?.urlRegular ?? item.image?.urlOriginal)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.image?.title ?? "PID \(item.pid)")
                    .font(.headline)
                    .lineLimit(2)
                Text(item.image?.author ?? "未知作者")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.p)", systemImage: "number")
                    if let image = item.image {
                        Label("\(image.width)x\(image.height)", systemImage: "aspectratio")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
