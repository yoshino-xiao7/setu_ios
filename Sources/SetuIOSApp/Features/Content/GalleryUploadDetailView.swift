import SetuIOSCore
import SwiftUI

struct GalleryUploadDetailView: View {
    @Bindable var environment: AppEnvironment
    let batchID: Int
    @State private var state: LoadState<GalleryUploadBatchDetail> = .idle
    @State private var feedback: SetuFeedback?
    @State private var showingCancelConfirmation = false
    @State private var isCancelling = false

    var body: some View {
        List {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
                .setuListRow()
            }

            switch state {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载投稿详情", message: "正在同步图片状态。", systemImage: "tray.full", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(
                    title: "投稿详情加载失败",
                    message: message,
                    systemImage: "tray.full",
                    actionTitle: "重试",
                    action: { Task { await load() } }
                )
            case .loaded(let batch):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "投稿信息")
                        GalleryUploadMetadataRow(title: "状态") {
                            GalleryUploadStatusPill(status: batch.status, title: batch.statusTitle)
                        }
                        GalleryUploadMetadataRow(title: "作品关系", value: workRelationshipTitle(batch.pidMode))
                        if let title = batch.title, !title.isEmpty {
                            GalleryUploadMetadataRow(title: "标题", value: title)
                        }
                        if let author = batch.author, !author.isEmpty {
                            GalleryUploadMetadataRow(title: "作者", value: author)
                        }
                        if let aiType = batch.aiType {
                            GalleryUploadMetadataRow(title: "图片来源", value: aiSourceTitle(aiType))
                        }
                        if let tags = batch.tags, !tags.isEmpty {
                            GalleryUploadMetadataRow(title: "标签", value: tags.joined(separator: " / "))
                        }
                        GalleryUploadMetadataRow(title: "创建时间", value: SetuDateFormatter.string(from: batch.createdAt, style: .full))
                        if let reviewedAt = batch.reviewedAt {
                            GalleryUploadMetadataRow(title: "审核时间", value: SetuDateFormatter.string(from: reviewedAt, style: .full))
                        }
                        if let publishedAt = batch.publishedAt {
                            GalleryUploadMetadataRow(title: "发布时间", value: SetuDateFormatter.string(from: publishedAt, style: .full))
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
                            GalleryUploadItemRow(item: item, order: index + 1)
                        }
                    }
                }
                .setuListRow()
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("投稿详情")
        .toolbar {
            if case .loaded(let batch) = state, canCancel(batch) {
                Button("取消投稿", role: .destructive) {
                    showingCancelConfirmation = true
                }
                .disabled(isCancelling)
            }
        }
        .alert("取消这次投稿？", isPresented: $showingCancelConfirmation) {
            Button("确认取消", role: .destructive) {
                Task { await cancel() }
            }
            Button("继续保留", role: .cancel) {}
        } message: {
            Text("取消后，这次投稿将不再进入审核，已经上传的进度也不会继续。")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        feedback = nil
        do {
            state = .loaded(try await environment.galleryUploadClient.detail(batchID: batchID))
        } catch {
            state = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func cancel() async {
        guard !isCancelling else { return }
        isCancelling = true
        defer { isCancelling = false }

        do {
            try await environment.galleryUploadClient.cancel(batchID: batchID)
            await load()
            feedback = .success("投稿已取消")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func canCancel(_ batch: GalleryUploadBatchDetail) -> Bool {
        batch.status == "UPLOADING" || batch.status == "WAITING_MANUAL_REVIEW"
    }

    private func workRelationshipTitle(_ value: String) -> String {
        switch value {
        case "SINGLE_PID_MULTI_PAGE": "多张属于同一作品"
        case "MULTI_PID_P0": "每张都是独立作品"
        default: "未知作品关系"
        }
    }

    private func aiSourceTitle(_ value: Int) -> String {
        switch value {
        case 1: "非 AI"
        case 2: "AI 生成"
        default: "未知"
        }
    }
}

struct GalleryUploadItemRow: View {
    let item: GalleryUploadItem
    let order: Int?

    init(item: GalleryUploadItem, order: Int? = nil) {
        self.item = item
        self.order = order
    }

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            SetuRemoteImage(
                urlString: item.previewUrl,
                accessibilityLabel: "投稿图片：\(displayTitle)"
            )
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(displayTitle)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.author ?? "未知作者")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 10) {
                    Label(item.statusTitle, systemImage: "flag")
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

    private var displayTitle: String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard title.isEmpty else { return title }
        return order.map { "第 \($0) 张图片" } ?? "投稿图片"
    }
}

private struct GalleryUploadMetadataRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        )
    }

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalRow
        } else {
            horizontalRow
        }
    }

    private var horizontalRow: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            titleLabel
                .layoutPriority(1)
            Spacer(minLength: SetuSpacing.sm)
            value
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            titleLabel
            value
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(SetuTypography.caption)
            .foregroundStyle(SetuColor.textSecondary)
    }
}
