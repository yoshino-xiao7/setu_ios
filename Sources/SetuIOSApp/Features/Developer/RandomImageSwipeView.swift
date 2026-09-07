import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct RandomImageSwipeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var environment: AppEnvironment

    @State private var imageState: LoadState<ImageFeedCard> = .idle
    @State private var currentCard: ImageFeedCard?
    @State private var displayedCards: [ImageFeedCard] = []
    @State private var scrollTargetID: String?
    @State private var unlockedImagesByKey: [String: SetuImageItem] = [:]
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
    @State private var showingParameters = false
    @State private var balance: Int?
    @State private var costPerImage = 20
    @State private var showingUnlockConfirmation = false
    @State private var favoriteStates: [String: LoadState<Bool>] = [:]
    @State private var favoriteStatusLoadIDs: [String: UUID] = [:]
    @State private var favoriteLoadingKeys: Set<String> = []
    @State private var favoriteDestinations: [String: FavoriteDestination] = [:]
    @State private var favoriteToastTarget: ImageCollectionReference?
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
                if !hasTransientFeedback { feedbackBanner }
                feedStage
                actionBar
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.bottom, SetuSpacing.sm)
        }
        .overlay(alignment: .top) {
            if hasTransientFeedback {
                feedbackBanner
                    .padding(.horizontal, SetuSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("image.swipe.page")
        .navigationTitle("随机图片")
        .setuRefreshAfterLogin(environment.authSession) { Task { await reloadFromParameters() } }
        .setuRetry { Task { await reloadFromParameters() } }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .setuFeedbackPresentation($feedback)
        .toolbar {
            ToolbarItemGroup {
                Button { router.navigate(to: .pointsLogs) } label: {
                    HStack(spacing: SetuSpacing.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(balance.map(String.init) ?? "—")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .accessibilityLabel("当前余额 \(balanceText)")
                .accessibilityIdentifier("image.balance")
                Button {
                    showingParameters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(hasActiveImageMutation)
                .accessibilityLabel("调整找图设置")
                Menu {
                    Button("重新加载") { Task { await reloadFromParameters() } }
                    Button("默认收藏") { router.navigate(to: .favorites) }
                    Button("我的收藏夹") { router.navigate(to: .collections) }
                    Button("API Key 管理") { router.navigate(to: .apiKeys) }
                    Button {
                        router.navigate(to: .points)
                    } label: {
                        Label("按条件找图", systemImage: "slider.horizontal.3")
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
            RandomImageCollectionSheet(environment: environment, target: target) { result, destination in
                present(.success(result))
                favoriteStatusLoadIDs[target.imageKey] = UUID()
                favoriteStates[target.imageKey] = .loaded(true)
                favoriteDestinations[target.imageKey] = destination
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
        .task(id: currentCard?.id) {
            guard let card = currentCard,
                  let delay = ImageFeedExpiryPolicy.prefetchDelay(for: card.expiresAt) else { return }
            let generation = feedGeneration
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, generation == feedGeneration else { return }
            displayedCards.removeAll {
                $0.id != currentCard?.id && (ImageFeedExpiryPolicy.prefetchDelay(for: $0.expiresAt) ?? 1) == 0
            }
            await prefetchIfNeeded(force: true, expectedGeneration: generation)
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
            Text("低清预览免费。当前余额：\(balanceText)；已解锁图片在本次浏览中再次查看不扣分。")
        }
    }

    @ViewBuilder
    private var feedStage: some View {
        GeometryReader { proxy in
            ZStack {
                switch imageState {
                case .idle where displayedCards.isEmpty && currentCard == nil:
                    loadingPlaceholder
                case .loading where displayedCards.isEmpty && currentCard == nil:
                    loadingPlaceholder
                case .failed(let text) where displayedCards.isEmpty && currentCard == nil:
                    if text.message == noMatchingImagesMessage {
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
                    if displayedCards.isEmpty {
                        SetuEmptyState(title: "暂无图片", systemImage: "photo.on.rectangle")
                    } else {
                        feedScroll(containerSize: proxy.size)
                    }
                }

                if isCurrentUnlocking {
                    floatingStatus(systemImage: "lock.open", title: "正在解锁")
                }
            }
        }
    }

    private func feedScroll(containerSize: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SetuSpacing.xxl) {
                    ForEach(displayedCards) { card in
                        RandomImageFeedPost(
                            card: card,
                            unlockedItem: unlockedItems[card.token],
                            containerWidth: containerSize.width,
                            maxImageHeight: max(containerSize.height * 0.72, 180),
                            onCopyPID: { copyPID(of: card) }
                        )
                        .id(card.id)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: FeedCardMinYKey.self,
                                    value: [card.id: geo.frame(in: .named("imageFeed")).minY]
                                )
                            }
                        }
                        .onAppear {
                            if card.id == displayedCards.last?.id {
                                let generation = feedGeneration
                                Task { await prefetchIfNeeded(expectedGeneration: generation) }
                            }
                        }
                    }

                    if isPrefetching && currentCard != nil {
                        SetuLoadMoreFooter(state: .loading)
                    }
                }
                .padding(.bottom, SetuSpacing.sm)
            }
            .coordinateSpace(name: "imageFeed")
            .scrollIndicators(.hidden)
            .onPreferenceChange(FeedCardMinYKey.self) { updateFocusedCard(from: $0) }
            .onChange(of: scrollTargetID) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .top)
                } else {
                    withAnimation(.snappy(duration: 0.28)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
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
                    isCurrentUnlocked || dynamicTypeSize.isAccessibilitySize ? "查看高清图" : "查看高清图 · \(costPerImage) 积分",
                    systemImage: isCurrentUnlocked ? "lock.open" : "lock"
                )
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(currentCard == nil || hasActiveImageMutation)
            .buttonStyle(.borderedProminent)
            .tint(SetuColor.gradientTop)
            .accessibilityHint("低清预览免费，确认后才会消费积分")
            .accessibilityIdentifier("image.unlock")

            HStack(spacing: SetuSpacing.xs) {
                Button {
                    Task { await handleFavoriteAction() }
                } label: {
                    ImageSwipeActionLabel(title: currentFavoriteButtonTitle, systemImage: currentFavoriteButtonSystemImage)
                }
                .setuButtonFeedback()
                .disabled(!canUseCurrentFavoriteAction)
                .accessibilityIdentifier("image.favorite")
                .accessibilityHint(currentFavoriteAccessibilityHint)
                .highPriorityGesture(
                    LongPressGesture().exclusively(before: TapGesture()).onEnded { gesture in
                        switch gesture {
                        case .first:
                            openCollectionPicker()
                        case .second:
                            Task { await handleFavoriteAction() }
                        }
                    }
                )
                .accessibilityAction(named: "选择收藏夹") { openCollectionPicker() }

                Button {
                    if let currentCard {
                        originalPreviewItem = UserImagePreviewItem(
                            id: currentCard.id,
                            pid: currentCard.preview.pid,
                            page: currentCard.preview.page,
                            title: title(for: currentCard),
                            author: author(for: currentCard),
                            width: width(for: currentCard),
                            height: height(for: currentCard),
                            r18: r18Value(for: currentCard),
                            displayURLString: currentCard.displayURLString(unlockedItem: unlockedItems[currentCard.token]),
                            originalURLString: unlockedItems[currentCard.token]?.originalURLString
                        )
                    }
                } label: {
                    ImageSwipeActionLabel(title: "分享", systemImage: "square.and.arrow.up")
                }
                .setuButtonFeedback()
                .disabled(currentCard == nil || hasActiveImageMutation)
                .accessibilityIdentifier("image.share")

                Button {
                    playSwipeFeedback()
                    let generation = feedGeneration
                    Task {
                        await loadNextImage(
                            reason: "已换到下一张图片，预览免费",
                            expectedGeneration: generation
                        )
                    }
                } label: {
                    ImageSwipeActionLabel(title: "下一张", systemImage: "arrow.down.circle.fill")
                }
                .setuButtonFeedback()
                .disabled(isLoadingImage || hasActiveImageMutation)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SetuSpacing.sm)
        .padding(.horizontal, SetuSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private func pidDisplay(for card: ImageFeedCard) -> ImagePidDisplay {
        ImagePidDisplay(pid: card.preview.pid, page: page(for: card))
    }

    private func copyPID(of card: ImageFeedCard) {
        let display = pidDisplay(for: card)
        PlatformClipboard.copy(display.copyText)
        present(.success("\(display.title) 已复制"))
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func updateFocusedCard(from minYs: [String: CGFloat]) {
        guard !showingUnlockConfirmation, !hasActiveImageMutation else { return }
        if let scrollTargetID {
            if let y = minYs[scrollTargetID], abs(y) < 120 {
                self.scrollTargetID = nil
            }
            return
        }
        guard let focusedID = minYs.min(by: { abs($0.value) < abs($1.value) })?.key,
              let card = displayedCards.first(where: { $0.id == focusedID }),
              currentCard?.id != card.id else { return }
        Task { selectCard(card, reason: nil, scroll: false) }
    }

    private func selectCard(_ card: ImageFeedCard, reason: String?, scroll: Bool) {
        if let unlocked = unlockedImagesByKey[imageKey(for: card)] {
            unlockedItems[card.token] = unlocked
        }
        let favoriteKey = imageKey(for: card)
        if favoriteStates[favoriteKey] == nil {
            favoriteStates[favoriteKey] = .loading
        }
        currentCard = card
        imageState = .loaded(card)
        if reason == "已应用参数" {
            present(.info(reason ?? ""))
        } else if reason != nil {
            feedback = nil
            favoriteToastTarget = nil
        }
        if scroll {
            scrollTargetID = card.id
        }
        let generation = feedGeneration
        Task { await refreshFavoriteStatus(for: card, expectedGeneration: generation) }
    }

    private var hasTransientFeedback: Bool {
        switch feedback {
        case .success, .info: true
        default: false
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let feedback {
            SetuFeedbackBanner(
                feedback: feedback,
                actionTitle: favoriteToastTarget == nil ? nil : "改到其他收藏夹",
                action: favoriteToastTarget.map { target in { collectionTarget = target } }
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.sm))
            .accessibilityIdentifier("image.feedback")
        }
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
        displayedCards = []
        scrollTargetID = nil
        unlockedItems = [:]
        favoriteStates = [:]
        favoriteStatusLoadIDs = [:]
        imageState = .loading
        feedback = nil
        let generation = feedGeneration
        return generation
    }

    private func completeReload(generation: Int) async {
        guard generation == feedGeneration else { return }
        await loadBalance(expectedGeneration: generation)
        guard generation == feedGeneration else { return }
        await prefetchIfNeeded(force: true, expectedGeneration: generation)
        guard generation == feedGeneration, !displayedCards.isEmpty else { return }
        imageState = .idle
        await loadNextImage(reason: "已应用参数", expectedGeneration: generation)
    }

    private func loadNextImage(reason: String, expectedGeneration: Int? = nil) async {
        let generation = expectedGeneration ?? feedGeneration
        guard generation == feedGeneration else { return }
        pruneExpiredCards()

        if let currentCard, let next = nextCard(after: currentCard) {
            selectCard(next, reason: reason, scroll: true)
            prefetchIfLow(expectedGeneration: generation)
            return
        }

        if currentCard == nil, let first = displayedCards.first(where: { !ImageFeedExpiryPolicy.isExpired($0.expiresAt) }) {
            selectCard(first, reason: reason, scroll: false)
            prefetchIfLow(expectedGeneration: generation)
            return
        }

        if isPrefetching {
            for _ in 0..<40 {
                guard generation == feedGeneration else { return }
                if !isPrefetching { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard generation == feedGeneration else { return }
            if let currentCard, let next = nextCard(after: currentCard) {
                selectCard(next, reason: reason, scroll: true)
                return
            }
        }

        await prefetchIfNeeded(force: true, expectedGeneration: generation)
        guard generation == feedGeneration else { return }
        pruneExpiredCards()

        if let currentCard, let next = nextCard(after: currentCard) {
            selectCard(next, reason: reason, scroll: true)
            return
        }
        if currentCard == nil, let first = displayedCards.first(where: { !ImageFeedExpiryPolicy.isExpired($0.expiresAt) }) {
            selectCard(first, reason: reason, scroll: false)
            return
        }
        if currentCard == nil {
            if case .failed = imageState {
                return
            }
            imageState = .failed(noMatchingImagesMessage)
        }
    }

    private func nextCard(after card: ImageFeedCard) -> ImageFeedCard? {
        let expired = displayedCards.map { ImageFeedExpiryPolicy.isExpired($0.expiresAt) }
        guard let index = displayedCards.firstIndex(where: { $0.id == card.id }),
              let nextIndex = ImageFeedBrowsePolicy.nextIndex(after: index, expired: expired) else {
            return nil
        }
        return displayedCards[nextIndex]
    }

    private func pruneExpiredCards() {
        displayedCards.removeAll { card in
            card.id != currentCard?.id && ImageFeedExpiryPolicy.isExpired(card.expiresAt)
        }
    }

    private func remainingCardsAfterFocus() -> Int {
        guard let currentCard,
              let index = displayedCards.firstIndex(where: { $0.id == currentCard.id }) else {
            return displayedCards.count
        }
        return max(displayedCards.count - index - 1, 0)
    }

    private func prefetchIfLow(expectedGeneration: Int? = nil) {
        let generation = expectedGeneration ?? feedGeneration
        Task { await prefetchIfNeeded(expectedGeneration: generation) }
    }

    private func appendUniqueCards(_ cards: [ImageFeedCard]) {
        let existing = Set(displayedCards.map(\.token))
        displayedCards.append(contentsOf: cards.filter { !existing.contains($0.token) })
    }

    private func prefetchIfNeeded(
        force: Bool = false,
        expectedGeneration: Int? = nil
    ) async {
        let generation = expectedGeneration ?? feedGeneration
        guard generation == feedGeneration else { return }
        guard activePrefetchID == nil else { return }
        guard force || remainingCardsAfterFocus() <= refillThreshold else { return }

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
            let cards = response.items.map { ImageFeedCard(feedID: response.feedId, preview: $0, expiresAt: ImageFeedExpiryPolicy.expirationDate(response.expiresAt)) }
            appendUniqueCards(cards)
            if cards.isEmpty {
                if currentCard == nil {
                    imageState = .failed(noMatchingImagesMessage)
                }
                present(.info(noMatchingImagesMessage))
            }
        } catch {
            guard generation == feedGeneration, activePrefetchID == requestID else { return }
            if currentCard == nil {
                imageState = .failed(UserFacingErrorMapper.map(error))
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

        if ImageFeedExpiryPolicy.isExpired(card.expiresAt) {
            await reloadExpiredFeed()
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
            unlockedImagesByKey[imageKey(for: card)] = response.item
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
                if ImageFeedExpiryPolicy.shouldReloadPreview(after: error) {
                    unlockingTokens.remove(card.token)
                    await reloadExpiredFeed()
                } else {
                    present(error)
                }
            }
            return nil
        }
    }

    private func reloadExpiredFeed() async {
        // No recursive consume: the replacement preview can be a different picture.
        guard let generation = beginReload() else { return }
        await completeReload(generation: generation)
        if generation == feedGeneration, currentCard != nil {
            present(.info("预览已过期，已重新加载。请确认新图片后查看高清图。"))
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
            favoriteStates[key] = .loaded(isFavorited || favoriteDestinations[key] != nil)
        } catch {
            guard generation == feedGeneration,
                  favoriteStatusLoadIDs[key] == loadID else { return }
            favoriteStates[key] = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func handleFavoriteAction() async {
        guard let currentCard else { return }
        switch currentFavoriteState {
        case .failed:
            await refreshFavoriteStatus(for: currentCard, expectedGeneration: feedGeneration)
        case .loaded(false):
            await addCurrentToDefaultFavorites()
        case .loaded(true):
            await removeCurrentFavorite()
        case .idle, .loading:
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
            favoriteDestinations[key] = .defaultCollection
            present(.success("已加入默认收藏"))
            favoriteToastTarget = ImageCollectionReference(card: currentCard, source: .defaultCollection)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        } catch {
            let mapped = UserFacingErrorMapper.map(error)
            favoriteStates[key] = .failed(mapped)
            present(.error(mapped))
        }
    }

    private func openCollectionPicker() {
        guard let card = currentCard, !hasActiveImageMutation else { return }
        let source: FavoriteDestination? = {
            if let destination = favoriteDestinations[imageKey(for: card)] { return destination }
            if case .loaded(true) = currentFavoriteState { return .defaultCollection }
            return nil
        }()
        collectionTarget = ImageCollectionReference(card: card, source: source)
    }

    private func removeCurrentFavorite() async {
        guard let card = currentCard, !hasActiveImageMutation else { return }
        let key = imageKey(for: card)
        favoriteLoadingKeys.insert(key)
        favoriteStatusLoadIDs[key] = UUID()
        defer { favoriteLoadingKeys.remove(key) }
        do {
            if case .collection(let id) = favoriteDestinations[key] {
                try await environment.collectionClient.removeItem(collectionID: id, pid: card.preview.pid, p: card.preview.page)
            } else {
                try await environment.favoriteClient.remove(pid: card.preview.pid, p: card.preview.page)
            }
            favoriteDestinations[key] = nil
            favoriteStates[key] = .loaded(false)
            present(.success("已取消收藏"))
        } catch {
            favoriteStates[key] = .failed(UserFacingErrorMapper.map(error))
            present(error)
        }
    }

    private var currentFavoriteButtonTitle: String {
        if isCurrentFavoriteLoading { return "正在收藏" }
        switch currentFavoriteState {
        case .idle, .loading: return "正在确认"
        case .failed: return "重试状态"
        case .loaded(true): return "已收藏"
        case .loaded(false): return "收藏"
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
        case .failed, .loaded: return true
        case .idle, .loading: return false
        }
    }

    private var currentFavoriteAccessibilityHint: String {
        switch currentFavoriteState {
        case .failed:
            return "暂时无法确认是否已收藏这张图片，轻点重试"
        case .idle, .loading:
            return "正在确认是否已收藏这张图片"
        case .loaded(true):
            return "再次点按取消收藏，长按选择收藏夹"
        case .loaded(false):
            return "加入默认收藏"
        }
    }

    private func imageKey(for card: ImageFeedCard) -> String {
        "\(card.preview.pid)-\(card.preview.page)"
    }

    private func present(_ newFeedback: SetuFeedback) {
        favoriteToastTarget = nil
        favoriteToastTarget = nil
        feedback = newFeedback
    }

    private func present(_ error: Error) {
        let mapped = UserFacingErrorMapper.map(error)
        present(.error(mapped))
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

private struct ImageSwipeActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: SetuSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(SetuSpacing.xs)
        .foregroundStyle(SetuColor.brandInk)
        .background(SetuColor.brandSoft.opacity(0.2), in: RoundedRectangle(cornerRadius: SetuRadius.md))
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct ImageFeedCard: Identifiable, Sendable {
    let feedID: String
    let preview: ImageFeedItem
    let expiresAt: Date?

    var id: String { preview.token }
    var token: String { preview.token }

    func displayURLString(unlockedItem: SetuImageItem?) -> String? {
        unlockedItem?.previewURLString ?? preview.previewURLString
    }

    func hasDisplayableURL(unlockedItem: SetuImageItem?) -> Bool {
        displayURLString(unlockedItem: unlockedItem).flatMap(URL.init(string:)) != nil
    }
}

private enum FavoriteDestination: Equatable {
    case defaultCollection
    case collection(Int)
}

private struct ImageCollectionReference: Identifiable {
    let pid: Int
    let page: Int
    let title: String

    let source: FavoriteDestination?

    init(card: ImageFeedCard, source: FavoriteDestination? = nil) {
        self.source = source
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
    let onDone: (String, FavoriteDestination) -> Void

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
            .setuRetry { Task { await loadCollections() } }
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
            state = .failed(UserFacingErrorMapper.map(error))
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
            let destination: FavoriteDestination = collection?.isDefault == true ? .defaultCollection : .collection(selectedCollectionID)
            // Add first. If removing the source fails, keep both copies and report it.
            if let source = target.source, source != destination {
                switch source {
                case .defaultCollection:
                    try await environment.favoriteClient.remove(pid: target.pid, p: target.page)
                case .collection(let id):
                    try await environment.collectionClient.removeItem(collectionID: id, pid: target.pid, p: target.page)
                }
            }
            onDone("已收藏到「\(collection?.name ?? "收藏夹")」", destination)
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private struct FeedCardMinYKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct RandomImageFeedPost: View {
    let card: ImageFeedCard
    let unlockedItem: SetuImageItem?
    let containerWidth: CGFloat
    let maxImageHeight: CGFloat
    let onCopyPID: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            imageStage
            if hasDisplayableURL {
                metadata
                    .accessibilityIdentifier("image.metadata.overlay")
            } else {
                pidRow
            }
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                .fill(SetuColor.surfaceMuted)
            if hasDisplayableURL {
                SetuRemoteImage(
                    urlString: card.displayURLString(unlockedItem: unlockedItem),
                    accessibilityLabel: "随机图片：\(displayTitle)，作者 \(displayAuthor)",
                    width: containerWidth,
                    height: imageHeight,
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

                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(SetuColor.textSecondary)
                        .padding(SetuSpacing.sm)
                }
                .accessibilityLabel("图片预览暂不可用，\(displayTitle)，作者 \(displayAuthor)")
                .accessibilityIdentifier("image.card.placeholder")
            }
        }
        .frame(width: containerWidth, height: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SetuSpacing.sm) {
                    titleBlock
                    Spacer(minLength: SetuSpacing.sm)
                    statusPills
                }
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    titleBlock
                    statusPills
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: SetuSpacing.sm) {
                    pidRow
                    Spacer(minLength: SetuSpacing.sm)
                    resolutionLabel
                }
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    pidRow
                    resolutionLabel
                }
            }

            if !displayTags.isEmpty {
                TagFlow(tags: displayTags)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(displayAuthor)
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPills: some View {
        HStack(spacing: SetuSpacing.xs) {
            if isR18 {
                SetuPill(text: "成人内容", tone: .danger)
            }
            SetuPill(
                text: unlockedItem == nil ? "预览" : "已解锁",
                tone: unlockedItem == nil ? .muted : .success
            )
        }
    }

    private var pidRow: some View {
        ImagePidCopyButton(display: pidDisplay, onCopied: onCopyPID)
    }

    private var resolutionLabel: some View {
        Label("\(displayWidth)×\(displayHeight)", systemImage: "aspectratio")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(SetuColor.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var hasDisplayableURL: Bool {
        card.hasDisplayableURL(unlockedItem: unlockedItem)
    }

    private var imageHeight: CGFloat {
        ImageFeedBrowsePolicy.imageHeight(
            containerWidth: containerWidth,
            pixelWidth: displayWidth,
            pixelHeight: displayHeight,
            maxHeight: maxImageHeight
        )
    }

    private var pidDisplay: ImagePidDisplay {
        ImagePidDisplay(pid: card.preview.pid, page: unlockedItem?.page ?? card.preview.page)
    }

    private var displayTitle: String {
        unlockedItem?.title ?? card.preview.title
    }

    private var displayAuthor: String {
        unlockedItem?.author ?? card.preview.author
    }

    private var displayWidth: Int {
        unlockedItem?.width ?? card.preview.width
    }

    private var displayHeight: Int {
        unlockedItem?.height ?? card.preview.height
    }

    private var displayTags: [String] {
        unlockedItem?.tags ?? card.preview.tags ?? []
    }

    private var isR18: Bool {
        (unlockedItem?.r18 == 1) || card.preview.r18
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
                            SetuSectionHeader(title: "筛选")
                            TextField("关键词", text: $keyword)
                                .accessibilityLabel("关键词")
                                .accessibilityIdentifier("image.filter.keyword")
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            TextField("标签，逗号分隔", text: $tagText)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
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
                            Toggle("排除 AI 图片", isOn: $excludeAI)
                                .tint(SetuColor.brandPink)
                        }
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        Label(
                            "列表会提前缓存一批免费预览图。只有你主动确认查看高清图时才会消费积分，已解锁图片在本次浏览中再次查看不扣分。",
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
