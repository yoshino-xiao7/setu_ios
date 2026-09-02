import SetuIOSCore
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
private typealias GalleryUploadPlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias GalleryUploadPlatformImage = NSImage
#endif

struct GalleryUploadBatchesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<GalleryUploadBatchSummary>(pageSize: 10)
    private var batches: [GalleryUploadBatchSummary] {
        get { pager.items }
        nonmutating set { pager.replaceItems(newValue) }
    }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    @State private var statusFilter = "ALL"
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var uploadItems: [LocalGalleryUploadItem] = []
    @State private var pidMode = "MULTI_PID_P0"
    @State private var title = ""
    @State private var author = ""
    @State private var tagsText = ""
    @State private var r18 = false
    @State private var aiType = 1
    @State private var uploadFeedback: SetuFeedback?
    @State private var isUploading = false
    @State private var isLoadingPickedItems = false
    @State private var draftRestored = false
    @State private var actionFeedback: SetuFeedback?
    @State private var uploadStep = GalleryUploadStep.images
    @State private var clientRequestID = UUID().uuidString
    @State private var showingExitConfirmation = false
    @State private var cancellationCandidate: GalleryUploadBatchSummary?
    private let pageSize = 10

    var body: some View {
        List {
            createSection

            if let actionFeedback {
                SetuFeedbackBanner(feedback: actionFeedback)
                .setuListRow()
            }

            SetuCard {
                adaptiveStatusPicker
            }
            .setuListRow()
            .onChange(of: statusFilter) {
                Task { await loadFirstPage(clearExisting: true) }
            }

            if isInitialLoading {
                ContentImageStateSection(title: "正在加载投稿记录", message: "正在同步你的投稿记录。", systemImage: "tray.full", isLoading: true)
            } else if batches.isEmpty {
                if let loadError {
                    SetuCard {
                        SetuEmptyState(
                            title: "投稿记录加载失败",
                            message: loadError,
                            systemImage: "tray.full",
                            actionTitle: "重试",
                            action: { Task { await loadFirstPage() } }
                        )
                    }
                    .setuListRow()
                } else {
                    ContentImageStateSection(title: "暂无投稿记录", message: "选择图片并提交后，审核进度会显示在这里。", systemImage: "tray")
                }
            } else {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(total) 条投稿", subtitle: "投稿记录")
                        ForEach(Array(batches.enumerated()), id: \.element.id) { index, batch in
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
                            .onAppear {
                                if batch.id == batches.last?.id {
                                    Task { await loadMore() }
                                }
                            }

                            if canCancel(batch) {
                                Button(role: .destructive) {
                                    cancellationCandidate = batch
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

                SetuLoadMoreFooter(state: loadMoreFooterState) {
                    Task { await loadMore() }
                }
                .setuListRow()
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("图库投稿")
        .navigationBarBackButtonHidden(hasMeaningfulDraft)
        .toolbar {
            if hasMeaningfulDraft {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingExitConfirmation = true
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                    .disabled(isUploading || isLoadingPickedItems)
                }
            }
        }
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
            await loadFirstPage()
        }
        .refreshable { await loadFirstPage() }
        .confirmationDialog("退出投稿编辑？", isPresented: $showingExitConfirmation, titleVisibility: .visible) {
            Button("保存草稿并退出") {
                saveDraft()
                dismiss()
            }
            Button("放弃草稿并退出", role: .destructive) {
                clearDraft()
                dismiss()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("你还有未提交的图片或信息。可以保留草稿，下次回来继续编辑。")
        }
        .alert(
            "取消这次投稿？",
            isPresented: Binding(
                get: { cancellationCandidate != nil },
                set: { if !$0 { cancellationCandidate = nil } }
            ),
            presenting: cancellationCandidate
        ) { batch in
            Button("确认取消", role: .destructive) {
                Task { await cancel(batch) }
            }
            Button("继续保留", role: .cancel) {}
        } message: { _ in
            Text("取消后，这次投稿将不再进入审核，已上传的进度也不会继续。")
        }
    }

    @ViewBuilder
    private var adaptiveStatusPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            statusPicker.pickerStyle(.menu)
        } else {
            statusPicker.pickerStyle(.segmented)
        }
    }

    private var statusPicker: some View {
        Picker("状态", selection: $statusFilter) {
            Text("全部").tag("ALL")
            Text("上传中").tag("UPLOADING")
            Text("待审核").tag("WAITING_MANUAL_REVIEW")
            Text("已发布").tag("PUBLISHED")
            Text("已拒绝").tag("REJECTED")
        }
    }

    private var createSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "新建投稿", subtitle: "分三步完成，最多 20 张图片")
                GalleryUploadStepProgress(step: uploadStep)

                if let uploadFeedback {
                    SetuFeedbackBanner(feedback: uploadFeedback)
                }

                Divider()
                    .overlay(SetuColor.separator)

                switch uploadStep {
                case .images:
                    imageSelectionStep
                case .details:
                    informationStep
                case .confirmation:
                    confirmationStep
                }
            }
        }
        .setuListRow()
    }

    private var imageSelectionStep: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: "选择图片", subtitle: "已选择 \(uploadItems.count) / 20 张")
            Text("长按缩略图并拖到目标位置可调整顺序；也可以逐张移除。")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)

            if remainingSelectionCount > 0 {
                PhotosPicker(
                    selection: $pickedItems,
                    maxSelectionCount: remainingSelectionCount,
                    matching: .images
                ) {
                    Label(uploadItems.isEmpty ? "选择图片" : "继续添加图片", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(SetuColor.brandPink)
                .disabled(isLoadingPickedItems)

                if isLoadingPickedItems {
                    ProgressView("正在读取图片")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                SetuPill(text: "已达到 20 张上限", systemImage: "checkmark.circle", tone: .muted)
            }

            if uploadItems.isEmpty {
                SetuEmptyState(
                    title: "还没有选择图片",
                    message: "选择后会在这里预览，也可以拖动调整提交顺序。",
                    systemImage: "photo.badge.plus"
                )
            } else {
                LazyVGrid(columns: uploadGridColumns, spacing: SetuSpacing.sm) {
                    ForEach(Array(uploadItems.enumerated()), id: \.element.id) { index, item in
                        GalleryUploadThumbnailTile(
                            item: item,
                            order: index + 1,
                            showsRemoveButton: true,
                            onRemove: { removeUploadItem(id: item.id) }
                        )
                        .draggable(item.id)
                        .dropDestination(for: String.self) { identifiers, _ in
                            guard let draggedID = identifiers.first else { return false }
                            return moveUploadItem(id: draggedID, before: item.id)
                        }
                        .accessibilityAction(named: Text("向前移动")) {
                            moveUploadItem(id: item.id, offset: -1)
                        }
                        .accessibilityAction(named: Text("向后移动")) {
                            moveUploadItem(id: item.id, offset: 1)
                        }
                    }
                }
                .allowsHitTesting(!isLoadingPickedItems)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SetuSpacing.md) {
                        clearDraftButton
                        nextStepButton
                    }

                    VStack(spacing: SetuSpacing.sm) {
                        nextStepButton
                        clearDraftButton
                    }
                }
                .disabled(isLoadingPickedItems)
            }
        }
    }

    private var clearDraftButton: some View {
        Button(role: .destructive) {
            clearDraft()
        } label: {
            Label("清空草稿", systemImage: "trash")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var nextStepButton: some View {
        Button {
            uploadFeedback = nil
            uploadStep = .details
        } label: {
            Label("下一步", systemImage: "arrow.right")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(SetuColor.brandPink)
    }

    private var informationStep: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: "填写信息", subtitle: "这些信息会应用于本次选择的图片")

            GalleryUploadLabeledTextField(title: "作品标题", prompt: "填写作品标题", text: $title)
            GalleryUploadLabeledTextField(title: "作者", prompt: "填写作者名称", text: $author)
            GalleryUploadLabeledTextField(title: "标签", prompt: "用逗号或空格分隔", text: $tagsText)

            Picker("作品关系", selection: $pidMode) {
                Text("每张都是独立作品").tag("MULTI_PID_P0")
                Text("多张属于同一作品").tag("SINGLE_PID_MULTI_PAGE")
            }
            .pickerStyle(.menu)

            Toggle("包含 18+ 内容", isOn: $r18)
            Text("请如实标记，审核时会按内容分级规则处理。")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)

            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                Text("图片来源")
                    .font(SetuTypography.body)
                    .foregroundStyle(SetuColor.textPrimary)
                Picker("图片来源", selection: $aiType) {
                    Text("非 AI").tag(1)
                    Text("AI 生成").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: SetuSpacing.md) {
                Button {
                    uploadFeedback = nil
                    uploadStep = .images
                } label: {
                    Label("上一步", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    advanceToConfirmation()
                } label: {
                    Label("确认信息", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
            }
        }
    }

    private var confirmationStep: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: "确认提交", subtitle: "最后检查图片顺序与作品信息")

            LazyVGrid(columns: uploadGridColumns, spacing: SetuSpacing.sm) {
                ForEach(Array(uploadItems.enumerated()), id: \.element.id) { index, item in
                    GalleryUploadThumbnailTile(
                        item: item,
                        order: index + 1,
                        showsRemoveButton: false,
                        onRemove: nil
                    )
                }
            }

            VStack(spacing: SetuSpacing.sm) {
                LabeledContent("图片数量", value: "\(uploadItems.count) 张")
                LabeledContent("作品关系", value: relationshipTitle)
                LabeledContent("内容级别", value: r18 ? "包含 18+ 内容" : "普通内容")
                LabeledContent("图片来源", value: imageSourceTitle)
                LabeledContent("标题", value: title.trimmingCharacters(in: .whitespacesAndNewlines))
                LabeledContent("作者", value: author.trimmingCharacters(in: .whitespacesAndNewlines))
                LabeledContent("标签", value: parsedTagsTitle)
            }
            .font(SetuTypography.caption)

            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                Label("审核说明", systemImage: "checkmark.seal")
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                Text("提交后会进入人工审核。审核人员会检查图片内容、顺序与作品信息；结果会在投稿记录和通知中更新，审核通过后再发布到图库。")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            .padding(SetuSpacing.md)
            .background(SetuColor.brandSoft.opacity(0.16), in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))

            HStack(spacing: SetuSpacing.md) {
                Button {
                    uploadFeedback = nil
                    uploadStep = .details
                } label: {
                    Label("上一步", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isUploading)

                Button {
                    Task { await submitUpload() }
                } label: {
                    Label(
                        isUploading ? "正在提交" : "提交审核",
                        systemImage: isUploading ? "hourglass" : "icloud.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
                .disabled(isUploading || uploadItems.isEmpty)
            }
        }
    }

    private var uploadGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96, maximum: 136), spacing: SetuSpacing.sm)]
    }

    private var remainingSelectionCount: Int {
        max(0, 20 - uploadItems.count)
    }

    private var relationshipTitle: String {
        pidMode == "SINGLE_PID_MULTI_PAGE" ? "多张属于同一作品" : "每张都是独立作品"
    }

    private var imageSourceTitle: String {
        aiType == 2 ? "AI 生成" : "非 AI"
    }

    private var parsedTagsTitle: String {
        let tags = parseTags(tagsText)
        return tags.isEmpty ? "无" : tags.joined(separator: "、")
    }

    private var hasMeaningfulDraft: Bool {
        !uploadItems.isEmpty
            || !pickedItems.isEmpty
            || isLoadingPickedItems
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !tagsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pidMode != "MULTI_PID_P0"
            || r18
            || aiType != 1
    }

    private var hasMore: Bool {
        batches.count < total
    }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !hasMore { return .complete("已加载全部 \(total) 条投稿") }
        return .idle
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        let filter = statusFilter
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.galleryUploadClient.listMine(status: filter == "ALL" ? nil : filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func loadMore() async {
        let filter = statusFilter
        await pager.loadMore { page in
            let result = try await environment.galleryUploadClient.listMine(status: filter == "ALL" ? nil : filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func canCancel(_ batch: GalleryUploadBatchSummary) -> Bool {
        batch.status == "UPLOADING" || batch.status == "WAITING_MANUAL_REVIEW"
    }

    private func cancel(_ batch: GalleryUploadBatchSummary) async {
        do {
            try await environment.galleryUploadClient.cancel(batchID: batch.batchId)
            await loadFirstPage()
            actionFeedback = .success("已取消投稿")
        } catch {
            actionFeedback = .error(UserFacingErrorMapper.map(error))
        }
        cancellationCandidate = nil
    }

    private func loadPickedItems() async {
        let selectedItems = pickedItems
        guard !selectedItems.isEmpty else { return }
        pickedItems = []
        isLoadingPickedItems = true
        defer { isLoadingPickedItems = false }

        let availableCount = max(0, 20 - uploadItems.count)
        guard availableCount > 0 else { return }
        var nextItems: [LocalGalleryUploadItem] = []
        var failedCount = 0
        let startIndex = uploadItems.count
        for (index, pickedItem) in selectedItems.prefix(availableCount).enumerated() {
            guard let data = try? await pickedItem.loadTransferable(type: Data.self) else {
                failedCount += 1
                continue
            }
            let type = pickedItem.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let preferredExtension = type.preferredFilenameExtension ?? "jpg"
            let clientItemID = UUID().uuidString
            let filename = "ios-upload-\(clientItemID.prefix(8)).\(preferredExtension)"
            let storedFileName = "\(clientItemID)-\(filename)"
            try? GalleryUploadDraftStore.write(data: data, fileName: storedFileName)
            nextItems.append(LocalGalleryUploadItem(
                clientItemID: clientItemID,
                filename: filename,
                contentType: type.preferredMIMEType ?? "image/jpeg",
                data: data,
                thumbnail: GalleryUploadThumbnailFactory.make(from: data),
                storedFileName: storedFileName,
                pageIndex: startIndex + index,
                status: "等待上传",
                progress: 0
            ))
        }
        uploadItems.append(contentsOf: nextItems)
        normalizeUploadOrder()
        if failedCount > 0 {
            uploadFeedback = .error("有 \(failedCount) 张图片无法读取，请重新选择")
        } else {
            uploadFeedback = nil
        }
        saveDraft()
    }

    private func removeUploadItem(id: String) {
        guard let index = uploadItems.firstIndex(where: { $0.id == id }) else { return }
        let item = uploadItems.remove(at: index)
        GalleryUploadDraftStore.removeFile(fileName: item.storedFileName)
        normalizeUploadOrder()
        saveDraft()
    }

    @discardableResult
    private func moveUploadItem(id: String, before targetID: String) -> Bool {
        guard id != targetID,
              let sourceIndex = uploadItems.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let item = uploadItems.remove(at: sourceIndex)
        guard let targetIndex = uploadItems.firstIndex(where: { $0.id == targetID }) else {
            uploadItems.insert(item, at: min(sourceIndex, uploadItems.endIndex))
            return false
        }
        uploadItems.insert(item, at: targetIndex)
        normalizeUploadOrder()
        saveDraft()
        return true
    }

    private func moveUploadItem(id: String, offset: Int) {
        guard let sourceIndex = uploadItems.firstIndex(where: { $0.id == id }) else { return }
        let destinationIndex = min(max(sourceIndex + offset, uploadItems.startIndex), uploadItems.index(before: uploadItems.endIndex))
        guard sourceIndex != destinationIndex else { return }
        let item = uploadItems.remove(at: sourceIndex)
        uploadItems.insert(item, at: destinationIndex)
        normalizeUploadOrder()
        saveDraft()
    }

    private func normalizeUploadOrder() {
        for index in uploadItems.indices {
            uploadItems[index].pageIndex = index
        }
    }

    private func advanceToConfirmation() {
        guard !uploadItems.isEmpty else {
            uploadFeedback = .warning("请先选择图片")
            uploadStep = .images
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedAuthor.isEmpty else {
            uploadFeedback = .warning("请填写作品标题和作者")
            return
        }
        uploadFeedback = nil
        uploadStep = .confirmation
    }

    private func submitUpload() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedAuthor.isEmpty else {
            uploadFeedback = .warning("请填写作品标题和作者")
            return
        }
        guard !uploadItems.isEmpty else {
            uploadFeedback = .warning("请选择图片")
            return
        }

        isUploading = true
        uploadFeedback = nil
        saveDraft()
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
                clientRequestId: clientRequestID,
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

            _ = try await environment.galleryUploadClient.completeBatch(batchID: initResponse.batchId, items: completedItems)
            clearDraft()
            uploadFeedback = .success("已提交审核。预计先由审核人员检查图片内容、顺序与作品信息，通过后再发布到图库；结果会在投稿记录和通知中更新。")
            await loadFirstPage()
        } catch {
            uploadFeedback = .error(UserFacingErrorMapper.map(error))
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

        clientRequestID = draft.clientRequestID ?? UUID().uuidString
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
                thumbnail: GalleryUploadThumbnailFactory.make(from: data),
                storedFileName: item.storedFileName,
                pageIndex: item.pageIndex,
                status: item.status,
                progress: item.progress
            )
        }
        uploadItems = restoredItems
        normalizeUploadOrder()

        if !draft.isMeaningful {
            GalleryUploadDraftStore.clear()
        } else if restoredItems.count == draft.items.count, !restoredItems.isEmpty {
            uploadFeedback = .info("已自动恢复上次未完成的投稿图片和填写内容")
        } else if !draft.items.isEmpty {
            uploadFeedback = .warning("已恢复上次填写的投稿草稿，部分图片需要重新选择")
        } else {
            uploadFeedback = .info("已恢复上次填写的投稿草稿")
        }
    }

    private func saveDraft() {
        guard draftRestored else { return }
        let draft = GalleryUploadDraftPayload(
            clientRequestID: clientRequestID,
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
        uploadFeedback = nil
        uploadStep = .images
        clientRequestID = UUID().uuidString
        GalleryUploadDraftStore.clear()
    }
}

private struct LocalGalleryUploadItem: Identifiable {
    let clientItemID: String
    let filename: String
    let contentType: String
    let data: Data
    let thumbnail: GalleryUploadPlatformImage?
    let storedFileName: String
    var pageIndex: Int
    var status: String
    var progress: Int

    var id: String { clientItemID }
}

private enum GalleryUploadStep: Int, CaseIterable {
    case images
    case details
    case confirmation

    var title: String {
        switch self {
        case .images: "选择图片"
        case .details: "填写信息"
        case .confirmation: "确认提交"
        }
    }
}

private struct GalleryUploadStepProgress: View {
    let step: GalleryUploadStep

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack {
                Text("第 \(step.rawValue + 1) / \(GalleryUploadStep.allCases.count) 步")
                Spacer()
                Text(step.title)
                    .fontWeight(.semibold)
            }
            .font(SetuTypography.caption)
            .foregroundStyle(SetuColor.textSecondary)

            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(GalleryUploadStep.allCases.count)
            )
            .tint(SetuColor.brandPink)
            .accessibilityLabel("投稿进度")
            .accessibilityValue("第 \(step.rawValue + 1) 步，共 \(GalleryUploadStep.allCases.count) 步，\(step.title)")
        }
    }
}

