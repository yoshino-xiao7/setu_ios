import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct AiGenerationDetailView: View {
    @Bindable var environment: AppEnvironment
    let jobID: Int
    @State private var state: LoadState<AiGenerationJob> = .idle
    @State private var publicCategory = "GENERAL"
    @State private var reviewNote = ""
    @State private var deleteReason = ""
    @State private var imageURL: AiImageURL?
    @State private var download: AiImageDownload?
    @State private var message: String?
    @State private var capabilities: AiCapabilityResponse?
    @State private var fullscreenImage: FullscreenImageItem?
    @State private var isPolling = false
    @State private var lastRefreshedAt: Date?

    var body: some View {
        List {
            if let message {
                SetuCard {
                    Label(message, systemImage: "checkmark.circle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .setuListRow()
            }

            switch state {
            case .idle, .loading:
                AiGenerationStateSection(title: "AI 任务", stateTitle: "正在加载任务", systemImage: "sparkles.rectangle.stack", isLoading: true)
            case .failed(let message):
                AiGenerationStateSection(title: "AI 任务", stateTitle: "任务加载失败", message: message, systemImage: "sparkles.rectangle.stack")
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
        .navigationTitle("AI 任务 #\(jobID)")
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
                Button {
                    fullscreenImage = FullscreenImageItem(url: url)
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                                        .stroke(SetuColor.separator, lineWidth: 1)
                                }
                        case .failure:
                            SetuEmptyState(title: "图片加载失败", message: "可以尝试刷新图片。", systemImage: "photo")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        default:
                            SetuEmptyState(title: "正在加载图片", systemImage: "photo", isLoading: true)
                                .frame(maxWidth: .infinity, minHeight: 280)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                SetuEmptyState(
                    title: "暂无图片",
                    message: job.status == "COMPLETED" ? "可以尝试刷新图片。" : "任务完成后会显示预览。",
                    systemImage: "photo"
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
            }
        }
        .setuListRow()
    }

    private func imageActionsSection(_ job: AiGenerationJob) -> some View {
        Section("图片操作") {
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

            if let imageURL {
                Label("\(imageURL.expiresInSeconds) 秒内有效", systemImage: "clock")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
    }

    private func infoSection(_ job: AiGenerationJob) -> some View {
        Section("状态") {
            LabeledContent("状态", value: job.statusTitle)
            if !job.isTrackingFinished {
                Label("正在自动刷新任务状态", systemImage: "arrow.triangle.2.circlepath")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            if let lastRefreshedAt {
                LabeledContent("最近刷新", value: lastRefreshedAt.formatted(date: .omitted, time: .standard))
            }
            if let detail = job.workerDetail, !detail.isEmpty {
                LabeledContent("节点状态", value: detail)
            } else if let stage = job.workerStage, !stage.isEmpty {
                LabeledContent("节点阶段", value: stage)
            }
            LabeledContent("尺寸", value: "\(job.width)x\(job.height)")
            LabeledContent("步数", value: "\(job.steps)")
            LabeledContent("CFG", value: job.cfg.formatted(.number.precision(.fractionLength(1))))
            LabeledContent("Seed", value: job.seed.map(String.init) ?? "随机")
            LabeledContent("生成模式", value: job.generationMode == "DUAL" ? "双角色" : "单角色")
            LabeledContent("图片保留", value: imageRetentionTitle(job.privateOssStatus))
            LabeledContent("清理时间", value: job.privateOssExpiresAt ?? "-")
            LabeledContent("模型", value: checkpointDisplayName(job.checkpoint))
            if let lora = job.loraName, !lora.isEmpty {
                LabeledContent("LoRA", value: lora)
            }
            if job.generationMode == "DUAL" {
                let secondLora = job.secondLoraName?.isEmpty == false ? job.secondLoraName ?? "" : "不使用第二 LoRA"
                LabeledContent("第二 LoRA", value: secondLora)
            }
            if let cost = job.pointsCost {
                LabeledContent("积分", value: "\(cost)")
            }
            if let createdAt = job.createdAt {
                LabeledContent("创建时间", value: createdAt)
            }
            if let completedAt = job.completedAt {
                LabeledContent("完成时间", value: completedAt)
            }
            if let error = job.userErrorMessage ?? job.errorMessage, !error.isEmpty {
                Text(error)
                    .foregroundStyle(SetuColor.danger)
            }
        }
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
            return status ?? "-"
        }
    }

    private func promptSection(_ job: AiGenerationJob) -> some View {
        Section("提示词") {
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

    private func copyPrompt(_ job: AiGenerationJob) {
        let text = [
            "正向提示词：\(job.promptPositive ?? job.promptCn)",
            "反向提示词：\(job.promptNegative ?? "")"
        ].joined(separator: "\n")
        PlatformClipboard.copy(text)
        message = "提示词已复制"
    }

    private func reviewSection(_ job: AiGenerationJob) -> some View {
        Section("公开审核") {
            LabeledContent("当前状态", value: job.reviewStatus)
            Picker("分类", selection: $publicCategory) {
                Text("全年龄").tag("GENERAL")
                Text("R18").tag("R18")
            }
            TextField("提交备注", text: $reviewNote, axis: .vertical)
            Button("提交公开审核") {
                Task { await submitReview() }
            }
            .disabled(job.status != "COMPLETED")
        }
    }

    private func deleteRequestSection(_ job: AiGenerationJob) -> some View {
        Section("删除申请") {
            LabeledContent("当前状态", value: job.deleteStatus ?? "NONE")
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

    private func load(showLoading: Bool = true) async {
        if showLoading {
            state = .loading
        }
        message = nil
        do {
            async let job = environment.aiGenerationClient.get(id: jobID)
            async let capabilityResponse = try? environment.aiGenerationClient.capabilities()
            let loadedJob = try await job
            state = .loaded(loadedJob)
            capabilities = await capabilityResponse
            lastRefreshedAt = Date()
            await AiGenerationLiveActivityCenter.update(job: loadedJob, mobileClient: environment.mobileAppClient)
        } catch {
            state = .failed(error.localizedDescription)
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
                return match.displayName?.isEmpty == false ? match.displayName ?? checkpoint : checkpoint
            }
            return checkpoint
        }
        if let onlyCheckpoint = capabilities?.checkpoints.first, capabilities?.checkpoints.count == 1 {
            return "默认模型（\(onlyCheckpoint.displayName?.isEmpty == false ? onlyCheckpoint.displayName ?? onlyCheckpoint.name : onlyCheckpoint.name)）"
        }
        return "默认模型"
    }

    private func fetchImageURL() async {
        do {
            imageURL = try await environment.aiGenerationClient.imageURL(id: jobID)
            message = "图片已刷新"
        } catch {
            message = error.localizedDescription
        }
    }

    private func fetchDownload() async {
        do {
            download = try await environment.aiGenerationClient.download(id: jobID)
            if let download {
                openDownload(download)
            }
            message = "已打开下载"
        } catch {
            message = error.localizedDescription
        }
    }

    private func openDownload(_ download: AiImageDownload) {
        guard let url = URL(string: download.downloadUrl) else {
            message = "下载地址无效"
            return
        }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func submitReview() async {
        do {
            let note = reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let review = try await environment.aiGenerationClient.submitReview(
                id: jobID,
                category: publicCategory,
                note: note.isEmpty ? nil : note
            )
            message = "审核申请已提交：\(review.status)"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func submitDeleteRequest() async {
        let reason = deleteReason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let request = try await environment.aiGenerationClient.submitDeleteRequest(id: jobID, reason: reason.isEmpty ? nil : reason)
            message = "删除申请已提交：\(request.status)"
            await load()
        } catch {
            message = error.localizedDescription
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

private struct AiGenerationStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
            }
        }
        .setuListRow()
    }
}

private struct FullscreenImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            ZStack {
                SetuColor.bgBase.ignoresSafeArea()
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        SetuEmptyState(title: "图片加载失败", message: "关闭后可以回到详情页刷新图片。", systemImage: "photo")
                            .background(SetuColor.surfaceMuted.opacity(0.82), in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                            .padding(SetuSpacing.lg)
                    default:
                        SetuEmptyState(title: "正在加载图片", systemImage: "photo", isLoading: true)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                            .padding(SetuSpacing.lg)
                    }
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
