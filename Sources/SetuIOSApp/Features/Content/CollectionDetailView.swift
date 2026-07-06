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

private struct TagFlow: View {
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
