import PhotosUI
import SetuIOSCore
import SwiftUI
import UniformTypeIdentifiers

struct AdminCloudVideosView: View {
    @Bindable var environment: AppEnvironment
    @State private var catalog: LoadState<PageResult<AdminCloudVideoItem>> = .idle
    @State private var page = 1
    @State private var statusFilter = "ALL"
    @State private var ratingFilter = "ALL"
    @State private var keywords = ""
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showingFiles = false
    @State private var composeDrafts: [CloudVideoUploadDraft] = []
    @State private var showingCompose = false
    @State private var editing: AdminCloudVideoItem?
    @State private var message: String?
    @State private var isLoadingCatalog = false

    private var store: CloudVideoUploadStore { environment.cloudVideoUploadStore }
    private var client: AdminCloudVideoClient { environment.adminCloudVideoClient }
    private let pageSize = 20

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "需要管理员权限", message: "请使用管理员账号登录后再上传云视频。", systemImage: "shield.slash")
                    }
                }
                .setuListRow()
            } else {
                actionsSection
                if let message {
                    Section {
                        SetuPill(text: message, systemImage: "info.circle", tone: .brand)
                    }
                    .setuListRow()
                }
                queueSection
                filtersSection
                catalogSection
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("云视频")
        .task { await loadCatalog() }
        .refreshable { await loadCatalog() }
        .task(id: store.items.map(\.session?.id)) {
            await refreshEncodingRows()
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            Task { await refreshEncodingRows() }
        }
        .fileImporter(
            isPresented: $showingFiles,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .avi],
            allowsMultipleSelection: true
        ) { result in
            Task { await importFiles(result) }
        }
        .onChange(of: pickedPhotos) { _, items in
            Task { await importPhotos(items) }
        }
        .sheet(isPresented: $showingCompose) {
            CloudVideoUploadComposeSheet(drafts: $composeDrafts) { confirmed in
                store.enqueue(confirmed)
                showingCompose = false
                composeDrafts = []
            }
        }
        .sheet(item: $editing) { item in
            AdminCloudVideoEditSheet(item: item, client: client) {
                editing = nil
                Task { await loadCatalog(silent: true) }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "上传", subtitle: store.busy ? store.summary : "相册和文件都会进入同一队列")
                    Toggle("仅 Wi-Fi 上传", isOn: Binding(
                        get: { store.wifiOnly },
                        set: { store.wifiOnly = $0; store.startIfNeeded() }
                    ))
                    HStack(spacing: SetuSpacing.md) {
                        PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 40, matching: .videos) {
                            Label(store.busy ? "继续添加" : "从相册添加", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SetuColor.brandPink)
                        Button {
                            showingFiles = true
                        } label: {
                            Label("从文件添加", systemImage: "folder")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    if store.pauseReason == .session {
                        Button("重新尝试队列") { store.resume() }
                    }
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var queueSection: some View {
        if !store.items.isEmpty {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "本机队列", subtitle: store.summary)
                        ForEach(store.items) { item in
                            AdminCloudVideoQueueRow(item: item) {
                                store.retry(id: item.id)
                            } cancel: {
                                store.cancel(id: item.id)
                            }
                            if item.id != store.items.last?.id {
                                Divider().overlay(SetuColor.separator)
                            }
                        }
                    }
                }
            }
            .setuListRow()
        }
    }

    private var filtersSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "目录筛选")
                    TextField("标题或标签", text: $keywords)
                        .textFieldStyle(.roundedBorder)
                    Picker("状态", selection: $statusFilter) {
                        Text("全部").tag("ALL")
                        Text("上传中").tag("uploading")
                        Text("转码中").tag("encoding")
                        Text("已就绪").tag("ready")
                        Text("失败").tag("failed")
                    }
                    .pickerStyle(.segmented)
                    Picker("分级", selection: $ratingFilter) {
                        Text("全部分级").tag("ALL")
                        Text("全年龄").tag("all_ages")
                        Text("R18").tag("r18")
                    }
                    .pickerStyle(.segmented)
                    Button {
                        Task { await loadCatalog(resetPage: true) }
                    } label: {
                        Label("筛选目录", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SetuColor.brandPink)
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var catalogSection: some View {
        switch catalog {
        case .idle, .loading:
            Section {
                SetuCard {
                    SetuEmptyState(title: "正在加载云视频目录", systemImage: "film", isLoading: true)
                }
            }
            .setuListRow()
        case .failed(let error):
            Section {
                SetuCard {
                    SetuEmptyState(title: "目录加载失败", message: error.message, systemImage: "exclamationmark.triangle", userFacingError: error)
                }
            }
            .setuListRow()
        case .loaded(let pageResult):
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "目录 · \(pageResult.total)", subtitle: "草稿、转码和已发布")
                        if pageResult.list.isEmpty {
                            Text("还没有云视频。选片后会先进入本机队列。")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                        ForEach(pageResult.list) { item in
                            Button {
                                editing = item
                            } label: {
                                AdminCloudVideoCatalogRow(item: item)
                            }
                            .buttonStyle(.plain)
                            if item.id != pageResult.list.last?.id {
                                Divider().overlay(SetuColor.separator)
                            }
                        }
                    }
                }
            }
            .setuListRow()
            if pageResult.total > pageSize {
                Section {
                    SetuCard {
                        HStack {
                            Button("上一页") {
                                page = max(1, page - 1)
                                Task { await loadCatalog() }
                            }
                            .disabled(page <= 1)
                            Spacer()
                            Text("第 \(page) 页")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                            Spacer()
                            Button("下一页") {
                                page += 1
                                Task { await loadCatalog() }
                            }
                            .disabled(page * pageSize >= pageResult.total)
                        }
                    }
                }
                .setuListRow()
            }
        }
    }

    private func loadCatalog(resetPage: Bool = false, silent: Bool = false) async {
        guard environment.authSession.currentUser?.role == .admin, !isLoadingCatalog else { return }
        if resetPage { page = 1 }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        if !silent { catalog = .loading }
        do {
            catalog = .loaded(try await client.list(
                status: statusFilter == "ALL" ? nil : statusFilter,
                keywords: keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : keywords,
                rating: ratingFilter == "ALL" ? nil : ratingFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            catalog = .failed(error.localizedDescription)
        }
    }

    private func refreshEncodingRows() async {
        guard case .loaded(let pageResult) = catalog else {
            await loadCatalog(silent: true)
            return
        }
        let encoding = pageResult.list.filter(\.isEncoding)
        guard !encoding.isEmpty else { return }
        for item in encoding {
            _ = try? await client.syncAdminCloudVideo(id: item.id)
        }
        await loadCatalog(silent: true)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var drafts: [CloudVideoUploadDraft] = []
        for item in items {
            guard let file = try? await item.loadTransferable(type: CloudVideoImportedFile.self) else { continue }
            drafts.append(draft(from: file.url))
        }
        pickedPhotos = []
        presentCompose(drafts)
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            presentCompose(urls.map(draft(from:)))
        }
    }

    private func presentCompose(_ drafts: [CloudVideoUploadDraft]) {
        guard !drafts.isEmpty else {
            message = "没有可用的视频文件"
            return
        }
        composeDrafts = drafts
        showingCompose = true
    }

    private func draft(from url: URL) -> CloudVideoUploadDraft {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let name = url.deletingPathExtension().lastPathComponent
        return CloudVideoUploadDraft(
            title: name.isEmpty ? "未命名视频" : name,
            fileName: url.lastPathComponent,
            sourceURL: url,
            byteCount: size
        )
    }
}

