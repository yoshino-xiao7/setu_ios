import SetuIOSCore
import SwiftUI

struct CollectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    let collectionID: Int

    @State private var infoState: LoadState<CollectionInfo> = .idle
    @State private var items: [CollectionItem] = []
    @State private var total = 0
    @State private var nextPage = 1
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var initialError: String?
    @State private var loadMoreError: String?
    @State private var feedback: SetuFeedback?
    @State private var editor: CollectionEditorContext?
    @State private var moveContext: CollectionItemMoveContext?
    @State private var previewItem: UserImagePreviewItem?
    @State private var showingDeleteConfirmation = false
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

                switch infoState {
                case .idle, .loading:
                    SetuCard {
                        SetuEmptyState(title: "正在加载收藏夹", systemImage: "rectangle.stack", isLoading: true)
                    }
                case .failed(let message):
                    SetuCard {
                        SetuEmptyState(title: "收藏夹加载失败", message: message, systemImage: "rectangle.stack.badge.minus")
                    }
                case .loaded(let info):
                    infoSection(info)
                    actionSection(info)
                }

                if isInitialLoading {
                    SetuCard {
                        SetuEmptyState(title: "正在加载图片", systemImage: "photo.on.rectangle", isLoading: true)
                    }
                } else if items.isEmpty {
                    itemEmptyState
                } else {
                    SetuSectionHeader(title: "收藏图片", subtitle: "共 \(total) 张")
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(items) { item in
                            CollectionItemTile(item: item) {
                                previewItem = UserImagePreviewItem(collectionItem: item)
                            } onSetCover: {
                                Task { await setCover(item) }
                            } onMove: {
                                moveContext = CollectionItemMoveContext(currentCollectionID: collectionID, item: item)
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
        .navigationTitle(title)
        .toolbar {
            if case .loaded(let info) = infoState {
                Button {
                    editor = .edit(info)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("编辑收藏夹")

                if !info.isDefault {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除收藏夹")
                }
            }
        }
        .sheet(item: $editor) { context in
            CollectionEditorSheet(environment: environment, context: context) {
                feedback = .success("收藏夹信息已保存")
                Task { await loadFirstPage() }
            }
        }
        .sheet(item: $moveContext) { context in
            CollectionItemMoveSheet(environment: environment, context: context) { mode in
                feedback = .success(mode.completionMessage)
                Task { await loadFirstPage() }
            }
        }
        .sheet(item: $previewItem) { item in
            UserImagePreviewSheet(item: item)
        }
        .confirmationDialog("删除这个收藏夹？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除收藏夹", role: .destructive) {
                Task { await deleteCollection() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后收藏夹中的条目关系会被移除，此操作不可撤销。")
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    @ViewBuilder
    private var itemEmptyState: some View {
        if let initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "图片加载失败", message: initialError, systemImage: "photo.on.rectangle.angled")
                    Button("重试") {
                        Task { await loadFirstPage() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无图片", message: "收藏夹加入图片后会显示在这里。", systemImage: "photo")
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
        if !hasMore { return .complete("已加载全部 \(total) 张图片") }
        return .idle
    }

    private var title: String {
        if case .loaded(let info) = infoState {
            info.name
        } else {
            "收藏夹详情"
        }
    }

    @ViewBuilder
    private func infoSection(_ info: CollectionInfo) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                HStack(alignment: .top, spacing: SetuSpacing.md) {
                    SetuRemoteImage(
                        urlString: info.coverUrl ?? info.previewImages?.first?.bestURLString,
                        accessibilityLabel: "收藏夹「\(info.name)」封面"
                    )
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text(info.name)
                            .font(SetuTypography.title)
                            .foregroundStyle(SetuColor.textPrimary)
                        if let description = info.description, !description.isEmpty {
                            Text(description)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SetuSpacing.sm) {
                                SetuPill(text: info.visibility.title, systemImage: info.visibility == .publicVisible ? "eye" : "lock", tone: .brand)
                                SetuPill(text: "\(info.itemCount ?? 0) 张", systemImage: "photo", tone: .info)
                                if info.isShared == true {
                                    SetuPill(text: "已分享", systemImage: "square.and.arrow.up", tone: .success)
                                }
                            }
                        }
                    }
                }

                if let tags = info.tags, !tags.isEmpty {
                    TagFlow(tags: tags)
                }

                if let note = info.curatorNote, !note.isEmpty {
                    CollectionInfoRow(title: "推荐语", value: note)
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ info: CollectionInfo) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "分享与数据")
                Button {
                    Task { await toggleShare(info) }
                } label: {
                    Label(info.isShared == true ? "取消分享到广场" : "分享到收藏夹广场", systemImage: info.isShared == true ? "square.and.arrow.down" : "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(SetuColor.brandPink)

                if canShareLink(info) {
                    let url = publicShareURL(for: info)
                    Button {
                        copyShareLink(url)
                    } label: {
                        Label("复制分享链接", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(SetuColor.brandPink)

                    Link(destination: url) {
                        Label("打开公开预览", systemImage: "arrow.up.forward.square")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(SetuColor.brandPink)
                } else if !info.isDefault {
                    Text("公开链接需要先将收藏夹设为公开。")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }

                Divider()
                statsLayout {
                    SetuStatTile(title: "浏览", value: "\(info.shareViewCount ?? 0)", systemImage: "eye", color: SetuColor.info)
                    SetuStatTile(title: "点赞", value: "\(info.likeCount ?? info.shareLikeCount ?? 0)", systemImage: "heart", color: SetuColor.brandPink)
                    SetuStatTile(title: "收藏", value: "\(info.favoriteCount ?? info.shareFavCount ?? 0)", systemImage: "bookmark", color: SetuColor.success)
                }
            }
        }
    }

    private var statsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: SetuSpacing.sm))
            : AnyLayout(HStackLayout(spacing: SetuSpacing.sm))
    }

    private func canShareLink(_ info: CollectionInfo) -> Bool {
        !info.isDefault && info.visibility == .publicVisible
    }

    private func publicShareURL(for info: CollectionInfo) -> URL {
        environment.config.siteBaseURL
            .appendingPathComponent("c")
            .appendingPathComponent(String(info.id))
    }

    private func copyShareLink(_ url: URL) {
        PlatformClipboard.copy(url.absoluteString)
        feedback = .success("分享链接已复制")
    }

    private func loadFirstPage() async {
        isInitialLoading = items.isEmpty
        initialError = nil
        loadMoreError = nil
        if case .loaded = infoState {
            // Keep the current header visible while refreshing.
        } else {
            infoState = .loading
        }
        do {
            async let infoRequest = environment.collectionClient.info(collectionID: collectionID)
            async let itemsRequest = environment.collectionClient.items(collectionID: collectionID, page: 1, size: pageSize)
            let (info, result) = try await (infoRequest, itemsRequest)
            infoState = .loaded(info)
            items = result.items
            total = result.total
            nextPage = 2
        } catch {
            if case .loading = infoState {
                infoState = .failed("暂时无法加载收藏夹信息，请稍后重试。")
            }
            initialError = "暂时无法加载图片，请检查网络后重试。"
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
            let result = try await environment.collectionClient.items(
                collectionID: collectionID,
                page: requestedPage,
                size: pageSize
            )
            guard requestedPage == nextPage else { return }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !existingIDs.contains($0.id) })
            total = result.total
            nextPage += 1
        } catch {
            loadMoreError = "更多图片加载失败"
        }
    }

    private func toggleShare(_ info: CollectionInfo) async {
        feedback = nil
        do {
            if info.isShared == true {
                try await environment.collectionClient.unshare(collectionID: collectionID)
                feedback = .success("已取消分享到广场")
            } else {
                try await environment.collectionClient.share(collectionID: collectionID)
                feedback = .success("已分享到收藏夹广场")
            }
            await loadFirstPage()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func setCover(_ item: CollectionItem) async {
        feedback = nil
        do {
            try await environment.collectionClient.setCover(collectionID: collectionID, pid: item.pid, p: item.p)
            feedback = .success("封面已更新")
            await loadFirstPage()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func remove(_ item: CollectionItem) async {
        feedback = nil
        do {
            try await environment.collectionClient.removeItem(collectionID: collectionID, pid: item.pid, p: item.p)
            feedback = .success("已从收藏夹移除")
            await loadFirstPage()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func deleteCollection() async {
        feedback = nil
        do {
            try await environment.collectionClient.delete(collectionID: collectionID)
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }
}

private struct CollectionItemTile: View {
    let item: CollectionItem
    let onPreview: () -> Void
    let onSetCover: () -> Void
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
                        if let addedAt = item.addedAt {
                            Label(SetuDateFormatter.string(from: addedAt), systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(SetuColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Button(action: onSetCover) {
                            Label("设为封面", systemImage: "photo.badge.checkmark")
                        }
                        Button(action: onMove) {
                            Label("移动/复制", systemImage: "arrow.left.arrow.right")
                        }
                        Button(role: .destructive, action: onRemove) {
                            Label("移除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("更多图片操作")
                }
                .padding(SetuSpacing.md)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CollectionInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
            Spacer(minLength: SetuSpacing.md)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CollectionItemMoveContext: Identifiable {
    let currentCollectionID: Int
    let item: CollectionItem

    var id: String {
        "\(currentCollectionID)-\(item.pid)-\(item.p)"
    }
}

private enum CollectionItemMoveMode: String, CaseIterable, Identifiable {
    case move
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: "移动"
        case .copy: "复制"
        }
    }

    var systemImage: String {
        switch self {
        case .move: "arrow.right"
        case .copy: "doc.on.doc"
        }
    }

    var completionMessage: String {
        switch self {
        case .move: "已移动到目标收藏夹"
        case .copy: "已复制到目标收藏夹"
        }
    }
}

private struct CollectionItemMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let context: CollectionItemMoveContext
    let onSaved: (CollectionItemMoveMode) -> Void

    @State private var collectionsState: LoadState<[CollectionInfo]> = .idle
    @State private var selectedCollectionID: Int?
    @State private var mode: CollectionItemMoveMode = .move
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "图片")
                            CollectionInfoRow(title: "标题", value: context.item.image?.title ?? "未命名作品")
                        }
                    }
                }

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "目标收藏夹")
                            switch collectionsState {
                            case .idle, .loading:
                                SetuEmptyState(title: "正在加载收藏夹", systemImage: "heart", isLoading: true)
                            case .failed(let message):
                                SetuEmptyState(title: "收藏夹加载失败", message: message, systemImage: "heart.slash")
                            case .loaded(let collections):
                                let candidates = targetCollections(from: collections)
                                if candidates.isEmpty {
                                    SetuEmptyState(title: "没有可选目标收藏夹", message: "请先创建另一个收藏夹。", systemImage: "tray")
                                } else {
                                    Picker("目标", selection: selectedCollectionBinding(candidates)) {
                                        ForEach(candidates) { collection in
                                            Text(collection.name).tag(collection.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "操作")
                            Picker("模式", selection: $mode) {
                                ForEach(CollectionItemMoveMode.allCases) { value in
                                    Label(value.title, systemImage: value.systemImage)
                                        .tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(SetuColor.brandPink)

                            Text(mode == .move ? "移动会先复制到目标收藏夹，再从当前收藏夹移除。" : "复制会保留当前收藏夹中的图片。")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                }

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle("移动/复制")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        Task { await submit() }
                    }
                    .disabled(selectedCollectionID == nil)
                }
            }
            .task { await loadCollections() }
        }
    }

    private func targetCollections(from collections: [CollectionInfo]) -> [CollectionInfo] {
        collections.filter { $0.id != context.currentCollectionID }
    }

    private func selectedCollectionBinding(_ candidates: [CollectionInfo]) -> Binding<Int> {
        Binding {
            selectedCollectionID ?? candidates.first?.id ?? context.currentCollectionID
        } set: { newValue in
            selectedCollectionID = newValue
        }
    }

    private func loadCollections() async {
        collectionsState = .loading
        do {
            let collections = try await environment.collectionClient.listMine()
            collectionsState = .loaded(collections)
            let candidates = targetCollections(from: collections)
            if selectedCollectionID == nil {
                selectedCollectionID = candidates.first?.id
            }
        } catch {
            collectionsState = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func submit() async {
        guard let selectedCollectionID else { return }
        feedback = nil
        do {
            try await environment.collectionClient.addItem(
                collectionID: selectedCollectionID,
                pid: context.item.pid,
                p: context.item.p
            )
            if mode == .move {
                try await environment.collectionClient.removeItem(
                    collectionID: context.currentCollectionID,
                    pid: context.item.pid,
                    p: context.item.p
                )
            }
            onSaved(mode)
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }
}

struct TagFlow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SetuColor.brandSoft.opacity(0.18), in: Capsule())
                        .foregroundStyle(SetuColor.brandInk)
                }
            }
        }
    }
}
