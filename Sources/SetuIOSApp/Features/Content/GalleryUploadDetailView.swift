import SetuIOSCore
import SwiftUI

struct GalleryUploadDetailView: View {
    @Bindable var environment: AppEnvironment
    let batchID: Int
    @State private var state: LoadState<GalleryUploadBatchDetail> = .idle
    @State private var message: String?

    var body: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("批次详情加载失败", systemImage: "tray.full", description: Text(message))
            case .loaded(let batch):
                Section("批次") {
                    LabeledContent("状态", value: batch.statusTitle)
                    LabeledContent("PID 模式", value: batch.pidMode)
                    if let title = batch.title, !title.isEmpty {
                        LabeledContent("标题", value: title)
                    }
                    if let author = batch.author, !author.isEmpty {
                        LabeledContent("作者", value: author)
                    }
                    if let aiType = batch.aiType {
                        LabeledContent("AI 类型", value: "\(aiType)")
                    }
                    if let tags = batch.tags, !tags.isEmpty {
                        Text(tags.joined(separator: " / "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("创建时间", value: batch.createdAt)
                    if let reviewedAt = batch.reviewedAt {
                        LabeledContent("审核时间", value: reviewedAt)
                    }
                    if let publishedAt = batch.publishedAt {
                        LabeledContent("发布时间", value: publishedAt)
                    }
                }

                Section("图片 \(batch.items.count)") {
                    ForEach(batch.items) { item in
                        GalleryUploadItemRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("投稿 #\(batchID)")
        .toolbar {
            if case .loaded(let batch) = state, canCancel(batch) {
                Button("取消批次", role: .destructive) {
                    Task { await cancel() }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            state = .loaded(try await environment.galleryUploadClient.detail(batchID: batchID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func cancel() async {
        do {
            try await environment.galleryUploadClient.cancel(batchID: batchID)
            message = "批次已取消"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func canCancel(_ batch: GalleryUploadBatchDetail) -> Bool {
        batch.status == "UPLOADING" || batch.status == "WAITING_MANUAL_REVIEW"
    }
}

struct GalleryUploadItemRow: View {
    let item: GalleryUploadItem

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: item.previewUrl)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title ?? item.filename ?? "投稿图片 #\(item.submissionId)")
                    .font(.headline)
                    .lineLimit(2)
                Text(item.author ?? "未知作者")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(item.statusTitle, systemImage: "flag")
                    if let uploadStatus = item.uploadStatus {
                        Label(uploadStatus, systemImage: "icloud")
                    }
                    if let publicPid = item.publicPid {
                        Label("\(publicPid)-\(item.publicP ?? 0)", systemImage: "number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let rejectReason = item.rejectReason, !rejectReason.isEmpty {
                    Text(rejectReason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
