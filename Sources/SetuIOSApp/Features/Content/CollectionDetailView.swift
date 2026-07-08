import SetuIOSCore
import SwiftUI

struct CollectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let collectionID: Int

    @State private var infoState: LoadState<CollectionInfo> = .idle
    @State private var itemsState: LoadState<CollectionItemPage> = .idle
    @State private var actionMessage: String?
    @State private var editor: CollectionEditorContext?
    @State private var moveContext: CollectionItemMoveContext?
    @State private var previewItem: CollectionImagePreviewItem?
    @State private var showingDeleteConfirmation = false
    @State private var page = 1
    private let pageSize = 24

    var body: some View {
        List {
            if let actionMessage {
                Section {
                    SetuPill(text: actionMessage, systemImage: "info.circle", tone: .info)
                }
            }

            switch infoState {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载收藏夹", systemImage: "rectangle.stack", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "收藏夹加载失败", message: message, systemImage: "rectangle.stack.badge.minus")
                    }
                }
            case .loaded(let info):
                infoSection(info)
                actionSection(info)
            }

            switch itemsState {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载图片", systemImage: "photo.on.rectangle", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "图片加载失败", message: message, systemImage: "photo.on.rectangle.angled")
                    }
                }
            case .loaded(let page):
                if page.items.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(title: "暂无图片", message: "收藏夹加入图片后会显示在这里。", systemImage: "photo")
                        }
                    }
                } else {
                    Section {
                        SetuCard {
                            SetuSectionHeader(title: "收藏图片", subtitle: "共 \(page.total) 张")
                        }
                    }
                    Section {
                        ForEach(page.items) { item in
                            SetuCard {
                                CollectionItemRow(item: item) {
                                    previewItem = CollectionImagePreviewItem(item: item)
                                } onSetCover: {
                                    Task { await setCover(item) }
                                } onMove: {
                                    moveContext = CollectionItemMoveContext(currentCollectionID: collectionID, item: item)
                                } onRemove: {
                                    Task { await remove(item) }
                                }
                            }
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle(title)
        .toolbar {
            if case .loaded(let info) = infoState {
                Button {
                    editor = .edit(info)
                } label: {
                    Image(systemName: "square.and.pencil")
                }

                if !info.isDefault {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .sheet(item: $editor) { context in
            CollectionEditorSheet(environment: environment, context: context) {
                Task { await load() }
            }
        }
        .sheet(item: $moveContext) { context in
            CollectionItemMoveSheet(environment: environment, context: context) { mode in
                actionMessage = mode.completionMessage
                Task { await load() }
            }
        }
        .sheet(item: $previewItem) { item in
            CollectionImagePreviewSheet(item: item)
        }
        .confirmationDialog("删除这个收藏夹？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除收藏夹", role: .destructive) {
                Task { await deleteCollection() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后收藏夹中的条目关系会被移除，此操作不可撤销。")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: CollectionItemPage) -> some View {
        Section {
            SetuCard {
                HStack {
                    Button("上一页") {
                        Task {
                            page = max(1, page - 1)
                            await load()
                        }
                    }
                    .disabled(page <= 1)

                    Spacer()
                    Text("第 \(result.page) 页")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    Spacer()

                    Button("下一页") {
                        Task {
                            page += 1
                            await load()
                        }
                    }
                    .disabled(result.page * result.size >= result.total)
                }
                .buttonStyle(.bordered)
                .tint(SetuColor.brandPink)
            }
        }
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
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        ImageThumbnailView(urlString: info.coverUrl ?? info.previewImages?.first?.bestURLString)
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            Text(info.name)
                                .font(SetuTypography.title)
                                .foregroundStyle(SetuColor.textPrimary)
                            if let description = info.description, !description.isEmpty {
                                Text(description)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            HStack(spacing: SetuSpacing.sm) {
                                SetuPill(text: info.visibility.title, systemImage: info.visibility == .publicVisible ? "eye" : "lock", tone: .brand)
                                SetuPill(text: "\(info.itemCount ?? 0) 张", systemImage: "photo", tone: .info)
                                if info.isShared == true {
                                    SetuPill(text: "已分享", systemImage: "square.and.arrow.up", tone: .success)
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
    }

    @ViewBuilder
    private func actionSection(_ info: CollectionInfo) -> some View {
        Section {
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
                    HStack {
                        SetuStatTile(title: "浏览", value: "\(info.shareViewCount ?? 0)", systemImage: "eye", color: SetuColor.info)
                        SetuStatTile(title: "点赞", value: "\(info.likeCount ?? info.shareLikeCount ?? 0)", systemImage: "heart", color: SetuColor.brandPink)
                        SetuStatTile(title: "收藏", value: "\(info.favoriteCount ?? info.shareFavCount ?? 0)", systemImage: "bookmark", color: SetuColor.success)
                    }
                }
            }
        }
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
        actionMessage = "分享链接已复制"
    }

    private func load() async {
        actionMessage = nil
        infoState = .loading
        itemsState = .loading
        do {
            async let info = environment.collectionClient.info(collectionID: collectionID)
            async let items = environment.collectionClient.items(collectionID: collectionID, page: page, size: pageSize)
            infoState = .loaded(try await info)
            itemsState = .loaded(try await items)
        } catch {
            let message = error.localizedDescription
            if case .loading = infoState {
                infoState = .failed(message)
            }
            if case .loading = itemsState {
                itemsState = .failed(message)
            }
        }
    }

    private func toggleShare(_ info: CollectionInfo) async {
        actionMessage = nil
        do {
            if info.isShared == true {
                try await environment.collectionClient.unshare(collectionID: collectionID)
                actionMessage = "已取消分享到广场"
            } else {
                try await environment.collectionClient.share(collectionID: collectionID)
                actionMessage = "已分享到收藏夹广场"
            }
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func setCover(_ item: CollectionItem) async {
        actionMessage = nil
        do {
            try await environment.collectionClient.setCover(collectionID: collectionID, pid: item.pid, p: item.p)
            actionMessage = "封面已更新"
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func remove(_ item: CollectionItem) async {
        actionMessage = nil
        do {
            try await environment.collectionClient.removeItem(collectionID: collectionID, pid: item.pid, p: item.p)
            actionMessage = "已从收藏夹移除"
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func deleteCollection() async {
        actionMessage = nil
        do {
            try await environment.collectionClient.delete(collectionID: collectionID)
            dismiss()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct CollectionItemRow: View {
    let item: CollectionItem
    let onPreview: () -> Void
    let onSetCover: () -> Void
    let onMove: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: item.image?.urlSmall ?? item.image?.urlRegular ?? item.image?.urlOriginal)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.image?.title ?? "PID \(item.pid)")
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.image?.author ?? "未知作者")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.p)", systemImage: "number")
                    if let addedAt = item.addedAt {
                        Label(addedAt, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
            }
            Spacer()
            Button {
                onPreview()
            } label: {
                Image(systemName: "eye")
                    .font(.title3)
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("查看图片")

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
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SetuSpacing.xs)
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

struct CollectionImagePreviewItem: Identifiable {
    let item: CollectionItem

    var id: Int { item.id }

    var image: FavoriteImage? { item.image }

    var title: String {
        image?.title ?? "PID \(item.pid)"
    }

    var author: String {
        image?.author ?? "未知作者"
    }

    var bestURLString: String? {
        image?.urlOriginal ?? image?.urlRegular ?? image?.urlSmall
    }

    var displayURLString: String? {
        image?.urlRegular ?? image?.urlSmall ?? image?.urlOriginal
    }
}

struct CollectionImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: CollectionImagePreviewItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageStage
                    metadata
                }
                .padding()
            }
            .setuBackground()
            .navigationTitle("图片预览")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        if let urlString = item.bestURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                case .failure:
                    SetuCard {
                        SetuEmptyState(title: "图片加载失败", message: "可以返回列表稍后再试。", systemImage: "photo")
                    }
                        .frame(maxWidth: .infinity, minHeight: 320)
                default:
                    SetuCard {
                        SetuEmptyState(title: "正在加载图片", systemImage: "photo", isLoading: true)
                    }
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无图片链接", systemImage: "photo")
            }
                .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private var metadata: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                Text(item.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .textSelection(.enabled)
                Text(item.author)
                    .font(.subheadline)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: SetuSpacing.sm) {
                    SetuPill(text: "\(item.item.pid)-\(item.item.p)", systemImage: "number", tone: .info)
                    if let image = item.image {
                        SetuPill(text: "\(image.width)x\(image.height)", systemImage: "aspectratio", tone: .muted)
                        if image.r18 == 1 {
                            SetuPill(text: "R18", systemImage: "exclamationmark.triangle", tone: .danger)
                        }
                    }
                }

                if let tags = item.image?.tags, !tags.isEmpty {
                    TagFlow(tags: tags)
                }

                if let urlString = item.displayURLString {
                    Text(urlString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(SetuColor.textSecondary)
                        .textSelection(.enabled)
                }
            }
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
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "图片")
                            CollectionInfoRow(title: "标题", value: context.item.image?.title ?? "PID \(context.item.pid)")
                            CollectionInfoRow(title: "PID", value: "\(context.item.pid)-\(context.item.p)")
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

                if let message {
                    Section {
                        SetuPill(text: message, systemImage: "exclamationmark.triangle", tone: .danger)
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
            collectionsState = .failed(error.localizedDescription)
        }
    }

    private func submit() async {
        guard let selectedCollectionID else { return }
        message = nil
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
            message = error.localizedDescription
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
