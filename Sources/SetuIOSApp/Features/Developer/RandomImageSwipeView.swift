import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct RandomImageSwipeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var environment: AppEnvironment

    @State private var imageState: LoadState<ImageFeedCard> = .idle
    @State private var currentCard: ImageFeedCard?
    @State private var feedQueue: [ImageFeedCard] = []
    @State private var unlockedItems: [String: SetuImageItem] = [:]
    @State private var unlockingTokens: Set<String> = []
    @State private var activePrefetchID: UUID?
    @State private var feedGeneration = 0
    @State private var r18 = 0
    @State private var keyword = ""
    @State private var tagText = ""
    @State private var aspectRatio = ""
    @State private var excludeAI = true
    @State private var feedback: SetuFeedback?
    @State private var feedbackAction: UserFacingErrorAction?
    @State private var showingParameters = false
    @State private var dragOffset = CGSize.zero
    @State private var balance: Int?
    @State private var costPerImage = 20
    @State private var showingUnlockConfirmation = false
    @State private var favoriteStates: [String: LoadState<Bool>] = [:]
    @State private var favoriteStatusLoadIDs: [String: UUID] = [:]
    @State private var favoriteLoadingKeys: Set<String> = []
    @State private var collectionTarget: ImageCollectionReference?
    @State private var originalPreviewItem: UserImagePreviewItem?

    private let preloadLimit = 10
    private let refillThreshold = 3
    private let noMatchingImagesMessage = "当前筛选条件没有匹配图片"

    var body: some View {
        ZStack {
            SetuColor.pageGradient
                .ignoresSafeArea()

            VStack(spacing: SetuSpacing.md) {
                statusStrip
                if let feedback {
                    VStack(spacing: SetuSpacing.sm) {
                        SetuFeedbackBanner(feedback: feedback)
                        if feedbackAction == .viewPoints {
                            Button("查看积分获取方式") {
                                router.navigate(to: .pointsLogs)
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                        }
                    }
                }
                imageStage
                actionBar
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.bottom, SetuSpacing.sm)
        }
        .navigationTitle("随机图片")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingParameters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(hasActiveImageMutation)
                .accessibilityLabel("调整找图设置")
                Menu {
                    Button {
                        router.navigate(to: .points)
                    } label: {
                        Label("高级找图设置", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        router.navigate(to: .pointsLogs)
                    } label: {
                        Label("积分明细", systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        router.navigate(to: .galleryUploads)
                    } label: {
                        Label("图库投稿", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        router.navigate(to: .imageDeleteRequests)
                    } label: {
                        Label("我的删除申请", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(hasActiveImageMutation)
                .accessibilityLabel("更多图片操作")
            }
        }
        .sheet(isPresented: $showingParameters) {
            RandomImageParameterSheet(
                initialParameters: currentParameters
            ) { parameters in
                applyParameters(parameters)
            }
        }
        .sheet(item: $collectionTarget) { target in
            RandomImageCollectionSheet(environment: environment, target: target) { result, savedToDefault in
                present(.success(result))
                if savedToDefault {
                    favoriteStatusLoadIDs[target.imageKey] = UUID()
                    favoriteStates[target.imageKey] = .loaded(true)
                }
            }
        }
        .sheet(item: $originalPreviewItem) { item in
            UserImagePreviewSheet(item: item)
        }
        .task {
            let generation = feedGeneration
            await loadBalance(expectedGeneration: generation)
            guard generation == feedGeneration else { return }
            await prefetchIfNeeded(force: true, expectedGeneration: generation)
            guard generation == feedGeneration else { return }
            if currentCard == nil {
                await loadNextImage(reason: "预览已准备好", expectedGeneration: generation)
            }
        }
        .refreshable {
            await reloadFromParameters()
        }
        .alert(
            unlockConfirmationTitle,
            isPresented: $showingUnlockConfirmation,
        ) {
            if hasEnoughPoints {
                Button("查看高清图 · \(costPerImage) 积分") {
                    Task { await openOriginal() }
                }
                .accessibilityIdentifier("image.unlock.confirm")
            } else {
                Button("查看积分明细") {
                    router.navigate(to: .pointsLogs)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("低清预览免费。当前余额：\(balanceText)；同一张图片重复查看不会再次扣分。")
        }
    }

    private var statusStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SetuSpacing.md) {
                statusStripContent
            }
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                statusStripContent
            }
        }
        .font(.footnote)
        .foregroundStyle(SetuColor.textSecondary)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前余额 \(balanceText)，高清图每张 \(costPerImage) 积分，预览免费")
    }

    @ViewBuilder
    private var statusStripContent: some View {
        Label(balanceText, systemImage: "bolt.circle")
        Label("高清 \(costPerImage) 积分", systemImage: "tag")
        if isCurrentUnlocking {
            Label("正在解锁", systemImage: "lock.open")
        } else if isCurrentUnlocked {
            Label("已解锁", systemImage: "checkmark.circle")
        } else {
            Label("预览免费", systemImage: "eye")
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: SetuRadius.lg)
                    .fill(SetuColor.surfaceMuted)

                switch imageState {
                case .idle where currentCard == nil:
                    loadingPlaceholder
                case .loading where currentCard == nil:
                    loadingPlaceholder
                case .failed(let text) where currentCard == nil:
                    if text == noMatchingImagesMessage {
                        SetuEmptyState(
                            title: "没有匹配图片",
                            message: "试试减少关键词或标签，或调整内容与画幅设置。",
                            systemImage: "slider.horizontal.3",
                            actionTitle: "调整筛选条件"
                        ) {
                            showingParameters = true
                        }
                        .accessibilityIdentifier("image.empty.no-match")
                    } else {
                        SetuEmptyState(title: "图片加载失败", message: text, systemImage: "photo.on.rectangle")
                    }
                default:
                    if let currentCard {
                        RandomImageCard(
                            card: currentCard,
                            unlockedItem: unlockedItems[currentCard.token],
                            stageSize: proxy.size
                        )
                    } else {
                        SetuEmptyState(title: "暂无图片", systemImage: "photo.on.rectangle")
                    }
                }

                if isLoadingImage && currentCard != nil {
                    floatingStatus(systemImage: "arrow.triangle.2.circlepath", title: "正在切换")
                } else if isCurrentUnlocking {
                    floatingStatus(systemImage: "lock.open", title: "正在解锁")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                    .stroke(SetuColor.separator, lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                if let currentCard,
                   currentCard.hasDisplayableURL(unlockedItem: unlockedItems[currentCard.token]) {
                    imageMetadataOverlay(currentCard)
                        .accessibilityIdentifier("image.metadata.overlay")
                }
            }
            .offset(dragOffset)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if !hasActiveImageMutation {
                            dragOffset = CGSize(
                                width: value.translation.width * 0.18,
                                height: value.translation.height * 0.18
                            )
                        }
                    }
                    .onEnded { value in
                        guard !hasActiveImageMutation else {
                            dragOffset = .zero
                            return
                        }
                        let distance = max(abs(value.translation.width), abs(value.translation.height))
                        let reason = swipeReason(for: value.translation)
                        dragOffset = .zero
                        if distance > 70 {
                            playSwipeFeedback()
                            let generation = feedGeneration
                            Task { await loadNextImage(reason: reason, expectedGeneration: generation) }
                        }
                    }
            )
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(SetuColor.brandPink)
            Text(isPrefetching ? "正在预加载图片" : "正在准备图片")
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
        }
    }

    private func floatingStatus(systemImage: String, title: String) -> some View {
        VStack(spacing: 6) {
            ProgressView()
                .tint(SetuColor.brandPink)
            Label(title, systemImage: systemImage)
                .font(.caption)
        }
        .padding(12)
        .background(.thinMaterial, in: Capsule())
    }

    private var actionBar: some View {
        VStack(spacing: SetuSpacing.sm) {
            Button {
                if isCurrentUnlocked {
                    Task { await openOriginal() }
                } else {
                    showingUnlockConfirmation = true
                }
            } label: {
                Label(
                    isCurrentUnlocked ? "查看高清图" : "查看高清图 · \(costPerImage) 积分",
                    systemImage: isCurrentUnlocked ? "lock.open" : "lock"
                )
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(currentCard == nil || hasActiveImageMutation)
            .buttonStyle(.borderedProminent)
            .tint(SetuColor.gradientTop)
            .accessibilityHint("低清预览免费，确认后才会消费积分")
            .accessibilityIdentifier("image.unlock")

            HStack(spacing: SetuSpacing.sm) {
                Button {
                    Task { await handleFavoriteAction() }
                } label: {
                    VStack(spacing: SetuSpacing.xs) {
                        Image(systemName: currentFavoriteButtonSystemImage)
                        Text(currentFavoriteButtonTitle)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .disabled(!canUseCurrentFavoriteAction)
                .accessibilityIdentifier("image.favorite")
                .accessibilityHint(currentFavoriteAccessibilityHint)

                Button {
                    if let currentCard {
                        collectionTarget = ImageCollectionReference(card: currentCard)
                    }
                } label: {
                    VStack(spacing: SetuSpacing.xs) {
                        Image(systemName: "folder.badge.plus")
                        Text("收藏夹")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .disabled(currentCard == nil || hasActiveImageMutation)

                Button {
                    let generation = feedGeneration
                    Task {
                        await loadNextImage(
                            reason: "已换到下一张图片，预览免费",
                            expectedGeneration: generation
                        )
                    }
                } label: {
                    VStack(spacing: SetuSpacing.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("下一张")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingImage || hasActiveImageMutation)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SetuSpacing.sm)
        .padding(.horizontal, SetuSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private func imageMetadataOverlay(_ card: ImageFeedCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: card))
                        .font(.headline)
                        .lineLimit(2)
                    Text(author(for: card))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.86))
                }
                Spacer()
                if r18Value(for: card) {
                    SetuPill(text: "成人内容", tone: .danger)
                }
                SetuPill(text: unlockedItems[card.token] == nil ? "预览" : "已解锁", tone: unlockedItems[card.token] == nil ? .muted : .success)
            }

            HStack(spacing: 10) {
                Label("\(width(for: card))x\(height(for: card))", systemImage: "aspectratio")
                if let firstTag = tags(for: card).first {
                    Label(firstTag, systemImage: "tag")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(SetuSpacing.md)
        .background(.ultraThinMaterial)
    }

    private var balanceText: String {
        balance.map { "\($0) 积分" } ?? "积分加载中"
    }

    private var hasEnoughPoints: Bool {
        guard let balance else { return true }
        return balance >= costPerImage
    }

    private var unlockConfirmationTitle: String {
        hasEnoughPoints ? "确认查看高清图？" : "积分不足"
    }

    private var isLoadingImage: Bool {
        if case .loading = imageState {
            return true
        }
        return false
    }

    private var isCurrentUnlocked: Bool {
        guard let token = currentCard?.token else { return false }
        return unlockedItems[token] != nil
    }

    private var isCurrentUnlocking: Bool {
        guard let token = currentCard?.token else { return false }
        return unlockingTokens.contains(token)
    }

    private var hasActiveImageMutation: Bool {
        !unlockingTokens.isEmpty || !favoriteLoadingKeys.isEmpty
    }

    private var parsedTags: [String] {
        tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var normalizedKeyword: String? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedAspectRatio: String? {
        aspectRatio.isEmpty ? nil : aspectRatio
    }

    private var currentParameters: RandomImageParameters {
        RandomImageParameters(
            r18: r18,
            keyword: keyword,
            tagText: tagText,
            aspectRatio: aspectRatio,
            excludeAI: excludeAI
        )
    }

    private func loadBalance(expectedGeneration: Int? = nil) async {
        let generation = expectedGeneration ?? feedGeneration
        do {
            let points = try await environment.pointsClient.balance().points
            guard generation == feedGeneration else { return }
            balance = points
        } catch {
            guard generation == feedGeneration else { return }
            balance = nil
        }
    }

    private func reloadFromParameters() async {
        guard let generation = beginReload() else { return }
        await completeReload(generation: generation)
    }

    private func applyParameters(_ parameters: RandomImageParameters) {
        guard !hasActiveImageMutation else {
            showingParameters = false
            present(.warning("请等待当前操作完成后再调整筛选"))
            return
        }

        r18 = parameters.r18
        keyword = parameters.keyword
        tagText = parameters.tagText
        aspectRatio = parameters.aspectRatio
        excludeAI = parameters.excludeAI
        showingParameters = false

        guard let generation = beginReload() else { return }
        Task { await completeReload(generation: generation) }
    }

    private func beginReload() -> Int? {
        guard !hasActiveImageMutation else {
            present(.warning("请等待当前操作完成后再刷新图片"))
            return nil
        }

        feedGeneration += 1
        activePrefetchID = nil
        currentCard = nil
        feedQueue = []
        unlockedItems = [:]
        favoriteStates = [:]
        favoriteStatusLoadIDs = [:]
        imageState = .loading
        feedback = nil
        feedbackAction = nil
        let generation = feedGeneration
        return generation
    }

    private func completeReload(generation: Int) async {
        guard generation == feedGeneration else { return }
        await loadBalance(expectedGeneration: generation)
        guard generation == feedGeneration else { return }
        await prefetchIfNeeded(force: true, expectedGeneration: generation)
        guard generation == feedGeneration, !feedQueue.isEmpty else { return }
        imageState = .idle
        await loadNextImage(reason: "已应用参数", expectedGeneration: generation)
    }

    private func loadNextImage(reason: String, expectedGeneration: Int? = nil) async {
        let generation = expectedGeneration ?? feedGeneration
        guard generation == feedGeneration else { return }
        guard !isLoadingImage else { return }
        if feedQueue.isEmpty, isPrefetching {
            present(.info("正在预加载下一批图片"))
            return
        }

        if feedQueue.isEmpty {
            imageState = currentCard.map { .loaded($0) } ?? .loading
            await prefetchIfNeeded(force: true, expectedGeneration: generation)
            guard generation == feedGeneration else { return }
        }

        guard !feedQueue.isEmpty else {
            if let currentCard {
                imageState = .loaded(currentCard)
            } else if case .failed = imageState {
                // Keep the precise network or empty-result state published by prefetch.
            } else {
                imageState = .failed(noMatchingImagesMessage)
            }
            return
        }

        let next = feedQueue.removeFirst()
        let favoriteKey = imageKey(for: next)
        favoriteStates[favoriteKey] = .loading
        currentCard = next
        imageState = .loaded(next)
        present(.info(reason))
        Task { await refreshFavoriteStatus(for: next, expectedGeneration: generation) }
        if feedQueue.count <= refillThreshold {
            Task { await prefetchIfNeeded(expectedGeneration: generation) }
        }
    }

    private func prefetchIfNeeded(
        force: Bool = false,
        expectedGeneration: Int? = nil
    ) async {
        let generation = expectedGeneration ?? feedGeneration
        guard generation == feedGeneration else { return }
        guard activePrefetchID == nil else { return }
        guard force || feedQueue.count <= refillThreshold else { return }

        let requestID = UUID()
        let request = ImageFeedRequest(
            r18: r18,
            limit: preloadLimit,
            keyword: normalizedKeyword,
            tags: parsedTags,
            excludeAI: excludeAI,
            aspectRatio: normalizedAspectRatio,
            source: nil
        )
        activePrefetchID = requestID
        defer {
            if activePrefetchID == requestID {
                activePrefetchID = nil
            }
        }

        do {
            let response = try await environment.imageFeedClient.feed(request)
            guard generation == feedGeneration, activePrefetchID == requestID else { return }
            costPerImage = response.costPerImage
            balance = response.balance
            let cards = response.items.map { ImageFeedCard(feedID: response.feedId, preview: $0) }
            feedQueue.append(contentsOf: cards)
            if cards.isEmpty {
                if currentCard == nil {
                    imageState = .failed(noMatchingImagesMessage)
                }
                present(.info(noMatchingImagesMessage))
            }
        } catch {
            guard generation == feedGeneration, activePrefetchID == requestID else { return }
            if currentCard == nil {
                imageState = .failed(UserFacingErrorMapper.map(error).message)
            }
            present(error)
        }
    }

    @discardableResult
    private func unlock(card: ImageFeedCard, trigger: ImageUnlockTrigger, showSuccess: Bool) async -> SetuImageItem? {
        if let item = unlockedItems[card.token] {
            return item
        }
        guard ImageUnlockPolicy.shouldConsume(trigger: trigger, isAlreadyUnlocked: false) else {
            return nil
        }
        guard !unlockingTokens.contains(card.token) else {
            return nil
        }

        unlockingTokens.insert(card.token)
        defer {
            unlockingTokens.remove(card.token)
        }

        do {
            let response = try await environment.imageFeedClient.consume(
                feedID: card.feedID,
                token: card.token,
                reason: "open_original"
            )
            unlockedItems[card.token] = response.item
            balance = response.balance
            if currentCard?.token == card.token {
                imageState = .loaded(card)
            }
            if showSuccess {
                present(.success(response.charged ? "已解锁，消耗 \(response.cost) 积分" : "已解锁，未重复扣分"))
            }
            return response.item
        } catch {
            if currentCard?.token == card.token {
                present(error)
            }
            return nil
        }
    }

    private func openOriginal() async {
        guard let currentCard else {
            present(.warning("当前没有可打开的图片"))
            return
        }
        guard !isCurrentUnlocking else { return }
        let item = await unlock(card: currentCard, trigger: .userRequestedHighResolution, showSuccess: true)
        guard let item else { return }
        originalPreviewItem = UserImagePreviewItem(image: item)
    }

    private var currentFavoriteState: LoadState<Bool> {
        guard let currentCard else { return .idle }
        return favoriteStates[imageKey(for: currentCard)] ?? .idle
    }

    private var isPrefetching: Bool {
        activePrefetchID != nil
    }

    private var isCurrentFavoriteLoading: Bool {
        guard let currentCard else { return false }
        return favoriteLoadingKeys.contains(imageKey(for: currentCard))
    }

    private func refreshFavoriteStatus(
        for card: ImageFeedCard,
        expectedGeneration: Int? = nil
    ) async {
        let generation = expectedGeneration ?? feedGeneration
        guard generation == feedGeneration else { return }
        let key = imageKey(for: card)
        let loadID = UUID()
        favoriteStatusLoadIDs[key] = loadID
        favoriteStates[key] = .loading
        do {
            let isFavorited = try await environment.favoriteClient.exists(pid: card.preview.pid, p: card.preview.page)
            guard generation == feedGeneration,
                  favoriteStatusLoadIDs[key] == loadID else { return }
            favoriteStates[key] = .loaded(isFavorited)
        } catch {
            guard generation == feedGeneration,
                  favoriteStatusLoadIDs[key] == loadID else { return }
            favoriteStates[key] = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func handleFavoriteAction() async {
        guard let currentCard else { return }
        switch currentFavoriteState {
        case .failed:
            await refreshFavoriteStatus(for: currentCard, expectedGeneration: feedGeneration)
        case .loaded(false):
            await addCurrentToDefaultFavorites()
        case .idle, .loading, .loaded(true):
            break
        }
    }

    private func addCurrentToDefaultFavorites() async {
        guard let currentCard else { return }
        let key = imageKey(for: currentCard)
        guard !favoriteLoadingKeys.contains(key), case .loaded(false) = favoriteStates[key] else { return }
        favoriteStatusLoadIDs[key] = UUID()
        favoriteLoadingKeys.insert(key)
        defer { favoriteLoadingKeys.remove(key) }
        do {
            try await environment.favoriteClient.add(pid: currentCard.preview.pid, p: currentCard.preview.page)
            favoriteStates[key] = .loaded(true)
            present(.success("已加入默认收藏"))
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } catch {
            let mapped = UserFacingErrorMapper.map(error)
            favoriteStates[key] = .failed(mapped.message)
            present(.error(mapped.message), action: mapped.action)
        }
    }

    private var currentFavoriteButtonTitle: String {
        if isCurrentFavoriteLoading { return "正在收藏" }
        switch currentFavoriteState {
        case .idle, .loading: return "正在确认"
        case .failed: return "重试状态"
        case .loaded(true): return "已喜欢"
        case .loaded(false): return "喜欢"
        }
    }

    private var currentFavoriteButtonSystemImage: String {
        if isCurrentFavoriteLoading { return "clock" }
        switch currentFavoriteState {
        case .idle, .loading: return "clock"
        case .failed: return "arrow.clockwise"
        case .loaded(true): return "heart.fill"
        case .loaded(false): return "heart"
        }
    }

    private var canUseCurrentFavoriteAction: Bool {
        guard currentCard != nil, !hasActiveImageMutation else { return false }
        switch currentFavoriteState {
        case .failed, .loaded(false): return true
        case .idle, .loading, .loaded(true): return false
        }
    }

    private var currentFavoriteAccessibilityHint: String {
        switch currentFavoriteState {
        case .failed:
            return "暂时无法确认是否已喜欢这张图片，轻点重试"
        case .idle, .loading:
            return "正在确认是否已喜欢这张图片"
        case .loaded(true):
            return "这张图片已在默认收藏中"
        case .loaded(false):
            return "加入默认收藏"
        }
    }

    private func imageKey(for card: ImageFeedCard) -> String {
        "\(card.preview.pid)-\(card.preview.page)"
    }

    private func present(_ newFeedback: SetuFeedback, action: UserFacingErrorAction? = nil) {
        feedback = newFeedback
        feedbackAction = action
    }

    private func present(_ error: Error) {
        let mapped = UserFacingErrorMapper.map(error)
        present(.error(mapped.message), action: mapped.action)
    }

    private func swipeReason(for translation: CGSize) -> String {
        if abs(translation.width) > abs(translation.height) {
            return translation.width > 0 ? "已向右换图，快滑不会扣分" : "已向左换图，快滑不会扣分"
        }
        return translation.height > 0 ? "已向下换图，快滑不会扣分" : "已向上换图，快滑不会扣分"
    }

    private func title(for card: ImageFeedCard) -> String {
        unlockedItems[card.token]?.title ?? card.preview.title
    }

    private func author(for card: ImageFeedCard) -> String {
        unlockedItems[card.token]?.author ?? card.preview.author
    }

    private func page(for card: ImageFeedCard) -> Int {
        unlockedItems[card.token]?.page ?? card.preview.page
    }

    private func width(for card: ImageFeedCard) -> Int {
        unlockedItems[card.token]?.width ?? card.preview.width
    }

    private func height(for card: ImageFeedCard) -> Int {
        unlockedItems[card.token]?.height ?? card.preview.height
    }

    private func tags(for card: ImageFeedCard) -> [String] {
        unlockedItems[card.token]?.tags ?? card.preview.tags ?? []
    }

    private func r18Value(for card: ImageFeedCard) -> Bool {
        (unlockedItems[card.token]?.r18 == 1) || card.preview.r18
    }

    private func playSwipeFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

private struct ImageFeedCard: Identifiable, Sendable {
    let feedID: String
    let preview: ImageFeedItem

    var id: String { preview.token }
    var token: String { preview.token }

    func displayURLString(unlockedItem: SetuImageItem?) -> String? {
        unlockedItem?.previewURLString ?? preview.previewURLString
    }

    func hasDisplayableURL(unlockedItem: SetuImageItem?) -> Bool {
        displayURLString(unlockedItem: unlockedItem).flatMap(URL.init(string:)) != nil
    }
}

private struct ImageCollectionReference: Identifiable {
    let pid: Int
    let page: Int
    let title: String

    init(card: ImageFeedCard) {
        pid = card.preview.pid
        page = card.preview.page
        title = card.preview.title
    }

    var id: String { imageKey }
    var imageKey: String { "\(pid)-\(page)" }
}

private struct RandomImageParameters: Equatable {
    var r18: Int
    var keyword: String
    var tagText: String
    var aspectRatio: String
    var excludeAI: Bool
}

private struct RandomImageCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let target: ImageCollectionReference
    let onDone: (String, Bool) -> Void

    @State private var state: LoadState<[CollectionInfo]> = .idle
    @State private var selectedCollectionID: Int?
    @State private var isSaving = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "加入收藏夹", subtitle: target.title)
                            switch state {
                            case .idle, .loading:
                                SetuEmptyState(title: "正在加载收藏夹", systemImage: "folder", isLoading: true)
                            case .failed(let text):
                                SetuEmptyState(title: "收藏夹加载失败", message: text, systemImage: "folder.badge.questionmark")
                            case .loaded(let collections):
                                if collections.isEmpty {
                                    SetuEmptyState(title: "暂无收藏夹", message: "请先创建一个收藏夹", systemImage: "folder.badge.plus")
                                } else {
                                    Picker("收藏到", selection: $selectedCollectionID) {
                                        ForEach(collections) { collection in
                                            Text(collection.name).tag(Optional(collection.id))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .setuListRow()

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                    .setuListRow()
                }
            }
            .listStyle(.plain)
            .setuBackground()
            .navigationTitle("选择收藏夹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收藏") { Task { await save() } }
                        .disabled(selectedCollectionID == nil || isSaving)
                }
            }
            .task { await loadCollections() }
        }
    }

    private func loadCollections() async {
        state = .loading
        do {
            let collections = try await environment.collectionClient.listMine()
            state = .loaded(collections)
            selectedCollectionID = collections.first(where: \.isDefault)?.id ?? collections.first?.id
        } catch {
            state = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func save() async {
        guard let selectedCollectionID, case .loaded(let collections) = state else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let collection = collections.first { $0.id == selectedCollectionID }
            if collection?.isDefault == true {
                try await environment.favoriteClient.add(pid: target.pid, p: target.page)
            } else {
                try await environment.collectionClient.addItem(collectionID: selectedCollectionID, pid: target.pid, p: target.page)
            }
            onDone(
                "已收藏到「\(collection?.name ?? "收藏夹")」",
                collection?.isDefault == true
            )
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }
}

private struct RandomImageCard: View {
    let card: ImageFeedCard
    let unlockedItem: SetuImageItem?
    let stageSize: CGSize

    var body: some View {
        ZStack {
            SetuColor.surfaceMuted
            if card.hasDisplayableURL(unlockedItem: unlockedItem) {
                SetuRemoteImage(
                    urlString: card.displayURLString(unlockedItem: unlockedItem),
                    accessibilityLabel: "随机图片：\(card.preview.title)，作者 \(card.preview.author)",
                    width: stageSize.width,
                    height: stageSize.height,
                    cornerRadius: SetuRadius.lg,
                    contentMode: .fit
                )
            } else {
                ViewThatFits(in: .vertical) {
                    SetuEmptyState(
                        title: "图片预览暂不可用",
                        message: "\(displayTitle) · 作者 \(displayAuthor)",
                        systemImage: "photo"
                    )

                    Label("图片预览暂不可用", systemImage: "photo")
                        .font(.body)
                        .foregroundStyle(SetuColor.textSecondary)
                        .padding(SetuSpacing.md)
                }
                    .accessibilityLabel("图片预览暂不可用，\(displayTitle)，作者 \(displayAuthor)")
                    .accessibilityIdentifier("image.card.placeholder")
            }
        }
    }

    private var displayTitle: String {
        unlockedItem?.title ?? card.preview.title
    }

    private var displayAuthor: String {
        unlockedItem?.author ?? card.preview.author
    }
}

private struct RandomImageParameterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var r18: Int
    @State private var keyword: String
    @State private var tagText: String
    @State private var aspectRatio: String
    @State private var excludeAI: Bool
    let onApply: (RandomImageParameters) -> Void

    init(
        initialParameters: RandomImageParameters,
        onApply: @escaping (RandomImageParameters) -> Void
    ) {
        _r18 = State(initialValue: initialParameters.r18)
        _keyword = State(initialValue: initialParameters.keyword)
        _tagText = State(initialValue: initialParameters.tagText)
        _aspectRatio = State(initialValue: initialParameters.aspectRatio)
        _excludeAI = State(initialValue: initialParameters.excludeAI)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "筛选", subtitle: "预加载和低清预览不扣分，只有确认查看高清图才会计费")
                            Picker("内容级别", selection: $r18) {
                                Text("普通内容").tag(0)
                                Text("成人内容").tag(1)
                                Text("混合").tag(2)
                            }
                            Picker("画幅偏好", selection: $aspectRatio) {
                                Text("全部").tag("")
                                Text("竖图").tag("0.1-0.85")
                                Text("方图").tag("0.86-1.15")
                                Text("横图").tag("1.16-3.0")
                            }
                            TextField("关键词", text: $keyword)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            TextField("标签，逗号分隔", text: $tagText)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            Toggle("排除 AI 图片", isOn: $excludeAI)
                                .tint(SetuColor.brandPink)
                        }
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        Label(
                            "列表会提前缓存一批免费预览图。只有你主动确认查看高清图时才会消费积分，同一张图片重复查看不会再次扣分。",
                            systemImage: "hand.draw"
                        )
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    }
                }
                .setuListRow()
            }
            .listStyle(.plain)
            .setuBackground()
            .navigationTitle("刷图参数")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(
                            RandomImageParameters(
                                r18: r18,
                                keyword: keyword,
                                tagText: tagText,
                                aspectRatio: aspectRatio,
                                excludeAI: excludeAI
                            )
                        )
                    }
                        .foregroundStyle(SetuColor.brandInk)
                }
            }
        }
    }
}

#if DEBUG
#Preview("随机图片 · 390 · 浅色") {
    SetuFeaturePreviewHost { environment, _ in
        RandomImageSwipeView(environment: environment)
    }
    .frame(width: 390, height: 844)
    .preferredColorScheme(.light)
}
#endif
