import SetuIOSCore
import SwiftUI

struct FavoriteListView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var environment: AppEnvironment
    @State private var items: [FavoriteItem] = []
    @State private var total = 0
    @State private var nextPage = 1
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var initialError: String?
    @State private var loadMoreError: String?
    @State private var feedback: SetuFeedback?
    @State private var previewItem: UserImagePreviewItem?
    @State private var movingItem: FavoriteItem?
    @State private var recentlyRemovedItem: FavoriteItem?
    @State private var undoDismissTask: Task<Void, Never>?
    private let pageSize = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                if let feedback {
                    SetuFeedbackBanner(feedback: feedback)
                }

                if let initialError, !items.isEmpty {
                    SetuLoadMoreFooter(state: .failed(initialError)) {
                        Task { await loadFirstPage() }
                    }
                }

                if isInitialLoading {
                    SetuCard {
                        SetuEmptyState(
                            title: "正在加载收藏",
                            message: "默认收藏会按最新顺序展示。",
                            systemImage: "heart",
                            isLoading: true
                        )
                    }
                } else if items.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: "默认收藏", subtitle: "共 \(total) 张")
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(items) { item in
                            FavoriteImageTile(item: item) {
                                previewItem = UserImagePreviewItem(favorite: item)
                            } onMove: {
                                movingItem = item
                            } onRemove: {
                                Task { await remove(item) }
                            }
                            .onAppear {
                                if item.id == items.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    SetuLoadMoreFooter(state: loadMoreFooterState) {
                        Task { await loadMore() }
                    }
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("默认收藏")
        .sheet(item: $previewItem) { item in
            UserImagePreviewSheet(item: item)
        }
        .sheet(item: $movingItem) { item in
            FavoriteMoveSheet(environment: environment, item: item) {
                recentlyRemovedItem = nil
                feedback = .success("已移动到目标收藏夹")
                Task { await loadFirstPage() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = recentlyRemovedItem {
                undoBar(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
        .onDisappear { undoDismissTask?.cancel() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "收藏加载失败", message: initialError, systemImage: "heart.slash")
                    Button("重试") {
                        Task { await loadFirstPage() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无默认收藏", message: "收藏图片后会显示在这里。", systemImage: "heart")
            }
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 156), spacing: SetuSpacing.md)]
    }

    private var hasMore: Bool { items.count < total }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadMoreError { return .failed(loadMoreError) }
        if !hasMore { return .complete("已加载全部 \(total) 张收藏") }
        return .idle
    }

    private func loadFirstPage() async {
        isInitialLoading = items.isEmpty
        initialError = nil
        loadMoreError = nil
        do {
            let result = try await environment.favoriteClient.list(page: 1, size: pageSize)
            items = result.items
            total = result.total
            nextPage = 2
        } catch {
            initialError = "暂时无法加载收藏，请检查网络后重试。"
        }
        isInitialLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        let requestedPage = nextPage
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let result = try await environment.favoriteClient.list(page: requestedPage, size: pageSize)
            guard requestedPage == nextPage else { return }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !existingIDs.contains($0.id) })
            total = result.total
            nextPage += 1
        } catch {
            loadMoreError = "更多收藏加载失败"
        }
    }

    private func remove(_ item: FavoriteItem) async {
        feedback = nil
        do {
            try await environment.favoriteClient.remove(pid: item.pid, p: item.p)
            recentlyRemovedItem = item
            scheduleUndoDismissal(for: item)
            await loadFirstPage()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func undoBar(_ item: FavoriteItem) -> some View {
        HStack(spacing: SetuSpacing.md) {
            Label("已移除「\(item.image?.title ?? "未命名作品")」", systemImage: "heart.slash")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: SetuSpacing.sm)
            Button("撤销") {
                Task { await undoRemove(item) }
            }
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, SetuSpacing.lg)
        .padding(.vertical, SetuSpacing.sm)
        .background(.regularMaterial)
    }

    private func undoRemove(_ item: FavoriteItem) async {
        undoDismissTask?.cancel()
        do {
            try await environment.favoriteClient.add(pid: item.pid, p: item.p)
            recentlyRemovedItem = nil
            await loadFirstPage()
            feedback = .success("已恢复收藏")
        } catch {
            feedback = .error("撤销失败：\(UserFacingErrorMapper.map(error).message)")
        }
    }

    private func scheduleUndoDismissal(for item: FavoriteItem) {
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, recentlyRemovedItem?.id == item.id else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                recentlyRemovedItem = nil
            }
        }
    }
}

