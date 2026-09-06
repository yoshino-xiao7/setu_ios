import SetuIOSCore
import SwiftUI

struct PublicAiWorkDetailView: View {
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    let initialWork: PublicAiWorkSnapshot

    @State private var verifiedWork: PublicAiWorkSnapshot?
    @State private var isUnavailable = false
    @State private var feedback: SetuFeedback?
    @State private var feedbackAllowsRefresh = false
    @State private var isUpdatingInteraction = false
    @State private var imagePreview: UserImagePreviewItem?

    init(environment: AppEnvironment, work: PublicAiWorkSnapshot) {
        self.environment = environment
        initialWork = work
    }

    @ViewBuilder
    var body: some View {
        if isUnavailable {
            unavailableContent
        } else {
            detailContent
        }
    }

    private var detailContent: some View {
        SetuBoard {
            if let feedback {
                Section {
                    SetuFeedbackBanner(
                        feedback: feedback,
                        actionTitle: feedbackAllowsRefresh ? "重试" : nil,
                        action: feedbackAllowsRefresh ? { Task { await refreshWork() } } : nil
                    )
                }

            }
            artworkSection
            interactionSection
            inspirationSection
            creatorSection
            detailsSection
        }

        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .navigationTitle("公开作品")
        .setuActionDock {

            SetuPrimaryButton {
                reuseInspiration()
            } label: {
                Label("以此为灵感创作", systemImage: "wand.and.sparkles")
            }

        }
        .toolbar {
            if imageURL != nil {
                Button {
                    imagePreview = previewItem
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square")
                }
                .accessibilityLabel("保存或分享作品")
            }
        }
        .sheet(item: $imagePreview) { item in
            UserImagePreviewSheet(item: item)
        }
        .task(id: initialWork.id) { await refreshWork() }
        .refreshable { await refreshWork() }
    }

    private var unavailableContent: some View {
        ScrollView {
            SetuCard {
                VStack(spacing: SetuSpacing.lg) {
                    SetuEmptyState(
                        title: "作品已下架",
                        message: "这件公开作品已不可用，可能由创作者撤回或未通过公开审核。",
                        systemImage: "photo.on.rectangle.angled"
                    )
                    SetuPrimaryButton {
                        navigation.navigate(to: .ai, route: .aiSquare, reset: true)
                    } label: {
                        Label("返回 AI 广场", systemImage: "rectangle.stack")
                    }
                }
            }
            .padding(SetuSpacing.lg)
        }
        .setuBackground()
        .navigationTitle("公开作品")
    }

