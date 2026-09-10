import SetuIOSCore
import SwiftUI

struct DashboardView: View {
    @AppStorage("setu.images.blurPreviews") private var blurPreviews = true
    @State private var hasLoadedInitialContent = false
    @State private var initialLoadCount = 0
    @State private var lifetimeID = UUID()
    @Environment(\.brandSplashActive) private var brandSplashActive
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var favoritesState: LoadState<[FavoriteItem]> = .idle
    @State private var generationState: LoadState<AiGenerationJob?> = .idle
    @State private var recommendationState: LoadState<AiPublicWork?> = .idle
    @State private var notificationState: LoadState<Int> = .idle
    @State private var pointsState: LoadState<Int> = .idle
    @State private var favoritesLoadID = UUID()
    @State private var generationLoadID = UUID()
    @State private var recommendationLoadID = UUID()
    @State private var notificationLoadID = UUID()
    @State private var pointsLoadID = UUID()
    @State private var previewItem: UserImagePreviewItem?

    var body: some View {
        List {
            greetingSection
            continueSection
            favoritesSection
            if !blurPreviews { recommendationSection }
            remindersSection
        }
        .listStyle(.plain)
        .setuBackground()
        .accessibilityIdentifier("dashboard.page")
        .navigationTitle("首页")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SetuToolbarLogo(assetName: "HomeLogo", accessibilityLabel: "首页")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { navigation.navigate(to: .home, route: .notifications) } label: {
                    Image(systemName: hasUnreadNotifications ? "bell.badge" : "bell")
                }
                .accessibilityLabel("通知中心")
                .accessibilityIdentifier("dashboard.notifications")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.navigate(to: .home, route: .account)
                } label: {
                    HomeAccountAvatar(user: environment.authSession.currentUser)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我的")
            }
        }
        .sheet(item: $previewItem) { item in
            UserImagePreviewSheet(item: item)
        }
        .task {
            draft = AiDrawDraftStore.load()
            guard !hasLoadedInitialContent else { return }
            initialLoadCount += 1
            await load()
            if !Task.isCancelled { hasLoadedInitialContent = true }
        }
        .refreshable {
            await load()
        }
    }

    private var hasUnreadNotifications: Bool {
        if case .loaded(let count) = notificationState { return count > 0 }
        return false
    }

    private var greetingSection: some View {
        Section {
            SetuCard(padding: SetuSpacing.xl) {
                greetingCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .setuListRow()
    }

    private var continueSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "继续使用")

                    if let track = player.currentTrack {
                        SetuNavigationRow(
                            title: track.title,
                            subtitle: "继续播放 · \(track.artist)",
                            systemImage: "play.circle.fill"
                        ) {
                            navigation.navigate(to: .music)
                        }
                    }

                    switch generationState {
                    case .idle, .loading:
                        DashboardFieldLoading(title: "正在同步生成进度")
                    case .failed(let message):
                        DashboardFieldFailure(
                            title: "生成进度暂不可用",
                            message: message,
                            retryIdentifier: "dashboard.retry.generation"
                        ) {
                            Task { await loadGeneration() }
                        }
                    case .loaded(let job):
                        if let job {
                            SetuNavigationRow(
                                title: job.promptCn.nonEmpty ?? "正在生成作品",
                                subtitle: "\(job.statusTitle) · 查看最新进度",
                                systemImage: "sparkles"
                            ) {
                                navigation.navigate(to: .ai, route: .aiGenerationDetail(job.id))
                            }
                        }
                    }

                    if hasMeaningfulDraft {
                        SetuNavigationRow(
                            title: draft.promptCn.nonEmpty ?? "未完成的 AI 绘画草稿",
                            subtitle: "继续编辑上次保存的参数",
                            systemImage: "square.and.pencil"
                        ) {
                            navigation.navigate(to: .ai, reset: true)
                        }
                    }

                    if hasConfirmedNoActiveContent {
                        SetuEmptyState(
                            title: "暂无进行中的内容",
                            message: "描述一个画面，开始今天的第一幅作品。",
                            systemImage: "clock.arrow.circlepath",
                            actionTitle: "开始创作",
                            action: { navigation.navigate(to: .ai, reset: true) }
                        )
                    }
                }
            }
        }
        .setuListRow()
    }

    private var favoritesSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(
                        title: "最近收藏",
                        actionTitle: "查看全部"
                    ) {
                        navigation.navigate(to: .images, route: .favorites)
                    }

                    switch favoritesState {
                    case .idle, .loading:
                        DashboardFieldLoading(title: "正在加载最近收藏")
                    case .failed(let message):
                        DashboardFieldFailure(
                            title: "最近收藏加载失败",
                            message: message,
                            retryIdentifier: "dashboard.retry.favorites"
                        ) {
                            Task { await loadFavorites() }
                        }
                    case .loaded(let favorites) where favorites.isEmpty:
                        SetuEmptyState(
                            title: "还没有收藏图片",
                            message: "去图片页发现喜欢的作品吧。",
                            systemImage: "heart",
                            actionTitle: "发现图片",
                            action: { navigation.navigate(to: .images) }
                        )
                    case .loaded(let favorites):
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SetuSpacing.md) {
                                ForEach(favorites) { favorite in
                                    Button {
                                        previewItem = UserImagePreviewItem(favorite: favorite)
                                    } label: {
                                        FavoritePreviewTile(item: favorite)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("查看收藏：\(favorite.image?.title.nonEmpty ?? "未命名作品")")
                                    .accessibilityIdentifier("dashboard.favorite.\(favorite.id)")
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboard.section.favorites")
        }
        .setuListRow()
    }

    @ViewBuilder
    private var recommendationSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "今日推荐")
                    switch recommendationState {
                    case .idle, .loading:
                        DashboardFieldLoading(title: "正在挑选今日推荐")
                    case .failed(let message):
                        DashboardFieldFailure(
                            title: "今日推荐加载失败",
                            message: message,
                            retryIdentifier: "dashboard.retry.recommendation"
                        ) {
                            Task { await loadRecommendation() }
                        }
                    case .loaded(nil):
                        SetuEmptyState(
                            title: "今天暂时没有推荐",
                            message: "稍后回来看看新的广场作品。",
                            systemImage: "sparkles"
                        )
                    case .loaded(let recommendation?):
                        Button {
                            navigation.navigate(
                                to: .more,
                                route: .publicAiWork(PublicAiWorkSnapshot(work: recommendation))
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuRemoteImage(
                                    urlString: recommendation.imageUrl,
                                    accessibilityLabel: "今日推荐 AI 作品",
                                    width: nil,
                                    height: nil,
                                    cornerRadius: SetuRadius.md,
                                    contentMode: .fill,
                                    allowsTapToRetry: false
                                )
                                .frame(maxWidth: .infinity)
                                .aspectRatio(16 / 10, contentMode: .fit)

                                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                    Text(recommendation.promptCn.nonEmpty ?? "广场精选作品")
                                        .font(SetuTypography.headline)
                                        .foregroundStyle(SetuColor.textPrimary)
                                        .lineLimit(2)
                                    Text("来自 AI 广场 · 点按查看作品")
                                        .font(SetuTypography.caption)
                                        .foregroundStyle(SetuColor.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看今日推荐作品")
                    }
                }
            }
        }
        .setuListRow()
    }

    private var remindersSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "提醒")
                    notificationReminderContent
                    pointsReminderContent

                    if remindersAreConfirmedClear {
                        Label("暂时没有需要处理的事项", systemImage: "checkmark.circle.fill")
                            .font(SetuTypography.body)
                            .foregroundStyle(SetuColor.success)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboard.section.reminders")
        }
        .setuListRow()
    }

    @ViewBuilder
    private var notificationReminderContent: some View {
        switch notificationState {
        case .idle, .loading:
            DashboardFieldLoading(title: "正在检查未读通知")
        case .failed(let message):
            DashboardFieldFailure(
                title: "通知状态加载失败",
                message: message,
                retryIdentifier: "dashboard.retry.notifications"
            ) {
                Task { await loadNotifications() }
            }
        case .loaded(let unread):
            if unread > 0 {
                SetuNavigationRow(
                    title: "有 \(unread) 条未读通知",
                    subtitle: "查看生成结果和处理进度",
                    systemImage: "bell.badge"
                ) {
                    navigation.navigate(to: .home, route: .notifications)
                }
            }
        }
    }

    @ViewBuilder
    private var pointsReminderContent: some View {
        switch pointsState {
        case .idle, .loading:
            DashboardFieldLoading(title: "正在检查积分余额")
        case .failed(let message):
            DashboardFieldFailure(
                title: "积分余额加载失败",
                message: message,
                retryIdentifier: "dashboard.retry.points"
            ) {
                Task { await loadPoints() }
            }
        case .loaded(let points):
            if points < 20 {
                SetuNavigationRow(
                    title: "积分余额较低",
                    subtitle: "当前剩余 \(points) 积分",
                    systemImage: "bolt.trianglebadge.exclamationmark"
                ) {
                    navigation.navigate(to: .images, route: .pointsLogs)
                }
            }
        }
    }

    @State private var draft = AiDrawDraft()

    private var greetingCopy: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            Text(greetingTitle)
                .anchorPreference(key: WelcomeLogoAnchorKey.self, value: .bounds) { EntryAnchors(greeting: HomeGreetingAnchor(bounds: $0, title: greetingTitle)) }
                .opacity(brandSplashActive ? 0 : 1)
                .font(SetuTypography.display)
                .foregroundStyle(SetuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(greetingSubtitle)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.greeting")
        .accessibilityValue(diagnosticLoadValue)
    }

    private var diagnosticLoadValue: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-player") {
            return "\(lifetimeID):loads=\(initialLoadCount)"
        }
        #endif
        return ""
    }

    private var hasMeaningfulDraft: Bool {
        let value = draft
        return !value.promptCn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !value.promptPositive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !value.styleTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !value.loraName.isEmpty
            || !value.characterId.isEmpty
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 5..<11: salutation = "早上好"
        case 11..<14: salutation = "中午好"
        case 14..<18: salutation = "下午好"
        default: salutation = "晚上好"
        }
        return "\(salutation)，\(displayName)"
    }

    private var greetingSubtitle: String {
        if player.currentTrack != nil || hasMeaningfulDraft {
            return "欢迎回来，从上次停下的地方继续吧。"
        }
        switch generationState {
        case .idle, .loading:
            return "欢迎回来，正在同步上次的创作进度。"
        case .failed:
            return "欢迎回来，部分首页内容暂时未能同步。"
        case .loaded(let job):
            return job == nil
                ? "今天想创作点什么，还是先看看新作品？"
                : "欢迎回来，从上次停下的地方继续吧。"
        }
    }

    private var displayName: String {
        let nickname = environment.authSession.currentUser?.nickname?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nickname.isEmpty { return nickname }
        return environment.authSession.currentUser?.email.split(separator: "@").first.map(String.init) ?? "朋友"
    }

    private var hasConfirmedNoActiveContent: Bool {
        guard player.currentTrack == nil, !hasMeaningfulDraft else { return false }
        if case .loaded(nil) = generationState { return true }
        return false
    }

    private var remindersAreConfirmedClear: Bool {
        guard case .loaded(let unread) = notificationState,
              case .loaded(let points) = pointsState else {
            return false
        }
        return unread == 0 && points >= 20
    }

    private func load() async {
        draft = AiDrawDraftStore.load()
        async let favorites: Void = loadFavorites()
        async let generation: Void = loadGeneration()
        async let recommendation: Void = loadRecommendation()
        async let notifications: Void = loadNotifications()
        async let points: Void = loadPoints()
        _ = await (favorites, generation, recommendation, notifications, points)
    }

    private func loadFavorites() async {
        let loadID = UUID()
        favoritesLoadID = loadID
        favoritesState = .loading
        do {
            let page = try await environment.favoriteClient.list(page: 1, size: 4)
            guard loadID == favoritesLoadID else { return }
            favoritesState = .loaded(page.items)
        } catch {
            guard loadID == favoritesLoadID else { return }
            favoritesState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func loadGeneration() async {
        let loadID = UUID()
        generationLoadID = loadID
        generationState = .loading
        do {
            let page = try await environment.aiGenerationClient.listMine(page: 1, pageSize: 5)
            guard loadID == generationLoadID else { return }
            let active = page.list.first { !["COMPLETED", "FAILED"].contains($0.status) }
            generationState = .loaded(active)
        } catch {
            guard loadID == generationLoadID else { return }
            generationState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func loadRecommendation() async {
        let loadID = UUID()
        recommendationLoadID = loadID
        recommendationState = .loading
        do {
            let page = try await environment.aiGenerationClient.square(page: 1, pageSize: 1)
            guard loadID == recommendationLoadID else { return }
            recommendationState = .loaded(page.list.first)
        } catch {
            guard loadID == recommendationLoadID else { return }
            recommendationState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func loadNotifications() async {
        let loadID = UUID()
        notificationLoadID = loadID
        notificationState = .loading
        do {
            let count = try await environment.dashboardClient.fetchUnreadNotificationCount()
            guard loadID == notificationLoadID else { return }
            notificationState = .loaded(count)
        } catch {
            guard loadID == notificationLoadID else { return }
            notificationState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func loadPoints() async {
        let loadID = UUID()
        pointsLoadID = loadID
        pointsState = .loading
        do {
            let balance = try await environment.dashboardClient.fetchPointsBalance()
            guard loadID == pointsLoadID else { return }
            pointsState = .loaded(balance.points)
        } catch {
            guard loadID == pointsLoadID else { return }
            pointsState = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

private struct DashboardFieldLoading: View {
    let title: String

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            ProgressView()
                .tint(SetuColor.brandPink)
                .accessibilityHidden(true)
            Text(title)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct DashboardFieldFailure: View {
    @State private var isExpanded = false
    let title: String
    let message: UserFacingError
    let retryIdentifier: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.danger)
                .fixedSize(horizontal: false, vertical: true)

            SetuErrorRecoveryButton(error: message, retry: retry)
                .tint(SetuColor.danger)
                .frame(minHeight: 44)
                .accessibilityIdentifier(retryIdentifier)

            Text(message.message)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if message.message.count > 40 {
                Button(isExpanded ? "收起详情" : "展开详情") { isExpanded.toggle() }
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SetuSpacing.md)
        .background(
            SetuColor.danger.opacity(0.08),
            in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
        )
    }
}

private struct FavoritePreviewTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: FavoriteItem

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            SetuRemoteImage(
                urlString: item.image?.urlSmall ?? item.image?.urlRegular,
                accessibilityLabel: "收藏图片：\(item.image?.title.nonEmpty ?? "未命名作品")",
                width: 136,
                height: 136,
                cornerRadius: SetuRadius.md,
                allowsTapToRetry: false
            )
            .modifier(ImagePreviewBlur())
            Text(item.image?.title.nonEmpty ?? "未命名作品")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 184 : 136, alignment: .leading)
    }
}

private struct HomeAccountAvatar: View {
    let user: CurrentUser?

    var body: some View {
        Group {
            if let urlString = user?.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay { Circle().stroke(borderColor, lineWidth: 0.5) }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Circle()
            .fill(SetuColor.surfaceMuted)
            .overlay {
                Image(systemName: user?.role == .admin ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(SetuColor.textSecondary)
            }
    }

    private var borderColor: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color.secondary.opacity(0.25)
        #endif
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
#Preview("首页 · 390 · 浅色") {
    SetuFeaturePreviewHost(playerState: .listening) { environment, player in
        DashboardView(environment: environment, player: player)
    }
    .frame(width: 390, height: 844)
    .preferredColorScheme(.light)
}
#endif