private struct CloudVideoImportedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        movieRepresentation(.movie)
        movieRepresentation(.mpeg4Movie)
        movieRepresentation(.quickTimeMovie)
        movieRepresentation(.avi)
    }

    private static func movieRepresentation(_ type: UTType) -> FileRepresentation<CloudVideoImportedFile> {
        FileRepresentation(
            contentType: type,
            exporting: { item in SentTransferredFile(item.url) },
            importing: { received in try importFile(received) }
        )
    }

    private static func importFile(_ received: ReceivedTransferredFile) throws -> CloudVideoImportedFile {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(received.file.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: received.file, to: copy)
        return CloudVideoImportedFile(url: copy)
    }
}

private struct AdminCloudVideoQueueRow: View {
    let item: CloudVideoUploadItem
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack {
                Text(item.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                Spacer()
                Text(item.rating == "r18" ? "R18" : "全年龄")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            ProgressView(value: item.fraction)
            Text(statusText)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
            HStack {
                if item.phase == .failed {
                    Button("重试", action: retry)
                }
                Button("移除", role: .destructive, action: cancel)
            }
            .font(SetuTypography.caption)
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    private var statusText: String {
        switch item.phase {
        case .preparing: "正在准备本地副本"
        case .queued: item.attempts > 0 ? "等待续传" : "排队中"
        case .waitingForWifi: "等待 Wi-Fi"
        case .uploading: item.attempts > 0 ? "续传 \(item.percent)%" : "上传中 \(item.percent)%"
        case .syncing: "正在同步转码状态"
        case .failed: item.lastError ?? "失败"
        }
    }
}

private struct AdminCloudVideoCatalogRow: View {
    let item: AdminCloudVideoItem

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(item.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                Text("\(item.statusText) · \(item.visibilityText) · \(item.ratingText) · \(item.durationText)")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                if item.isEncoding, let progress = item.encodeProgress {
                    ProgressView(value: Double(progress), total: 100)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(SetuColor.textSecondary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct CloudVideoUploadComposeSheet: View {
    @Binding var drafts: [CloudVideoUploadDraft]
    let onConfirm: ([CloudVideoUploadDraft]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach($drafts) { $draft in
                    Section {
                        TextField("标题", text: $draft.title)
                        Picker("分级", selection: $draft.rating) {
                            Text("全年龄").tag("all_ages")
                            Text("R18").tag("r18")
                        }
                        Text(draft.fileName)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
            }
            .navigationTitle("确认上传")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入队列") { onConfirm(drafts) }
                        .disabled(drafts.isEmpty)
                }
            }
        }
    }
}

private struct AdminCloudVideoEditSheet: View {
    let item: AdminCloudVideoItem
    let client: AdminCloudVideoClient
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var tags: String
    @State private var visibility: String
    @State private var rating: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(item: AdminCloudVideoItem, client: AdminCloudVideoClient, onFinished: @escaping () -> Void) {
        self.item = item
        self.client = client
        self.onFinished = onFinished
        _title = State(initialValue: item.title)
        _description = State(initialValue: item.description ?? "")
        _tags = State(initialValue: item.tags ?? "")
        _visibility = State(initialValue: item.visibility ?? "draft")
        _rating = State(initialValue: item.rating ?? "all_ages")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("标题", text: $title)
                TextField("简介", text: $description, axis: .vertical)
                TextField("标签", text: $tags)
                Picker("分级", selection: $rating) {
                    Text("全年龄").tag("all_ages")
                    Text("R18").tag("r18")
                }
                Picker("可见性", selection: $visibility) {
                    Text("草稿").tag("draft")
                    Text("发布").tag("published")
                }
                .disabled(!item.canPublish && visibility == "published")
                if !item.canPublish {
                    Text("转码完成前不能发布")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                Button("从 Bunny 同步") {
                    Task { await sync() }
                }
                Button("删除这条云视频", role: .destructive) {
                    Task { await deleteVideo() }
                }
            }
            .navigationTitle("编辑云视频")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            _ = try await client.updateAdminCloudVideo(
                id: item.id,
                update: AdminCloudVideoUpdate(
                    title: title,
                    description: description,
                    tags: tags,
                    visibility: visibility,
                    rating: rating
                )
            )
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sync() async {
        do {
            _ = try await client.syncAdminCloudVideo(id: item.id)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteVideo() async {
        do {
            try await client.deleteAdminCloudVideo(id: item.id)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