    private var artworkSection: some View {
        Section {
            SetuCard(padding: SetuSpacing.sm) {
                if let imageURL {
                    SetuRemoteImage(
                        urlString: imageURL.absoluteString,
                        accessibilityLabel: "公开 AI 作品：\(work.prompt)",
                        width: nil,
                        height: nil,
                        cornerRadius: SetuRadius.md,
                        contentMode: .fit,
                        onActivate: { imagePreview = previewItem },
                        activationHint: "打开后可保存到照片或使用系统分享"
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    SetuEmptyState(
                        title: "作品图片暂不可用",
                        message: "图片可能已过期，你仍可使用下方创作灵感开始新的作品。",
                        systemImage: "photo"
                    )
                    .frame(minHeight: 280)
                }
            }
        }

    }

    private var interactionSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "作品互动")
                    if isOwnWork {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: SetuSpacing.lg) {
                                interactionStat(title: "喜欢", count: work.likeCount, systemImage: "heart.fill")
                                interactionStat(title: "收藏", count: work.favoriteCount, systemImage: "bookmark.fill")
                            }
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                interactionStat(title: "喜欢", count: work.likeCount, systemImage: "heart.fill")
                                interactionStat(title: "收藏", count: work.favoriteCount, systemImage: "bookmark.fill")
                            }
                        }
                    } else {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: SetuSpacing.sm) {
                                interactionButtons
                            }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: SetuSpacing.sm) {
                                    interactionButtons
                                }
                                VStack(spacing: SetuSpacing.sm) {
                                    interactionButtons
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    @ViewBuilder
    private var interactionButtons: some View {
        Button {
            Task { await setLiked(!work.likedByMe) }
        } label: {
            HStack {
                Image(systemName: work.likedByMe ? "heart.fill" : "heart")
                    .accessibilityHidden(true)
                Text("喜欢 \(work.likeCount)")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(SetuColor.brandPink)
        .disabled(isUpdatingInteraction)
        .accessibilityLabel(work.likedByMe ? "取消喜欢，当前 \(work.likeCount) 人喜欢" : "喜欢作品，当前 \(work.likeCount) 人喜欢")
        .accessibilityIdentifier("ai.public.like")

        Button {
            Task { await setFavorited(!work.favoritedByMe) }
        } label: {
            HStack {
                Image(systemName: work.favoritedByMe ? "bookmark.fill" : "bookmark")
                    .accessibilityHidden(true)
                Text("收藏 \(work.favoriteCount)")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(SetuColor.brandPink)
        .disabled(isUpdatingInteraction)
        .accessibilityLabel(work.favoritedByMe ? "取消收藏，当前 \(work.favoriteCount) 人收藏" : "收藏作品，当前 \(work.favoriteCount) 人收藏")
        .accessibilityIdentifier("ai.public.favorite")
    }

    private func interactionStat(title: String, count: Int, systemImage: String) -> some View {
        Label("\(title) \(count)", systemImage: systemImage)
            .font(SetuTypography.body)
            .foregroundStyle(SetuColor.textPrimary)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private var creatorSection: some View {
        if let ownerUserID = work.ownerUserID {
            Section {
                SetuCard {
                    SetuNavigationRow(
                        title: "查看创作者主页",
                        subtitle: "查看对方公开分享的作品与收藏夹",
                        systemImage: "person.crop.circle"
                    ) {
                        navigation.navigate(to: .square, route: .publicUserProfile(ownerUserID))
                    }
                }
            }

        }
    }

    private var inspirationSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "创作灵感")
                    Text(work.prompt)
                        .font(.body)
                        .foregroundStyle(SetuColor.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }

    }

    private var detailsSection: some View {
        let parameters = [AiDetailParameter(title: "画幅", value: "\(work.width) × \(work.height)")]
        return VStack(alignment: .leading, spacing: SetuSpacing.lg) {
            SetuBento(items: parameters, span: { _ in .wide }) { parameter in
                SetuRecordCard(headline: parameter.title, fields: [.init("尺寸", parameter.value)])
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("画幅")
                    .accessibilityValue(parameter.value)
                    .accessibilityIdentifier("ai.public.dimensions")
            }
            if let createdAt = work.createdAt, !createdAt.isEmpty {
                SetuCard {
                    SetuTimeline(events: [
                        .init(
                            id: "published", title: "发布时间",
                            timestamp: SetuDateFormatter.string(from: createdAt, style: .full), tone: .success, isCurrent: true)
                    ])
                }
            }
            if work.category == "R18" {
                SetuPill(text: "成人内容", systemImage: "eye.slash", tone: .danger)
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(SetuColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
        } else {
            LabeledContent(title, value: value)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
    }

    private var imageURL: URL? {
        work.imageURLString.flatMap(URL.init(string:))
    }

    private var work: PublicAiWorkSnapshot {
        verifiedWork ?? initialWork
    }

    private var isOwnWork: Bool {
        work.ownerUserID == environment.authSession.currentUser?.id
    }

    private var previewItem: UserImagePreviewItem {
        UserImagePreviewItem(
            id: "public-ai-\(work.id)",
            title: work.prompt,
            author: "公开作品创作者",
            width: work.width,
            height: work.height,
            r18: work.category == "R18",
            displayURLString: work.imageURLString,
            originalURLString: work.imageURLString
        )
    }

    private func reuseInspiration() {
        AiDrawDraftStore.save(AiDrawDraft(
            promptCn: work.prompt,
            width: work.width,
            height: work.height,
            negativePrompt: AiDrawDefaults.defaultNegativePrompt,
            source: "history",
            updatedAt: Date()
        ))
        navigation.navigate(to: .ai, route: .aiDraw)
    }

    @MainActor
    private func refreshWork() async {
        do {
            let current = try await environment.aiGenerationClient.squareDetail(id: initialWork.id)
            verifiedWork = PublicAiWorkSnapshot(work: current)
            feedback = nil
            feedbackAllowsRefresh = false
            isUnavailable = false
        } catch {
            switch PublicAiWorkRefreshPolicy.resolve(
                error,
                hasVerifiedServerCopy: verifiedWork != nil
            ) {
            case .markUnavailable:
                verifiedWork = nil
                imagePreview = nil
                feedback = nil
                feedbackAllowsRefresh = false
                isUnavailable = true
            case .keepSnapshot:
                feedback = .warning("暂时无法确认作品的最新公开状态，当前显示的是广场中的内容。")
                feedbackAllowsRefresh = true
                isUnavailable = false
            }
        }
    }

    @MainActor
    private func setLiked(_ liked: Bool) async {
        guard !isUpdatingInteraction else { return }
        isUpdatingInteraction = true
        defer { isUpdatingInteraction = false }
        do {
            let updated = try await environment.aiGenerationClient.setSquareLiked(id: work.id, liked: liked)
            verifiedWork = PublicAiWorkSnapshot(work: updated)
            feedback = nil
            feedbackAllowsRefresh = false
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
            feedbackAllowsRefresh = false
        }
    }

    @MainActor
    private func setFavorited(_ favorited: Bool) async {
        guard !isUpdatingInteraction else { return }
        isUpdatingInteraction = true
        defer { isUpdatingInteraction = false }
        do {
            let updated = try await environment.aiGenerationClient.setSquareFavorited(id: work.id, favorited: favorited)
            verifiedWork = PublicAiWorkSnapshot(work: updated)
            feedback = nil
            feedbackAllowsRefresh = false
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
            feedbackAllowsRefresh = false
        }
    }
}

enum PublicAiWorkRefreshPolicy {
    enum Decision: Equatable {
        case keepSnapshot
        case markUnavailable
    }

    static func resolve(_ error: Error, hasVerifiedServerCopy: Bool) -> Decision {
        guard hasVerifiedServerCopy,
              case APIError.httpStatus(let status, _, _, _, _) = error,
              status == 403 || status == 404 else {
            return .keepSnapshot
        }
        return .markUnavailable
    }
}

#if DEBUG
#Preview("公开 AI 作品 · 390 · AX3") {
    SetuFeaturePreviewHost { environment, _ in
        PublicAiWorkDetailView(
            environment: environment,
            work: PublicAiWorkSnapshot(
                id: 601,
                ownerUserID: 71,
                imageURLString: nil,
                prompt: "粉色云层下的夏日列车，柔和逆光与安静站台",
                width: 768,
                height: 1024,
                category: "GENERAL",
                createdAt: "2026-07-10T08:30:00+08:00",
                likeCount: 128,
                favoriteCount: 42,
                likedByMe: true,
                favoritedByMe: false
            )
        )
    }
    .frame(width: 390, height: 844)
    .preferredColorScheme(.light)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
