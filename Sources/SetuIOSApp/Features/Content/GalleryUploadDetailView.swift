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
                SetuCard {
                    Label(message, systemImage: "checkmark.circle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .setuListRow()
            }

            switch state {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载批次详情", message: "正在同步图片状态。", systemImage: "tray.full", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(title: "批次详情加载失败", message: message, systemImage: "tray.full")
            case .loaded(let batch):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "批次", subtitle: "#\(batch.batchId)")
                        GalleryUploadMetadataRow(title: "状态") {
                            GalleryUploadStatusPill(status: batch.status, title: batch.statusTitle)
                        }
                        GalleryUploadMetadataRow(title: "PID 模式", value: batch.pidMode)
                        if let title = batch.title, !title.isEmpty {
                            GalleryUploadMetadataRow(title: "标题", value: title)
                        }
                        if let author = batch.author, !author.isEmpty {
                            GalleryUploadMetadataRow(title: "作者", value: author)
                        }
                        if let aiType = batch.aiType {
                            GalleryUploadMetadataRow(title: "AI 类型", value: "\(aiType)")
                        }
                        if let tags = batch.tags, !tags.isEmpty {
                            GalleryUploadMetadataRow(title: "标签", value: tags.joined(separator: " / "))
                        }
                        GalleryUploadMetadataRow(title: "创建时间", value: batch.createdAt)
                        if let reviewedAt = batch.reviewedAt {
                            GalleryUploadMetadataRow(title: "审核时间", value: reviewedAt)
                        }
                        if let publishedAt = batch.publishedAt {
                            GalleryUploadMetadataRow(title: "发布时间", value: publishedAt)
                        }
                    }
                }
                .setuListRow()

                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "图片 \(batch.items.count)", subtitle: "投稿明细")
                        ForEach(Array(batch.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                            GalleryUploadItemRow(item: item)
                        }
                    }
                }
                .setuListRow()
            }
        }
        .listStyle(.plain)
        .setuBackground()
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
        HStack(spacing: SetuSpacing.md) {
            ImageThumbnailView(urlString: item.previewUrl)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(item.title ?? item.filename ?? "投稿图片 #\(item.submissionId)")
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.author ?? "未知作者")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
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
                .foregroundStyle(SetuColor.textTertiary)
                if let rejectReason = item.rejectReason, !rejectReason.isEmpty {
                    Text(rejectReason)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.danger)
                }
            }
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct GalleryUploadMetadataRow: View {
    let title: String
    private let value: AnyView

    init<Value: View>(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = AnyView(value())
    }

    init(title: String, value: String) {
        self.title = title
        self.value = AnyView(
            Text(value)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
