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
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            switch infoState {
            case .idle, .loading:
                ProgressView("正在加载收藏夹")
            case .failed(let message):
                ContentUnavailableView("收藏夹加载失败", systemImage: "rectangle.stack.badge.minus", description: Text(message))
            case .loaded(let info):
                infoSection(info)
                actionSection(info)
            }

            switch itemsState {
            case .idle, .loading:
                ProgressView("正在加载图片")
            case .failed(let message):
                ContentUnavailableView("图片加载失败", systemImage: "photo.on.rectangle.angled", description: Text(message))
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentUnavailableView("暂无图片", systemImage: "photo", description: Text("收藏夹加入图片后会显示在这里。"))
                } else {
                    Section("共 \(page.total) 张") {
                        ForEach(page.items) { item in
                            CollectionItemRow(item: item) {
                                Task { await setCover(item) }
                            } onMove: {
                                moveContext = CollectionItemMoveContext(currentCollectionID: collectionID, item: item)
                            } onRemove: {
                                Task { await remove(item) }
                            }
                        }
                    }
                }
            }
        }
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
            HStack(alignment: .top, spacing: 12) {
                ImageThumbnailView(urlString: info.coverUrl ?? info.previewImages?.first?.bestURLString)
                VStack(alignment: .leading, spacing: 6) {
                    Text(info.name)
                        .font(.headline)
                    if let description = info.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Label(info.visibility.title, systemImage: info.visibility == .publicVisible ? "eye" : "lock")
                        Label("\(info.itemCount ?? 0) 张", systemImage: "photo")
                        if info.isShared == true {
                            Label("已分享", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let tags = info.tags, !tags.isEmpty {
                TagFlow(tags: tags)
            }

            if let note = info.curatorNote, !note.isEmpty {
                LabeledContent("推荐语", value: note)
            }
        }
    }

    @ViewBuilder
    private func actionSection(_ info: CollectionInfo) -> some View {
        Section {
            Button {
                Task { await toggleShare(info) }
            } label: {
                Label(info.isShared == true ? "取消分享到广场" : "分享到收藏夹广场", systemImage: info.isShared == true ? "square.and.arrow.down" : "square.and.arrow.up")
            }

            LabeledContent("浏览", value: "\(info.shareViewCount ?? 0)")
            LabeledContent("点赞", value: "\(info.likeCount ?? info.shareLikeCount ?? 0)")
            LabeledContent("收藏", value: "\(info.favoriteCount ?? info.shareFavCount ?? 0)")
        }
    }

    private func load() async {
        actionMessage = nil
        infoState = .loading
        itemsState = .loading
        do {
            async let info = environment.collectionClient.info(collectionID: collectionID)
            async let items = environment.collectionClient.items(collectionID: collectionID)
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
    let onSetCover: () -> Void
    let onMove: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: item.image?.urlSmall ?? item.image?.urlRegular ?? item.image?.urlOriginal)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.image?.title ?? "PID \(item.pid)")
                    .font(.headline)
                    .lineLimit(2)
                Text(item.image?.author ?? "未知作者")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.p)", systemImage: "number")
                    if let addedAt = item.addedAt {
                        Label(addedAt, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
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
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
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
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("图片") {
                    LabeledContent("标题", value: context.item.image?.title ?? "PID \(context.item.pid)")
                    LabeledContent("PID", value: "\(context.item.pid)-\(context.item.p)")
                }

                Section("目标收藏夹") {
                    switch collectionsState {
                    case .idle, .loading:
                        ProgressView("正在加载收藏夹")
                    case .failed(let message):
                        ContentUnavailableView("收藏夹加载失败", systemImage: "heart.slash", description: Text(message))
                    case .loaded(let collections):
                        let candidates = targetCollections(from: collections)
                        if candidates.isEmpty {
                            ContentUnavailableView("没有可选目标收藏夹", systemImage: "tray", description: Text("请先创建另一个收藏夹。"))
                        } else {
                            Picker("目标", selection: selectedCollectionBinding(candidates)) {
                                ForEach(candidates) { collection in
                                    Text(collection.name).tag(collection.id)
                                }
                            }
                        }
                    }
                }

                Section("操作") {
                    Picker("模式", selection: $mode) {
                        ForEach(CollectionItemMoveMode.allCases) { value in
                            Label(value.title, systemImage: value.systemImage)
                                .tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(mode == .move ? "移动会先复制到目标收藏夹，再从当前收藏夹移除。" : "复制会保留当前收藏夹中的图片。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
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
                        .background(.pink.opacity(0.12), in: Capsule())
                        .foregroundStyle(.pink)
                }
            }
        }
    }
}
