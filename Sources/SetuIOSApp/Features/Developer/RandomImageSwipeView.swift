import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct RandomImageSwipeView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    @State private var imageState: LoadState<ImageFeedCard> = .idle
    @State private var currentCard: ImageFeedCard?
    @State private var feedQueue: [ImageFeedCard] = []
    @State private var unlockedItems: [String: SetuImageItem] = [:]
    @State private var unlockingTokens: Set<String> = []
    @State private var isPrefetching = false
    @State private var r18 = 0
    @State private var keyword = ""
    @State private var tagText = ""
    @State private var aspectRatio = ""
    @State private var excludeAI = true
    @State private var message: String?
    @State private var showingParameters = false
    @State private var dragOffset = CGSize.zero
    @State private var balance: Int?
    @State private var costPerImage = 20
    @State private var settleUnlockTask: Task<Void, Never>?

    private let preloadLimit = 10
    private let refillThreshold = 3
    private let settleDelayNanoseconds: UInt64 = 650_000_000

    var body: some View {
        ZStack {
            SetuColor.pageGradient
                .ignoresSafeArea()

            VStack(spacing: SetuSpacing.md) {
                statusStrip
                if let message {
                    messageStrip(message)
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
                Menu {
                    Button {
                        router.navigate(to: .points)
                    } label: {
                        Label("高级参数与批量获取", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        router.navigate(to: .pointsLogs)
                    } label: {
                        Label("积分流水", systemImage: "list.bullet.rectangle")
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
            }
        }
        .sheet(isPresented: $showingParameters) {
            RandomImageParameterSheet(
                r18: $r18,
                keyword: $keyword,
                tagText: $tagText,
                aspectRatio: $aspectRatio,
                excludeAI: $excludeAI
            ) {
                showingParameters = false
                Task { await reloadFromParameters() }
            }
        }
        .task {
            await loadBalance()
            await prefetchIfNeeded(force: true)
            if currentCard == nil {
                await loadNextImage(reason: "预加载完成，停留片刻后解锁")
            }
        }
        .refreshable {
            await reloadFromParameters()
        }
        .onDisappear {
            settleUnlockTask?.cancel()
        }
    }

    private var statusStrip: some View {
        HStack(spacing: SetuSpacing.sm) {
            Label(balanceText, systemImage: "bolt.circle")
            Divider()
                .frame(height: 18)
            Label("解锁 \(costPerImage)", systemImage: "tag")
            Divider()
                .frame(height: 18)
            Label("\(feedQueue.count) 张已预加载", systemImage: "tray.full")
            Spacer()
            if isPrefetching {
                ProgressView()
                    .tint(SetuColor.brandPink)
            } else if isCurrentUnlocking {
                Label("正在解锁", systemImage: "lock.open")
            } else if isCurrentUnlocked {
                Label("已解锁", systemImage: "checkmark.circle")
            } else {
                Label("停留扣分", systemImage: "hand.tap")
            }
        }
        .font(.footnote)
        .foregroundStyle(SetuColor.textSecondary)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.sm)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(SetuColor.separator, lineWidth: 1)
        }
        .accessibilityLabel("积分 \(balanceText)，当前队列已预加载 \(feedQueue.count) 张，图片稳定停留后才会解锁扣分")
    }

    private func messageStrip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: text.contains("失败") || text.contains("不足") ? "exclamationmark.triangle" : "hand.draw")
            Text(text)
                .lineLimit(2)
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(text.contains("失败") || text.contains("不足") ? SetuColor.danger : SetuColor.textSecondary)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
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
                    SetuEmptyState(title: "图片加载失败", message: text, systemImage: "photo.on.rectangle")
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
                if let currentCard {
                    imageMetadataOverlay(currentCard)
                }
            }
            .offset(dragOffset)
            .animation(.snappy(duration: 0.18), value: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        dragOffset = CGSize(
                            width: value.translation.width * 0.18,
                            height: value.translation.height * 0.18
                        )
                    }
                    .onEnded { value in
                        let distance = max(abs(value.translation.width), abs(value.translation.height))
                        let reason = swipeReason(for: value.translation)
                        dragOffset = .zero
                        if distance > 70 {
                            playSwipeFeedback()
                            Task { await loadNextImage(reason: reason) }
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
        HStack(spacing: SetuSpacing.lg) {
            Button {
                Task { await openOriginal() }
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .frame(width: 48, height: 48)
                    .background(SetuColor.surface.opacity(0.62), in: Circle())
            }
            .disabled(currentCard == nil)
            .setuButtonFeedback(cornerRadius: 24)
            .accessibilityLabel("打开原图")

            Button {
                showingParameters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 48, height: 48)
                    .background(SetuColor.surface.opacity(0.62), in: Circle())
            }
            .setuButtonFeedback(cornerRadius: 24)
            .accessibilityLabel("刷图参数")

            Button {
                Task { await loadNextImage(reason: "已换到下一张图片") }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .frame(width: 48, height: 48)
                    .background(SetuColor.surface.opacity(0.62), in: Circle())
            }
            .disabled(isLoadingImage)
            .setuButtonFeedback(cornerRadius: 24)
            .accessibilityLabel("下一张")
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(SetuColor.brandPink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SetuSpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
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
                    SetuPill(text: "R18", tone: .danger)
                }
                SetuPill(text: unlockedItems[card.token] == nil ? "预览" : "已解锁", tone: unlockedItems[card.token] == nil ? .muted : .success)
            }

            HStack(spacing: 10) {
                Label("PID \(card.preview.pid)-\(page(for: card))", systemImage: "number")
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

    private func loadBalance() async {
        do {
            balance = try await environment.pointsClient.balance().points
        } catch {
            balance = nil
        }
    }

    private func reloadFromParameters() async {
        settleUnlockTask?.cancel()
        currentCard = nil
        feedQueue = []
        unlockedItems = [:]
        unlockingTokens = []
        imageState = .loading
        message = nil
        await loadBalance()
        await prefetchIfNeeded(force: true)
        await loadNextImage(reason: "已应用参数")
    }

    private func loadNextImage(reason: String) async {
        guard !isLoadingImage else { return }
        settleUnlockTask?.cancel()

        if feedQueue.isEmpty, isPrefetching {
            message = "正在预加载下一批图片"
            return
        }

        if feedQueue.isEmpty {
            imageState = currentCard.map { .loaded($0) } ?? .loading
            await prefetchIfNeeded(force: true)
        }

        guard !feedQueue.isEmpty else {
            imageState = currentCard.map { .loaded($0) } ?? .failed("当前筛选条件没有匹配图片")
            message = "当前筛选条件没有匹配图片"
            return
        }

        let next = feedQueue.removeFirst()
        currentCard = next
        imageState = .loaded(next)
        message = reason
        scheduleSettledUnlock(for: next)

        if feedQueue.count <= refillThreshold {
            Task { await prefetchIfNeeded() }
        }
    }

    private func prefetchIfNeeded(force: Bool = false) async {
        guard !isPrefetching else { return }
        guard force || feedQueue.count <= refillThreshold else { return }

        isPrefetching = true
        defer { isPrefetching = false }

        do {
            let response = try await environment.imageFeedClient.feed(
                ImageFeedRequest(
                    r18: r18,
                    limit: preloadLimit,
                    keyword: normalizedKeyword,
                    tags: parsedTags,
                    excludeAI: excludeAI,
                    aspectRatio: normalizedAspectRatio,
                    source: nil
                )
            )
            costPerImage = response.costPerImage
            balance = response.balance
            let cards = response.items.map { ImageFeedCard(feedID: response.feedId, preview: $0) }
            feedQueue.append(contentsOf: cards)
            if cards.isEmpty, currentCard == nil {
                imageState = .failed("当前筛选条件没有匹配图片")
                message = "当前筛选条件没有匹配图片"
            }
        } catch {
            if currentCard == nil {
                imageState = .failed(error.localizedDescription)
            }
            message = error.localizedDescription
        }
    }

    private func scheduleSettledUnlock(for card: ImageFeedCard) {
        settleUnlockTask?.cancel()
        settleUnlockTask = Task {
            try? await Task.sleep(nanoseconds: settleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            _ = await unlock(card: card, reason: "dwell", showSuccess: false)
        }
    }

    @discardableResult
    private func unlock(card: ImageFeedCard, reason: String, showSuccess: Bool) async -> SetuImageItem? {
        if let item = unlockedItems[card.token] {
            return item
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
                reason: reason
            )
            unlockedItems[card.token] = response.item
            balance = response.balance
            if currentCard?.token == card.token {
                imageState = .loaded(card)
            }
            if showSuccess {
                message = response.charged ? "已解锁，消耗 \(response.cost) 积分" : "已解锁，未重复扣分"
            }
            return response.item
        } catch {
            if currentCard?.token == card.token {
                message = error.localizedDescription
            }
            return nil
        }
    }

    private func openOriginal() async {
        guard let currentCard else {
            message = "当前没有可打开的图片"
            return
        }
        let item = await unlock(card: currentCard, reason: "open_original", showSuccess: true)
        guard let urlString = item?.originalURLString ?? item?.previewURLString ?? currentCard.preview.previewURLString,
              let url = URL(string: urlString)
        else {
            message = "图片链接无效"
            return
        }
        #if os(iOS)
        await UIApplication.shared.open(url)
        #else
        message = "当前平台暂不支持打开原图"
        #endif
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
}

private struct RandomImageCard: View {
    let card: ImageFeedCard
    let unlockedItem: SetuImageItem?
    let stageSize: CGSize

    var body: some View {
        ZStack {
            SetuColor.surfaceMuted
            if let url = displayURLString.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(SetuColor.brandPink)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: stageSize.width, maxHeight: stageSize.height)
                    case .failure:
                        SetuEmptyState(title: "图片加载失败", systemImage: "photo")
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                SetuEmptyState(title: "没有可用图片地址", systemImage: "photo")
            }
        }
    }

    private var displayURLString: String? {
        unlockedItem?.previewURLString ?? card.preview.previewURLString
    }
}

private struct RandomImageParameterSheet: View {
    @Binding var r18: Int
    @Binding var keyword: String
    @Binding var tagText: String
    @Binding var aspectRatio: String
    @Binding var excludeAI: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "筛选", subtitle: "预加载不扣分，停留到当前图片后才解锁计费")
                            Picker("R18", selection: $r18) {
                                Text("非 R18").tag(0)
                                Text("R18").tag(1)
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
                            "列表会提前缓存一批预览图。快速滑过的图片不会扣分；停在某张图片后，会自动解锁并只扣一次积分。",
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: onApply)
                        .foregroundStyle(SetuColor.brandInk)
                }
            }
        }
    }
}
