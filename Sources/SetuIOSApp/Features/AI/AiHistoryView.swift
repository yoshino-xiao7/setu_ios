import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct AiHistoryView: View {
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<AiGenerationJob>(pageSize: 12)
    private var jobs: [AiGenerationJob] {
        get { pager.items }
        nonmutating set { pager.replaceItems(newValue) }
    }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    @State private var statusFilter = ""
    @State private var feedback: SetuFeedback?
    @State private var showingDeleteRequests = false
    @State private var previewSelection: AiHistoryPreviewSelection?
    private let pageSize = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
            }

            adaptiveStatusPicker
            .onChange(of: statusFilter) {
                Task { await loadFirstPage(clearExisting: true) }
            }

            if isInitialLoading {
                SetuCard {
                    SetuEmptyState(title: "正在加载 AI 绘画历史", systemImage: "sparkles", isLoading: true)
                }
            } else if jobs.isEmpty {
                if let loadError {
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "历史加载失败", message: loadError, systemImage: "wifi.exclamationmark")
                            Button("重试") { Task { await loadFirstPage() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "暂无 AI 绘画记录", message: "描述一个画面，开始你的第一幅作品。", systemImage: "sparkles")
                            Button("开始创作") { router.navigate(to: .aiDraw) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "我的作品")
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(jobs) { job in
                            AiGenerationGridTile(job: job, footerTitle: SetuDateFormatter.string(from: job.createdAt)) {
                                router.navigate(to: .aiGenerationDetail(job.id))
                            }
                            .contextMenu {
                                Button {
                                    reuse(job)
                                } label: {
                                    Label("复用参数", systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button {
                                    copyPrompt(job)
                                } label: {
                                    Label("复制提示词", systemImage: "doc.on.doc")
                                }
                                if job.status == "COMPLETED" {
                                    Button {
                                        previewSelection = AiHistoryPreviewSelection(job: job)
                                    } label: {
                                        Label("查看图片", systemImage: "eye")
                                    }
                                }
                            }
                            .onAppear {
                                if job.id == jobs.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    loadMoreFooter
                }
            }
        }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .navigationTitle("AI 绘画历史")
        .toolbar {
            Button {
                showingDeleteRequests = true
            } label: {
                Label("删除申请", systemImage: "xmark.bin")
            }
        }
        .sheet(isPresented: $showingDeleteRequests) {
            NavigationStack {
                AiDeleteRequestsView(environment: environment, showsCloseButton: true)
            }
        }
        .sheet(item: $previewSelection) { selection in
            AiGenerationImagePreviewSheet(
                environment: environment,
                job: selection.job,
                onOpenDetail: {
                    previewSelection = nil
                    router.navigate(to: .aiGenerationDetail(selection.job.id))
                },
                onFeedback: { feedback = $0 }
            )
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
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
            Text("全部").tag("")
            Text("排队中").tag("QUEUED")
            Text("生成中").tag("RUNNING")
            Text("已完成").tag("COMPLETED")
            Text("失败").tag("FAILED")
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        SetuLoadMoreFooter(state: loadMoreFooterState) {
            Task { await loadMore() }
        }
    }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !hasMore { return .complete("已加载全部 \(total) 条记录") }
        return .idle
    }

    private var hasMore: Bool { pager.hasMore }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 148), spacing: SetuSpacing.md)]
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        let filter = statusFilter
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.aiGenerationClient.listMine(status: filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func loadMore() async {
        let filter = statusFilter
        await pager.loadMore { page in
            let result = try await environment.aiGenerationClient.listMine(status: filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func reuse(_ job: AiGenerationJob) {
        AiDrawDraftStore.applyHistoryJob(job)
        navigation.navigate(to: .ai, reset: true)
    }

    private func copyPrompt(_ job: AiGenerationJob) {
        let text = [
            "正向提示词：\(job.promptPositive ?? job.promptCn)",
            "反向提示词：\(job.promptNegative ?? "")"
        ].joined(separator: "\n")
        PlatformClipboard.copy(text)
        feedback = .success("提示词已复制")
    }

}

private struct AiHistoryPreviewSelection: Identifiable {
    let job: AiGenerationJob

    var id: Int { job.id }
}

private struct AiGenerationRow: View {
    let job: AiGenerationJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if job.status == "COMPLETED" {
                    SetuRemoteImage(
                        urlString: job.imageUrl,
                        accessibilityLabel: "AI 作品：\(job.promptCn)",
                        allowsTapToRetry: false
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.promptCn)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(2)
                    Text("\(job.width) × \(job.height) · \(job.steps) 步")
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                Spacer()
                StatusBadge(title: job.statusTitle, status: job.status)
            }

            if let detail = job.userErrorMessage, !detail.isEmpty {
                Text(detail)
                    .font(SetuTypography.caption)
                    .foregroundStyle(job.status == "FAILED" ? SetuColor.danger : SetuColor.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let cost = job.pointsCost {
                    Label("\(cost) 积分", systemImage: "bolt.circle")
                }
                if let size = job.sizeBytes {
                    Label(formatFileSize(size), systemImage: "doc")
                }
                if job.publicVisible == true {
                    Label("公开", systemImage: "globe")
                }
                if let createdAt = job.createdAt {
                    Label(SetuDateFormatter.string(from: createdAt), systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(SetuColor.textTertiary)

            if job.status == "COMPLETED" {
                HStack(spacing: 8) {
                    StatusBadge(title: "公开：\(reviewStatusTitle)", status: job.reviewStatus)
                    if let publicCategory = job.publicCategory {
                        StatusBadge(title: publicCategory == "R18" ? "成人内容" : "全年龄", status: publicCategory)
                    }
                    if let deleteStatus = job.deleteStatus, deleteStatus != "NONE" {
                        StatusBadge(title: deleteStatusTitle(deleteStatus), status: deleteStatus)
                    }
                }
            }

            if job.privateOssStatus == "EXPIRED" || job.privateOssStatus == "EXPLICITLY_DELETED" {
                Label("图片文件已清理，生成历史仍会保留", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            } else if job.status == "COMPLETED", let expiresAt = job.privateOssExpiresAt {
                Label("图片仅保留 30 天，预计 \(SetuDateFormatter.string(from: expiresAt)) 清理", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var reviewStatusTitle: String {
        switch job.reviewStatus {
        case "WAITING": "待审核"
        case "APPROVED": "已进广场"
        case "REJECTED": "已拒绝"
        case "NONE": "未提交"
        default: "状态更新中"
        }
    }

    private func deleteStatusTitle(_ status: String) -> String {
        switch status {
        case "WAITING": "删除待审核"
        case "APPROVED": "删除已通过"
        case "REJECTED": "删除已拒绝"
        default: "状态更新中"
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

struct AiGenerationImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let job: AiGenerationJob
    let onOpenDetail: () -> Void
    let onFeedback: (SetuFeedback) -> Void

    @State private var imageState: LoadState<String> = .idle
    @State private var localFeedback: SetuFeedback?
    @State private var fileSharePayload: SystemFileSharePayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    imageStage

                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text(job.promptCn)
                                .font(SetuTypography.headline)
                                .foregroundStyle(SetuColor.textPrimary)
                            .textSelection(.enabled)
                        Text("\(job.width) × \(job.height) · \(job.statusTitle)")
                                .font(.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        if let localFeedback {
                            SetuFeedbackBanner(feedback: localFeedback)
                        }
                    }
                    }

                    actions
                }
                .padding(SetuSpacing.lg)
            }
            .background(SetuColor.pageGradient.ignoresSafeArea())
            .navigationTitle("图片预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .task(id: job.id) {
                await prepareImageURL()
            }
            .sheet(item: $fileSharePayload) { payload in
                SystemFileShareSheet(fileURL: payload.fileURL) { result in
                    switch result {
                    case .completed:
                        localFeedback = .success("已完成保存或分享")
                    case .cancelled:
                        localFeedback = .info("已取消保存或分享")
                    case .failed(let text):
                        localFeedback = .error("保存或分享失败：\(text)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        switch imageState {
        case .idle, .loading:
            SetuCard {
                SetuEmptyState(title: "正在加载图片", systemImage: "photo", isLoading: true)
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        case .failed(let message):
            SetuCard {
                SetuEmptyState(title: "图片加载失败", message: message, systemImage: "photo")
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        case .loaded(let urlString):
            if URL(string: urlString) != nil {
                SetuCard {
                    SetuRemoteImage(
                        urlString: urlString,
                        accessibilityLabel: "AI 作品图片：\(job.promptCn)",
                        width: nil,
                        height: 320,
                        cornerRadius: SetuRadius.md,
                        contentMode: .fit
                    )
                }
            } else {
                SetuCard {
                    SetuEmptyState(title: "图片暂时不可用", systemImage: "photo.badge.exclamationmark")
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
        }
    }

    private var actions: some View {
        SetuCard {
            VStack(spacing: SetuSpacing.sm) {
            Button {
                Task { await refreshImageURL() }
            } label: {
                Label("刷新图片", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button {
                Task { await download() }
            } label: {
                Label("下载图片", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button {
                copyPrompt()
            } label: {
                Label("复制提示词", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button {
                onOpenDetail()
            } label: {
                Label("查看作品详情", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
            }
        }
    }

    private func prepareImageURL() async {
        if let imageUrl = job.imageUrl, URL(string: imageUrl) != nil {
            imageState = .loaded(imageUrl)
            return
        }
        await refreshImageURL()
    }

    private func refreshImageURL() async {
        imageState = .loading
        do {
            let result = try await environment.aiGenerationClient.imageURL(id: job.id)
            imageState = .loaded(result.url)
            localFeedback = .info("图片链接将在 \(result.expiresInSeconds) 秒后失效")
        } catch {
            imageState = .failed(UserFacingErrorMapper.map(error))
            localFeedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func download() async {
        do {
            let result = try await environment.aiGenerationClient.download(id: job.id)
            guard let url = URL(string: result.downloadUrl) else {
                localFeedback = .error("下载地址无效，请稍后重试。")
                return
            }
            let fileURL = try await RemoteFileExportService.download(from: url, filename: exportFilename)
            fileSharePayload = SystemFileSharePayload(fileURL: fileURL)
            localFeedback = .info("下载完成，请选择保存位置或分享方式")
            onFeedback(.success("图片已准备好"))
        } catch {
            localFeedback = .error(RemoteFileExportService.userMessage(for: error))
        }
    }

    private var exportFilename: String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = job.promptCn
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = sanitized.isEmpty ? "AI作品" : String(sanitized.prefix(24))
        return "雪涼云-\(title).png"
    }

    private func copyPrompt() {
        let text = [
            "正向提示词：\(job.promptPositive ?? job.promptCn)",
            "反向提示词：\(job.promptNegative ?? "")"
        ].joined(separator: "\n")
        PlatformClipboard.copy(text)
        localFeedback = .success("提示词已复制")
        onFeedback(.success("提示词已复制"))
    }
}

struct StatusBadge: View {
    let title: String
    let status: String

    var body: some View {
        SetuPill(text: title, tone: tone)
    }

    private var tone: SetuPillTone {
        switch status {
        case "COMPLETED", "APPROVED", "GENERAL": .success
        case "FAILED", "REJECTED", "R18": .danger
        case "RUNNING", "UPLOADING": .info
        case "WAITING": .warning
        default: .warning
        }
    }
}