private struct FavoriteImageTile: View {
    let item: FavoriteItem
    let onPreview: () -> Void
    let onMove: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SetuCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onPreview) {
                    ContentGridImageView(
                        urlString: item.image?.urlSmall ?? item.image?.urlRegular ?? item.image?.urlOriginal,
                        accessibilityLabel: item.image?.title ?? "未命名作品"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("favorite.item.\(item.id)")

                HStack(alignment: .top, spacing: SetuSpacing.sm) {
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(item.image?.title ?? "未命名作品")
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.textPrimary)
                            .lineLimit(2)
                        Text(item.image?.author ?? "未知作者")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .lineLimit(1)
                        if let favoritedAt = item.favoritedAt {
                            Label(SetuDateFormatter.string(from: favoritedAt), systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(SetuColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Button(action: onMove) {
                            Label("移动到收藏夹", systemImage: "folder")
                        }
                        Button(role: .destructive, action: onRemove) {
                            Label("从默认收藏移除", systemImage: "heart.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("更多收藏操作")
                }
                .padding(SetuSpacing.md)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ContentGridImageView: View {
    let urlString: String?
    let accessibilityLabel: String

    var body: some View {
        SetuRemoteImage(
            urlString: urlString,
            accessibilityLabel: accessibilityLabel,
            width: nil,
            height: nil,
            cornerRadius: 0,
            allowsTapToRetry: false
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

private struct FavoriteMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: FavoriteItem
    let onMoved: () -> Void

    @State private var state: LoadState<[CollectionInfo]> = .idle
    @State private var selectedCollectionID: Int?
    @State private var isMoving = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "移动到收藏夹", subtitle: item.image?.title ?? "未命名作品")
                            switch state {
                            case .idle, .loading:
                                SetuEmptyState(title: "正在加载收藏夹", systemImage: "folder", isLoading: true)
                            case .failed(let text):
                                SetuEmptyState(title: "收藏夹加载失败", message: text, systemImage: "folder.badge.questionmark")
                            case .loaded(let collections):
                                if collections.isEmpty {
                                    SetuEmptyState(title: "没有可移动的收藏夹", message: "请先创建一个收藏夹", systemImage: "folder.badge.plus")
                                } else {
                                    Picker("目标收藏夹", selection: $selectedCollectionID) {
                                        ForEach(collections) { collection in
                                            Text(collection.name).tag(Optional(collection.id))
                                        }
                                    }
                                    Text("移动成功后，这张图片会从默认收藏中移除。")
                                        .font(.footnote)
                                        .foregroundStyle(SetuColor.textSecondary)
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
            .navigationTitle("移动收藏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("移动") { Task { await move() } }
                        .disabled(selectedCollectionID == nil || isMoving)
                }
            }
            .task { await loadCollections() }
        }
    }

    private func loadCollections() async {
        state = .loading
        do {
            let collections = try await environment.collectionClient.listMine().filter { !$0.isDefault }
            state = .loaded(collections)
            selectedCollectionID = collections.first?.id
        } catch {
            state = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func move() async {
        guard let selectedCollectionID else { return }
        isMoving = true
        feedback = nil
        defer { isMoving = false }
        do {
            try await environment.collectionClient.addItem(collectionID: selectedCollectionID, pid: item.pid, p: item.p)
            try await environment.favoriteClient.remove(pid: item.pid, p: item.p)
            onMoved()
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }
}

struct ContentImageStateSection: View {
    let title: String
    var message: String?
    var systemImage: String
    var isLoading = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        SetuCard {
            SetuEmptyState(
                title: title,
                message: message,
                systemImage: systemImage,
                isLoading: isLoading,
                actionTitle: actionTitle,
                action: action
            )
        }
        .setuListRow()
    }
}
