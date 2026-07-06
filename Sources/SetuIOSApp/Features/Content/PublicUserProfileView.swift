import SetuIOSCore
import SwiftUI

struct PublicUserProfileView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let userID: Int
    @State private var state: LoadState<[CollectionInfo]> = .idle
    @State private var ownerName = ""
    @State private var ownerAvatarURL: String?

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("用户主页加载失败", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(message))
            case .loaded(let collections):
                Section {
                    HStack(spacing: 14) {
                        PublicUserAvatarView(urlString: ownerAvatarURL, name: displayName)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName)
                                .font(.headline)
                            Text("用户 #\(userID)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Label("\(collections.count) 个公开收藏夹", systemImage: "rectangle.stack")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if collections.isEmpty {
                    ContentUnavailableView("该用户还没有公开收藏夹", systemImage: "rectangle.stack")
                } else {
                    Section("公开收藏夹") {
                        ForEach(collections) { collection in
                            Button {
                                router.navigate(to: .publicCollectionDetail(collection.id))
                            } label: {
                                PublicUserCollectionRow(collection: collection)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("用户主页")
        .task { await load() }
        .refreshable { await load() }
    }

    private var displayName: String {
        ownerName.isEmpty ? "用户#\(userID)" : ownerName
    }

    private func load() async {
        state = .loading
        do {
            let page = try await environment.collectionClient.square(page: 1, size: 100, sort: "hot")
            let userCollections = page.list.filter { $0.userId == userID }
            if let owner = userCollections.first ?? page.list.first(where: { $0.userId == userID }) {
                ownerName = owner.ownerNickname ?? "用户#\(userID)"
                ownerAvatarURL = owner.ownerAvatarUrl
            }
            state = .loaded(userCollections)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct PublicUserCollectionRow: View {
    let collection: CollectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ImageThumbnailView(urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString)
                VStack(alignment: .leading, spacing: 5) {
                    Text(collection.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let description = collection.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 12) {
                        Label("\(collection.itemCount ?? 0)", systemImage: "photo")
                        Label("\(collection.shareViewCount ?? 0)", systemImage: "eye")
                        Label("\(collection.likeCount ?? collection.shareLikeCount ?? 0)", systemImage: "hand.thumbsup")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .padding(.vertical, 4)
    }
}

private struct PublicUserAvatarView: View {
    let urlString: String?
    let name: String

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(.pink.opacity(0.14))
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.pink)
            }
    }
}
