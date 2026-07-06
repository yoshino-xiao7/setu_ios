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

    var body: some View {
        List {
            createSection

            Picker("状态", selection: $statusFilter) {
                Text("全部").tag("ALL")
                Text("上传中").tag("UPLOADING")
                Text("待审核").tag("WAITING_MANUAL_REVIEW")
                Text("已发布").tag("PUBLISHED")
                Text("已拒绝").tag("REJECTED")
            }
            .pickerStyle(.segmented)
            .onChange(of: statusFilter) {
                Task { await load() }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("投稿批次加载失败", systemImage: "tray.full", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无投稿批次", systemImage: "tray")
                } else {
                    Section("共 \(page.total) 个批次") {
                        ForEach(page.list) { batch in
                            Button {
                                router.navigate(to: .galleryUploadDetail(batch.batchId))
                            } label: {
                                GalleryUploadBatchRow(batch: batch)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("图库投稿")
        .onChange(of: pickedItems) {
            Task { await loadPickedItems() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var createSection: some View {
        Section("新建投稿") {
            Picker("PID 模式", selection: $pidMode) {
                Text("多 PID 单页").tag("MULTI_PID_P0")
                Text("单 PID 多页").tag("SINGLE_PID_MULTI_PAGE")
            }
            TextField("统一标题", text: $title)
            TextField("统一作者", text: $author)
            TextField("标签，用逗号或空格分隔", text: $tagsText)
            Toggle("R18", isOn: $r18)
            Picker("AI 类型", selection: $aiType) {
                Text("非 AI").tag(1)
                Text("AI").tag(2)
            }
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 20, matching: .images) {
                Label("选择图片", systemImage: "photo.on.rectangle.angled")
            }
            if !uploadItems.isEmpty {
                ForEach(uploadItems) { item in
                    GalleryLocalUploadItemRow(item: item)
                }
            }
            if let uploadMessage {
                Text(uploadMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await submitUpload() }
            } label: {
                if isUploading {
                    ProgressView()
                } else {
                    Label("提交投稿", systemImage: "icloud.and.arrow.up")
                }
            }
            .disabled(isUploading || uploadItems.isEmpty)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.galleryUploadClient.listMine(status: statusFilter))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadPickedItems() async {
        guard !pickedItems.isEmpty else {
            uploadItems = []
            return
        }
        var nextItems: [LocalGalleryUploadItem] = []
        for (index, pickedItem) in pickedItems.enumerated() {
            guard let data = try? await pickedItem.loadTransferable(type: Data.self) else { continue }
            let type = pickedItem.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let preferredExtension = type.preferredFilenameExtension ?? "jpg"
            nextItems.append(LocalGalleryUploadItem(
                clientItemID: UUID().uuidString,
                filename: "ios-upload-\(index + 1).\(preferredExtension)",
                contentType: type.preferredMIMEType ?? "image/jpeg",
                data: data,
                pageIndex: index,
                status: "等待上传",
                progress: 0
            ))
        }
        uploadItems = nextItems
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
}

private struct LocalGalleryUploadItem: Identifiable {
    let clientItemID: String
    let filename: String
    let contentType: String
    let data: Data
    let pageIndex: Int
    var status: String
    var progress: Int

    var id: String { clientItemID }
}

private struct GalleryLocalUploadItemRow: View {
    let item: LocalGalleryUploadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.filename)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(item.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(item.progress), total: 100)
            Text("\(item.data.count / 1024) KB · p\(item.pageIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.title ?? "投稿批次 #\(batch.batchId)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(batch.author ?? "未知作者")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(batch.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 12) {
                Label("\(batch.itemCount)", systemImage: "photo")
                Label("\(batch.uploadedCount) 已传", systemImage: "icloud.and.arrow.up")
                Label("\(batch.publishedCount) 已发布", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(batch.createdAt)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
