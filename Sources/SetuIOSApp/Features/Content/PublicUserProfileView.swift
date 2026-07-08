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
                PublicUserStateSection(title: "用户主页", stateTitle: "正在加载用户主页", systemImage: "person.crop.circle", isLoading: true)
            case .failed(let message):
                PublicUserStateSection(title: "用户主页", stateTitle: "用户主页加载失败", message: message, systemImage: "person.crop.circle.badge.exclamationmark")
            case .loaded(let collections):
                Section {
                    SetuCard {
                        HStack(spacing: SetuSpacing.md) {
                            PublicUserAvatarView(urlString: ownerAvatarURL, name: displayName)
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text(displayName)
                                    .font(SetuTypography.title)
                                    .foregroundStyle(SetuColor.textPrimary)
                                Text("用户 #\(userID)")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                                SetuPill(text: "\(collections.count) 个公开收藏夹", systemImage: "rectangle.stack", tone: .brand)
                            }
                            Spacer()
                        }
                    }
                    .setuListRow()
                }

                if collections.isEmpty {
                    PublicUserStateSection(title: "公开收藏夹", stateTitle: "该用户还没有公开收藏夹", systemImage: "rectangle.stack")
                } else {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "公开收藏夹")
                                VStack(spacing: 0) {
                                    ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                        Button {
                                            router.navigate(to: .publicCollectionDetail(collection.id))
                                        } label: {
                                            PublicUserCollectionRow(collection: collection)
                                        }
                                        .buttonStyle(.plain)

                                        if index < collections.count - 1 {
                                            Divider().overlay(SetuColor.separator)
                                        }
                                    }
                                }
                            }
                        }
                        .setuListRow()
                    }
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
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

private struct PublicUserStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
                }
            }
            .setuListRow()
        }
    }
}

private struct PublicUserCollectionRow: View {
    let collection: CollectionInfo

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
                    HStack(spacing: SetuSpacing.md) {
                        Label("\(collection.itemCount ?? 0)", systemImage: "photo")
                        Label("\(collection.shareViewCount ?? 0)", systemImage: "eye")
                        Label("\(collection.likeCount ?? collection.shareLikeCount ?? 0)", systemImage: "hand.thumbsup")
                    }
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textTertiary)
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
        }
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
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
            .fill(SetuColor.brandSoft.opacity(0.22))
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SetuColor.brandPink)
            }
    }
}
