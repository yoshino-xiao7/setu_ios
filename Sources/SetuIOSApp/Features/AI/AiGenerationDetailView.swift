import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct AiGenerationDetailView: View {
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Bindable var environment: AppEnvironment
    let jobID: Int
    @State private var state: LoadState<AiGenerationJob> = .idle
    @State private var publicCategory = "GENERAL"
    @State private var reviewNote = ""
    @State private var deleteReason = ""
    @State private var imageURL: AiImageURL?
    @State private var feedback: SetuFeedback?
    @State private var capabilities: AiCapabilityResponse?
    @State private var fullscreenImage: FullscreenImageItem?
    @State private var isPolling = false
    @State private var lastRefreshedAt: Date?
    @State private var fileSharePayload: SystemFileSharePayload?

    var body: some View {
        List {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
                .setuListRow()
            }

            switch state {
            case .idle, .loading:
                AiGenerationStateSection(title: "作品", stateTitle: "正在加载作品", systemImage: "sparkles.rectangle.stack", isLoading: true)
            case .failed(let message):
                AiGenerationStateSection(
                    title: "作品",
                    stateTitle: "作品加载失败",
                    message: message,
                    systemImage: "sparkles.rectangle.stack",
                    actionTitle: "重试",
                    action: { Task { await load() } }
                )
            case .loaded(let job):
                previewSection(job)
                imageActionsSection(job)
                infoSection(job)
                promptSection(job)
                reviewSection(job)
                deleteRequestSection(job)
            }
        }
        .listStyle(.plain)
        .setuBackground()
        #if os(iOS)
        .fullScreenCover(item: $fullscreenImage) { item in
            FullscreenImageViewer(url: item.url)
        }
        #else
        .sheet(item: $fullscreenImage) { item in
            FullscreenImageViewer(url: item.url)
        }
        #endif
        .sheet(item: $fileSharePayload) { payload in
            SystemFileShareSheet(fileURL: payload.fileURL) { result in
                switch result {
                case .completed:
                    feedback = .success("已完成保存或分享")
                case .cancelled:
                    feedback = .info("已取消保存或分享")
                case .failed(let text):
                    feedback = .error("保存或分享失败：\(text)")
                }
            }
        }
        .navigationTitle("作品详情")
        .setuFeedbackPresentation($feedback)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .loaded(let job) = state {
                SetuBottomCTA {
                    Button {
                        AiDrawDraftStore.applyHistoryJob(job)
                        navigation.navigate(to: .ai, reset: true)
                    } label: {
                        Text("再画一张（沿用这次参数）")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("ai.detail.create-again")
                }
            }
        }
        .task(id: jobID) {
            await load()
            await pollUntilTerminalStatus()
        }
        .refreshable { await load(showLoading: false) }
    }

    @ViewBuilder
    private func previewSection(_ job: AiGenerationJob) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "预览", subtitle: job.statusTitle)
                    let urlString = imageURL?.url ?? job.imageUrl
                    if let urlString, let url = URL(string: urlString) {
                        SetuRemoteImage(
                            urlString: urlString,
                            accessibilityLabel: "AI 作品：\(job.promptCn)",
                            width: nil,
                            height: nil,
                            cornerRadius: SetuRadius.md,
                            contentMode: .fit,
                            onActivate: { fullscreenImage = FullscreenImageItem(url: url) },
                            activationHint: "打开全屏图片预览"
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        SetuEmptyState(
                            title: "暂无图片",
                            message: job.status == "COMPLETED" ? "可以尝试刷新图片。" : "作品生成完成后会显示预览。",
                            systemImage: "photo"
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    }
            }
        }
        .setuListRow()
    }

    private func imageActionsSection(_ job: AiGenerationJob) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "图片操作")
                Button {
                    Task { await fetchImageURL() }
                } label: {
                    Label("刷新图片", systemImage: "arrow.clockwise")
                }
                .disabled(job.status != "COMPLETED")

                Button {
                    Task { await fetchDownload() }
                } label: {
                    Label("下载图片", systemImage: "arrow.down.circle")
                }
                .disabled(job.status != "COMPLETED")

            }
        }
        .setuListRow()
    }

    private func infoSection(_ job: AiGenerationJob) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "作品状态")
                LabeledContent("状态", value: job.statusTitle)
                if !job.isTrackingFinished {
                    Label("正在更新作品进度", systemImage: "arrow.triangle.2.circlepath")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                if let lastRefreshedAt {
                    LabeledContent("最近刷新", value: lastRefreshedAt.formatted(date: .omitted, time: .standard))
                }
                LabeledContent("画幅", value: "\(job.width) × \(job.height)")
                LabeledContent("图片保留", value: imageRetentionTitle(job.privateOssStatus))
                if let expiresAt = job.privateOssExpiresAt, !expiresAt.isEmpty {
                    LabeledContent("预计清理", value: SetuDateFormatter.string(from: expiresAt, style: .full))
                }
                if let cost = job.pointsCost {
                    LabeledContent("本次消耗", value: "\(cost) 积分")
                }
                if let createdAt = job.createdAt {
                    LabeledContent("创建时间", value: SetuDateFormatter.string(from: createdAt, style: .full))
                }
                if let completedAt = job.completedAt {
                    LabeledContent("完成时间", value: SetuDateFormatter.string(from: completedAt, style: .full))
                }
                if let error = job.userErrorMessage, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(SetuColor.danger)
                } else if job.status == "FAILED" {
                    Text("这次生成没有完成，请调整描述或稍后重试。")
                        .foregroundStyle(SetuColor.danger)
                }

                DisclosureGroup("高级参数") {
                    LabeledContent("细节质量", value: "\(job.steps) 步")
                    LabeledContent("描述遵循程度", value: job.cfg.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("随机种子", value: job.seed.map(String.init) ?? "随机")
                    LabeledContent("角色模式", value: job.generationMode == "DUAL" ? "双角色" : "单角色")
                    LabeledContent("基础模型", value: checkpointDisplayName(job.checkpoint))
                    if let lora = job.loraName, !lora.isEmpty {
                        LabeledContent("附加画风", value: lora)
                    }
                    if job.generationMode == "DUAL",
                        let secondLora = job.secondLoraName,
                        !secondLora.isEmpty
                    {
                        LabeledContent("第二附加画风", value: secondLora)
                    }
                }

            }
        }
        .setuListRow()
    }

    private func imageRetentionTitle(_ status: String?) -> String {
        switch status {
        case "ACTIVE":
            return "可下载"
        case "EXPIRED":
            return "已过期"
        case "EXPLICITLY_DELETED":
            return "已清理"
        case "NONE", nil:
            return "未生成"
        default:
            return "状态更新中"
        }
    }

    private func promptSection(_ job: AiGenerationJob) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "提示词")
                Button {
                    copyPrompt(job)
                } label: {
                    Label("复制提示词", systemImage: "doc.on.doc")
                }

                Text(job.promptCn)
                    .textSelection(.enabled)
                if let positive = job.promptPositive, !positive.isEmpty {
                    LabeledContent("正向") {
                        Text(positive)
                            .textSelection(.enabled)
                    }
                }
                if let negative = job.promptNegative, !negative.isEmpty {
                    LabeledContent("负向") {
                        Text(negative)
                            .textSelection(.enabled)
                    }
                }
                if let styleNotes = job.styleNotes, !styleNotes.isEmpty {
                    LabeledContent("说明") {
                        Text(styleNotes)
                            .textSelection(.enabled)
                    }
                }

            }
        }
        .setuListRow()
    }

    private func copyPrompt(_ job: AiGenerationJob) {
        let text = [
            "正向提示词：\(job.promptPositive ?? job.promptCn)",
            "反向提示词：\(job.promptNegative ?? "")",
        ].joined(separator: "\n")
        PlatformClipboard.copy(text)
        feedback = .success("提示词已复制")
    }

    private func reviewSection(_ job: AiGenerationJob) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "发布到广场")
                LabeledContent("发布状态", value: reviewStatusTitle(job.reviewStatus))
                Picker("分类", selection: $publicCategory) {
                    Text("全年龄").tag("GENERAL")
                    Text("成人内容").tag("R18")
                }
                TextField("提交备注", text: $reviewNote, axis: .vertical)
                Button("申请发布到广场") {
                    Task { await submitReview() }
                }
                .disabled(job.status != "COMPLETED")

            }
        }
        .setuListRow()
    }

    private func deleteRequestSection(_ job: AiGenerationJob) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "删除申请")
                LabeledContent("处理状态", value: deleteStatusTitle(job.deleteStatus))
                Text("删除申请通过后，这张图会从你的历史和公共广场中隐藏，并清理对应图片文件。")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                TextField("删除原因", text: $deleteReason, axis: .vertical)
                Button("提交删除申请", role: .destructive) {
                    Task { await submitDeleteRequest() }
                }
                .disabled(job.deleted == true || job.deleteStatus == "WAITING" || job.deleteStatus == "APPROVED")

            }
        }
        .setuListRow()
    }

    private func load(showLoading: Bool = true) async {
        if showLoading {
            state = .loading
            feedback = nil
        }
        do {
            async let job = environment.aiGenerationClient.get(id: jobID)
            async let capabilityResponse = try? environment.aiGenerationClient.capabilities()
            let loadedJob = try await job
            state = .loaded(loadedJob)
            capabilities = await capabilityResponse
            lastRefreshedAt = Date()
            await AiGenerationLiveActivityCenter.update(job: loadedJob, mobileClient: environment.mobileAppClient)
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func pollUntilTerminalStatus() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        while !Task.isCancelled {
            guard case .loaded(let job) = state, !job.isTrackingFinished else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            await load(showLoading: false)
        }
    }

    private func checkpointDisplayName(_ checkpoint: String?) -> String {
        if let checkpoint, !checkpoint.isEmpty {
            if let match = capabilities?.checkpoints.first(where: { $0.name == checkpoint }) {
                return match.displayName?.isEmpty == false ? match.displayName ?? "自定义画风" : "自定义画风"
            }
            return "自定义画风"
        }
        if let onlyCheckpoint = capabilities?.checkpoints.first, capabilities?.checkpoints.count == 1 {
            let title = onlyCheckpoint.displayName?.isEmpty == false ? onlyCheckpoint.displayName ?? "推荐画风" : "推荐画风"
            return "默认画风（\(title)）"
        }
        return "默认画风"
    }

    private func fetchImageURL() async {
        do {
            imageURL = try await environment.aiGenerationClient.imageURL(id: jobID)
            feedback = .success("图片已刷新")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func fetchDownload() async {
        do {
            let download = try await environment.aiGenerationClient.download(id: jobID)
            guard let url = URL(string: download.downloadUrl) else {
                feedback = .error("下载地址无效，请稍后重试。")
                return
            }
            let fileURL = try await RemoteFileExportService.download(from: url, filename: exportFilename)
            fileSharePayload = SystemFileSharePayload(fileURL: fileURL)
            feedback = .info("下载完成，请选择保存位置或分享方式")
        } catch {
            feedback = .error(RemoteFileExportService.userMessage(for: error))
        }
    }

    private var exportFilename: String {
        let prompt: String
        if case .loaded(let job) = state {
            prompt = job.promptCn
        } else {
            prompt = "AI作品"
        }
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = prompt
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = sanitized.isEmpty ? "AI作品" : String(sanitized.prefix(24))
        return "雪涼云-\(title).png"
    }

    private func submitReview() async {
        do {
            let note = reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await environment.aiGenerationClient.submitReview(
                id: jobID,
                category: publicCategory,
                note: note.isEmpty ? nil : note
            )
            await load()
            feedback = .success("发布申请已提交，等待审核。")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func submitDeleteRequest() async {
        let reason = deleteReason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await environment.aiGenerationClient.submitDeleteRequest(id: jobID, reason: reason.isEmpty ? nil : reason)
            await load()
            feedback = .success("删除申请已提交，等待处理。")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func reviewStatusTitle(_ status: String) -> String {
        switch status {
        case "WAITING": "审核中"
        case "APPROVED": "已发布"
        case "REJECTED": "未通过"
        case "NONE": "尚未申请"
        default: "状态更新中"
        }
    }

    private func deleteStatusTitle(_ status: String?) -> String {
        switch status {
        case "WAITING": "处理中"
        case "APPROVED": "已处理"
        case "REJECTED": "未通过"
        case "NONE", nil: "尚未申请"
        default: "状态更新中"
        }
    }
}

private struct FullscreenImageItem: Identifiable {
    let id: String
    let url: URL

    init(url: URL) {
        self.url = url
        id = url.absoluteString
    }
}

private typealias AiGenerationStateSection = SetuStateSection

private struct FullscreenImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            ZStack {
                SetuColor.bgBase.ignoresSafeArea()
                GeometryReader { proxy in
                    SetuRemoteImage(
                        urlString: url.absoluteString,
                        accessibilityLabel: "AI 作品全屏预览",
                        width: proxy.size.width,
                        height: proxy.size.height,
                        cornerRadius: 0,
                        contentMode: .fit
                    )
                }
                .padding(.horizontal, 8)
            }
            .navigationTitle("图片预览")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
