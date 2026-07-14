import SetuIOSCore
import SwiftUI

struct PublicUserProfileView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    let userID: Int
    @State private var state: LoadState<PublicUserProfileContent> = .idle

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                PublicUserStateSection(title: "用户主页", stateTitle: "正在加载用户主页", systemImage: "person.crop.circle", isLoading: true)
            case .failed(let message):
                PublicUserStateSection(
                    title: "用户主页",
                    stateTitle: "用户主页加载失败",
                    message: message,
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    actionTitle: "重试",
                    action: { Task { await load() } }
                )
            case .loaded(let content):
                profileSection(content.profile)
                aiWorksSection(content.aiWorks, total: content.profile.publicAiWorkCount)
                collectionsSection(content.collections, total: content.profile.publicCollectionCount)
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("用户主页")
        .task { await load() }
        .refreshable { await load() }
    }

    private var aiGridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 156), spacing: SetuSpacing.md)]
    }

    private func load() async {
        state = .loading
        do {
            async let profile = environment.collectionClient.publicUserProfile(userID: userID)
            async let collections = environment.collectionClient.square(
                page: 1,
                size: 100,
                sort: "new",
                ownerID: userID
            )
            async let aiWorks = environment.aiGenerationClient.square(
                page: 1,
                pageSize: 100,
                ownerID: userID
            )
            state = .loaded(try await PublicUserProfileContent(
                profile: profile,
                collections: collections.list,
                aiWorks: aiWorks.list
            ))
        } catch {
            state = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func profileSection(_ profile: PublicUserProfile) -> some View {
        Section {
            SetuCard {
                HStack(alignment: .top, spacing: SetuSpacing.md) {
                    PublicUserAvatarView(urlString: profile.avatarUrl, name: displayName(profile))
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text(displayName(profile))
                            .font(SetuTypography.title)
                            .foregroundStyle(SetuColor.textPrimary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: SetuSpacing.sm) {
                                profilePills(profile)
                            }
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                profilePills(profile)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .setuListRow()
        }
    }

    @ViewBuilder
    private func profilePills(_ profile: PublicUserProfile) -> some View {
        SetuPill(
            text: "\(profile.publicAiWorkCount) 件 AI 作品",
            systemImage: "sparkles",
            tone: .brand
        )
        SetuPill(
            text: "\(profile.publicCollectionCount) 个收藏夹",
            systemImage: "rectangle.stack",
            tone: .info
        )
    }

    @ViewBuilder
    private func aiWorksSection(_ works: [AiPublicWork], total: Int) -> some View {
        if works.isEmpty {
            PublicUserStateSection(
                title: "公开 AI 作品",
                stateTitle: "暂无公开 AI 作品",
                message: "对方审核通过并公开的作品会显示在这里。",
                systemImage: "sparkles"
            )
        } else {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "公开 AI 作品", subtitle: sectionCountText(loaded: works.count, total: total, unit: "件"))
                        LazyVGrid(columns: aiGridColumns, spacing: SetuSpacing.md) {
                            ForEach(works) { work in
                                AiGenerationGridTile(
                                    work: work,
                                    footerTitle: SetuDateFormatter.string(from: work.createdAt)
                                ) {
                                    router.navigate(to: .publicAiWork(PublicAiWorkSnapshot(work: work)))
                                }
                            }
                        }
                    }
                }
                .setuListRow()
            }
        }
    }

    @ViewBuilder
    private func collectionsSection(_ collections: [CollectionInfo], total: Int) -> some View {
        if collections.isEmpty {
            PublicUserStateSection(
                title: "公开收藏夹",
                stateTitle: "暂无公开收藏夹",
                message: "对方分享到广场的收藏夹会显示在这里。",
                systemImage: "rectangle.stack"
            )
        } else {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "公开收藏夹", subtitle: sectionCountText(loaded: collections.count, total: total, unit: "个"))
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

    private func displayName(_ profile: PublicUserProfile) -> String {
        let name = profile.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "雪涼云用户" : name
    }

    private func sectionCountText(loaded: Int, total: Int, unit: String) -> String {
        loaded < total ? "最近 \(loaded) \(unit)，共 \(total) \(unit)" : "共 \(total) \(unit)"
    }
}

private struct PublicUserProfileContent {
    let profile: PublicUserProfile
    let collections: [CollectionInfo]
    let aiWorks: [AiPublicWork]
}

private struct PublicUserStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(
                        title: stateTitle,
                        message: message,
                        systemImage: systemImage,
                        isLoading: isLoading,
                        actionTitle: actionTitle,
                        action: action
                    )
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
                SetuRemoteImage(
                    urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString,
                    accessibilityLabel: "收藏夹「\(collection.name)」封面",
                    allowsTapToRetry: false
                )
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
                            SetuRemoteImage(
                                urlString: image.bestURLString,
                                accessibilityLabel: "收藏夹「\(collection.name)」中的预览图片",
                                width: 48,
                                height: 48,
                                allowsTapToRetry: false
                            )
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
        .accessibilityHidden(true)
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

#if DEBUG
#Preview("公开用户主页 · 390 · 深色 · AX3") {
    SetuFeaturePreviewHost { environment, _ in
        PublicUserProfileView(environment: environment, userID: 71)
    }
    .frame(width: 390, height: 844)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