private struct GalleryUploadLabeledTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(title)
                .font(SetuTypography.caption.weight(.semibold))
                .foregroundStyle(SetuColor.textSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct GalleryUploadThumbnailTile: View {
    let item: LocalGalleryUploadItem
    let order: Int
    let showsRemoveButton: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                        .fill(SetuColor.brandSoft.opacity(0.18))

                    GalleryUploadDataImage(image: item.thumbnail)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    Text("\(order)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                        .padding(SetuSpacing.xs)

                    if showsRemoveButton, let onRemove {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Button(role: .destructive, action: onRemove) {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(SetuColor.danger)
                                        .frame(width: 32, height: 32)
                                        .background(.regularMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .accessibilityLabel("移除第 \(order) 张图片")
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                .accessibilityLabel("第 \(order) 张图片")
            }
            .aspectRatio(1, contentMode: .fit)

            Text(item.status)
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(1)

            if item.progress > 0 {
                ProgressView(value: Double(item.progress), total: 100)
                    .tint(SetuColor.brandPink)
                    .accessibilityLabel("第 \(order) 张图片上传进度")
                    .accessibilityValue("\(item.progress)%")
            }
        }
    }
}

private struct GalleryUploadDataImage: View {
    let image: GalleryUploadPlatformImage?

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            placeholder
        }
        #elseif os(macOS)
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(SetuColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

private enum GalleryUploadThumbnailFactory {
    static func make(from data: Data) -> GalleryUploadPlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        #if os(iOS)
        return UIImage(cgImage: image)
        #elseif os(macOS)
        return NSImage(cgImage: image, size: .zero)
        #endif
    }
}

private struct GalleryUploadDraftPayload: Codable {
    let version: Int
    let updatedAt: Date
    let clientRequestID: String?
    let form: GalleryUploadDraftFormPayload
    let items: [GalleryUploadDraftItemPayload]

    init(clientRequestID: String, form: GalleryUploadDraftFormPayload, items: [GalleryUploadDraftItemPayload]) {
        self.version = 2
        self.updatedAt = Date()
        self.clientRequestID = clientRequestID
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

    static func removeFile(fileName: String) {
        guard let fileURL = try? directory(create: false).appendingPathComponent(fileName, isDirectory: false) else { return }
        try? FileManager.default.removeItem(at: fileURL)
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
                    Text(displayTitle)
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

            Text(SetuDateFormatter.string(from: batch.createdAt))
                .font(.caption)
                .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    private var displayTitle: String {
        let title = batch.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "未命名投稿" : title
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
