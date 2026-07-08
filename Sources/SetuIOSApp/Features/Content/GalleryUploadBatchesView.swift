import SetuIOSCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct GalleryUploadBatchesView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<GalleryUploadBatchSummary>> = .idle
    @State private var statusFilter = "ALL"
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var uploadItems: [LocalGalleryUploadItem] = []
    @State private var pidMode = "MULTI_PID_P0"
    @State private var title = ""
    @State private var author = ""
    @State private var tagsText = ""
    @State private var r18 = false
    @State private var aiType = 1
    @State private var uploadMessage: String?
    @State private var isUploading = false
    @State private var draftRestored = false
    @State private var page = 1
    @State private var actionMessage: String?
    private let pageSize = 10

    var body: some View {
        List {
            createSection

            if let actionMessage {
                SetuCard {
                    Label(actionMessage, systemImage: "checkmark.circle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .setuListRow()
            }

            SetuCard {
                Picker("状态", selection: $statusFilter) {
                    Text("全部").tag("ALL")
                    Text("上传中").tag("UPLOADING")
                    Text("待审核").tag("WAITING_MANUAL_REVIEW")
                    Text("已发布").tag("PUBLISHED")
                    Text("已拒绝").tag("REJECTED")
                }
                .pickerStyle(.segmented)
            }
            .setuListRow()
            .onChange(of: statusFilter) {
                Task {
                    page = 1
                    await load()
                }
            }

            switch state {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载投稿批次", message: "正在同步你的投稿记录。", systemImage: "tray.full", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(title: "投稿批次加载失败", message: message, systemImage: "tray.full")
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentImageStateSection(title: "暂无投稿批次", message: "选择图片并提交后，批次会显示在这里。", systemImage: "tray")
                } else {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "共 \(page.total) 个批次", subtitle: "投稿记录")
                            ForEach(Array(page.list.enumerated()), id: \.element.id) { index, batch in
                                if index > 0 {
                                    Divider()
                                        .overlay(SetuColor.separator)
                                }
                                Button {
                                    router.navigate(to: .galleryUploadDetail(batch.batchId))
                                } label: {
                                    GalleryUploadBatchRow(batch: batch)
                                }
                                .buttonStyle(.plain)

                                if canCancel(batch) {
                                    Button(role: .destructive) {
                                        Task { await cancel(batch) }
                                    } label: {
                                        Label("取消投稿", systemImage: "xmark.circle")
                                            .frame(minHeight: 44, alignment: .leading)
                                    }
                                    .font(SetuTypography.caption)
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .setuListRow()
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("图库投稿")
        .onChange(of: pickedItems) {
            Task { await loadPickedItems() }
        }
        .onChange(of: pidMode) { saveDraft() }
        .onChange(of: title) { saveDraft() }
        .onChange(of: author) { saveDraft() }
        .onChange(of: tagsText) { saveDraft() }
        .onChange(of: r18) { saveDraft() }
        .onChange(of: aiType) { saveDraft() }
        .task {
            restoreDraftIfNeeded()
            await load()
        }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PageResult<GalleryUploadBatchSummary>) -> some View {
        SetuCard {
            HStack {
                Button {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()

                Button {
                    Task {
                        page += 1
                        await load()
                    }
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .frame(minHeight: 44)
                }
                .disabled(result.page * result.pageSize >= result.total)
            }
            .font(SetuTypography.body)
        }
        .setuListRow()
    }

    private var createSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "新建投稿", subtitle: "最多选择 20 张图片")
                Picker("PID 模式", selection: $pidMode) {
                    Text("多 PID 单页").tag("MULTI_PID_P0")
                    Text("单 PID 多页").tag("SINGLE_PID_MULTI_PAGE")
                }
                .pickerStyle(.segmented)
                TextField("统一标题", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("统一作者", text: $author)
                    .textFieldStyle(.roundedBorder)
                TextField("标签，用逗号或空格分隔", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                Toggle("R18", isOn: $r18)
                Picker("AI 类型", selection: $aiType) {
                    Text("非 AI").tag(1)
                    Text("AI").tag(2)
                }
                .pickerStyle(.segmented)
                PhotosPicker(selection: $pickedItems, maxSelectionCount: 20, matching: .images) {
                    Label("选择图片", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                if !uploadItems.isEmpty {
                    VStack(spacing: SetuSpacing.sm) {
                        ForEach(uploadItems) { item in
                            GalleryLocalUploadItemRow(item: item)
                        }
                    }
                    Button(role: .destructive) {
                        clearDraft()
                    } label: {
                        Label("清空草稿", systemImage: "trash")
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .disabled(isUploading)
                }
                if let uploadMessage {
                    Text(uploadMessage)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                Button {
                    Task { await submitUpload() }
                } label: {
                    Label(isUploading ? "提交中" : "提交投稿", systemImage: isUploading ? "hourglass" : "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
                .disabled(isUploading || uploadItems.isEmpty)
            }
        }
        .setuListRow()
    }

    private func load() async {
        state = .loading
        actionMessage = nil
        do {
            let status = statusFilter == "ALL" ? nil : statusFilter
            state = .loaded(try await environment.galleryUploadClient.listMine(status: status, page: page, pageSize: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func canCancel(_ batch: GalleryUploadBatchSummary) -> Bool {
        batch.status == "UPLOADING" || batch.status == "WAITING_MANUAL_REVIEW"
    }

    private func cancel(_ batch: GalleryUploadBatchSummary) async {
        do {
            try await environment.galleryUploadClient.cancel(batchID: batch.batchId)
            await load()
            actionMessage = "已取消批次 #\(batch.batchId)"
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func loadPickedItems() async {
        guard !pickedItems.isEmpty else {
            uploadItems = []
            saveDraft()
            return
        }
        var nextItems: [LocalGalleryUploadItem] = []
        for (index, pickedItem) in pickedItems.enumerated() {
            guard let data = try? await pickedItem.loadTransferable(type: Data.self) else { continue }
            let type = pickedItem.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let preferredExtension = type.preferredFilenameExtension ?? "jpg"
            let clientItemID = UUID().uuidString
            let filename = "ios-upload-\(index + 1).\(preferredExtension)"
            let storedFileName = "\(clientItemID)-\(filename)"
            try? GalleryUploadDraftStore.write(data: data, fileName: storedFileName)
            nextItems.append(LocalGalleryUploadItem(
                clientItemID: clientItemID,
                filename: filename,
                contentType: type.preferredMIMEType ?? "image/jpeg",
                data: data,
                storedFileName: storedFileName,
                pageIndex: index,
                status: "等待上传",
                progress: 0
            ))
        }
        uploadItems = nextItems
        saveDraft()
    }

    private func submitUpload() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedAuthor.isEmpty else {
            uploadMessage = "请填写统一标题和作者"
            return
        }
        guard !uploadItems.isEmpty else {
            uploadMessage = "请选择图片"
            return
        }

        isUploading = true
        uploadMessage = nil
        do {
            let tags = parseTags(tagsText)
            let initItems = uploadItems.map { item in
                GalleryUploadInitItem(
                    clientItemId: item.clientItemID,
                    filename: item.filename,
                    contentType: item.contentType,
                    sizeBytes: item.data.count,
                    pageIndex: pidMode == "SINGLE_PID_MULTI_PAGE" ? item.pageIndex : nil
                )
            }
            let initResponse = try await environment.galleryUploadClient.createBatch(GalleryUploadInitRequest(
                clientRequestId: UUID().uuidString,
                pidMode: pidMode,
                defaults: GalleryUploadDefaults(title: trimmedTitle, author: trimmedAuthor, r18: r18, aiType: aiType, tags: tags.isEmpty ? nil : tags),
                items: initItems
            ))
            var completedItems: [GalleryUploadCompleteItem] = []

            for index in uploadItems.indices {
                let localItem = uploadItems[index]
                guard let preparedItem = initResponse.items.first(where: { $0.clientItemId == localItem.clientItemID }) ?? initResponse.items[safe: index],
                      let objectKey = preparedItem.objectKey else {
                    throw APIError.invalidResponse
                }

                uploadItems[index].status = "上传中"
                uploadItems[index].progress = 15
                saveDraft()
                _ = try? await environment.galleryUploadClient.updateItemStatus(
                    batchID: initResponse.batchId,
                    clientItemID: localItem.clientItemID,
                    request: GalleryUploadItemStatusRequest(uploadStatus: "UPLOADING", objectKey: objectKey)
                )
                let etag = try await environment.galleryUploadClient.uploadPreparedItem(
                    initResponse: initResponse,
                    item: preparedItem,
                    data: localItem.data,
                    contentType: localItem.contentType
                )
                uploadItems[index].status = "已上传"
                uploadItems[index].progress = 100
                saveDraft()
                _ = try? await environment.galleryUploadClient.updateItemStatus(
                    batchID: initResponse.batchId,
                    clientItemID: localItem.clientItemID,
                    request: GalleryUploadItemStatusRequest(uploadStatus: "UPLOADED", objectKey: objectKey)
                )
                completedItems.append(GalleryUploadCompleteItem(
                    submissionId: preparedItem.submissionId,
                    objectKey: objectKey,
                    etag: etag
                ))
            }

            let completeResponse = try await environment.galleryUploadClient.completeBatch(batchID: initResponse.batchId, items: completedItems)
            uploadMessage = "投稿批次 #\(completeResponse.batchId) 已提交审核"
            pickedItems = []
            uploadItems = []
            GalleryUploadDraftStore.clear()
            await load()
        } catch {
            uploadMessage = error.localizedDescription
        }
        isUploading = false
    }

    private func parseTags(_ rawValue: String) -> [String] {
        rawValue
            .split { character in
                character == "," || character == "，" || character == " " || character == "\n"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func restoreDraftIfNeeded() {
        guard !draftRestored else { return }
        draftRestored = true
        guard let draft = GalleryUploadDraftStore.load() else { return }

        pidMode = draft.form.pidMode == "SINGLE_PID_MULTI_PAGE" ? draft.form.pidMode : "MULTI_PID_P0"
        title = draft.form.title
        author = draft.form.author
        tagsText = draft.form.tagsText
        r18 = draft.form.r18
        aiType = draft.form.aiType

        let restoredItems = draft.items.compactMap { item -> LocalGalleryUploadItem? in
            guard let data = GalleryUploadDraftStore.readData(fileName: item.storedFileName) else { return nil }
            return LocalGalleryUploadItem(
                clientItemID: item.clientItemID,
                filename: item.filename,
                contentType: item.contentType,
                data: data,
                storedFileName: item.storedFileName,
                pageIndex: item.pageIndex,
                status: item.status,
                progress: item.progress
            )
        }
        uploadItems = restoredItems

        if !draft.isMeaningful {
            GalleryUploadDraftStore.clear()
        } else if restoredItems.count == draft.items.count, !restoredItems.isEmpty {
            uploadMessage = "已自动恢复上次未完成的投稿图片和填写内容"
        } else if !draft.items.isEmpty {
            uploadMessage = "已恢复上次填写的投稿草稿，部分图片需要重新选择"
        } else {
            uploadMessage = "已恢复上次填写的投稿草稿"
        }
    }

    private func saveDraft() {
        guard draftRestored, !isUploading else { return }
        let draft = GalleryUploadDraftPayload(
            form: GalleryUploadDraftFormPayload(
                pidMode: pidMode,
                title: title,
                author: author,
                r18: r18,
                aiType: aiType,
                tagsText: tagsText
            ),
            items: uploadItems.map(GalleryUploadDraftItemPayload.init(item:))
        )
        GalleryUploadDraftStore.save(draft)
    }

    private func clearDraft() {
        pickedItems = []
        uploadItems = []
        pidMode = "MULTI_PID_P0"
        title = ""
        author = ""
        tagsText = ""
        r18 = false
        aiType = 1
        uploadMessage = nil
        GalleryUploadDraftStore.clear()
    }
}

private struct LocalGalleryUploadItem: Identifiable {
    let clientItemID: String
    let filename: String
    let contentType: String
    let data: Data
    let storedFileName: String
    let pageIndex: Int
    var status: String
    var progress: Int

    var id: String { clientItemID }
}

private struct GalleryLocalUploadItemRow: View {
    let item: LocalGalleryUploadItem

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            HStack {
                Text(item.filename)
                    .font(SetuTypography.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(item.status)
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            ProgressView(value: Double(item.progress), total: 100)
                .tint(SetuColor.brandPink)
            Text("\(item.data.count / 1024) KB · p\(item.pageIndex)")
                .font(.caption)
                .foregroundStyle(SetuColor.textTertiary)
        }
    }
}

private struct GalleryUploadDraftPayload: Codable {
    let version: Int
    let updatedAt: Date
    let form: GalleryUploadDraftFormPayload
    let items: [GalleryUploadDraftItemPayload]

    init(form: GalleryUploadDraftFormPayload, items: [GalleryUploadDraftItemPayload]) {
        self.version = 1
        self.updatedAt = Date()
        self.form = form
        self.items = items
    }

    var isMeaningful: Bool {
        !items.isEmpty
            || !form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !form.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || form.r18
            || form.aiType != 1
            || !form.tagsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || form.pidMode != "MULTI_PID_P0"
    }
}

private struct GalleryUploadDraftFormPayload: Codable {
    let pidMode: String
    let title: String
    let author: String
    let r18: Bool
    let aiType: Int
    let tagsText: String
}

private struct GalleryUploadDraftItemPayload: Codable {
    let clientItemID: String
    let filename: String
    let contentType: String
    let storedFileName: String
    let sizeBytes: Int
    let pageIndex: Int
    let status: String
    let progress: Int

    init(item: LocalGalleryUploadItem) {
        self.clientItemID = item.clientItemID
        self.filename = item.filename
        self.contentType = item.contentType
        self.storedFileName = item.storedFileName
        self.sizeBytes = item.data.count
        self.pageIndex = item.pageIndex
        self.status = item.status
        self.progress = item.progress
    }
}

private enum GalleryUploadDraftStore {
    private static let key = "icu.yukiryou.setu.galleryUploadDraft"

    static func load() -> GalleryUploadDraftPayload? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GalleryUploadDraftPayload.self, from: data)
    }

    static func save(_ draft: GalleryUploadDraftPayload) {
        guard draft.isMeaningful else {
            clear()
            return
        }
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func write(data: Data, fileName: String) throws {
        let targetURL = try directory().appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: targetURL, options: .atomic)
    }

    static func readData(fileName: String) -> Data? {
        guard let fileURL = try? directory().appendingPathComponent(fileName, isDirectory: false) else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        guard let directoryURL = try? directory(create: false) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func directory(create: Bool = true) throws -> URL {
        let cachesURL = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = cachesURL.appendingPathComponent("GalleryUploadDraft", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct GalleryUploadBatchRow: View {
    let batch: GalleryUploadBatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.title ?? "投稿批次 #\(batch.batchId)")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(batch.author ?? "未知作者")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                Spacer()
                GalleryUploadStatusPill(status: batch.status, title: batch.statusTitle)
            }

            HStack(spacing: 12) {
                Label("\(batch.itemCount)", systemImage: "photo")
                Label("\(batch.uploadedCount) 已传", systemImage: "icloud.and.arrow.up")
                Label("\(batch.publishedCount) 已发布", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(SetuColor.textTertiary)

            Text(batch.createdAt)
                .font(.caption)
                .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

struct GalleryUploadStatusPill: View {
    let status: String
    let title: String

    var body: some View {
        SetuPill(text: title, systemImage: "flag", tone: tone)
    }

    private var tone: SetuPillTone {
        switch status {
        case "PUBLISHED":
            .success
        case "REJECTED", "CANCELED":
            .danger
        case "UPLOADING", "WAITING_MANUAL_REVIEW":
            .warning
        default:
            .muted
        }
    }
}
