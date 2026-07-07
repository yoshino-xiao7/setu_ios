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

    var body: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("任务加载失败", systemImage: "sparkles.rectangle.stack", description: Text(message))
            case .loaded(let job):
                previewSection(job)
                imageActionsSection(job)
                infoSection(job)
                promptSection(job)
                reviewSection(job)
                deleteRequestSection(job)
            }
        }
        .navigationTitle("AI 任务 #\(jobID)")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func previewSection(_ job: AiGenerationJob) -> some View {
        Section("预览") {
            let urlString = imageURL?.url ?? job.imageUrl
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        ContentUnavailableView("图片加载失败", systemImage: "photo")
                    default:
                        ProgressView("正在加载图片")
                    }
                }
            } else {
                ContentUnavailableView("暂无图片", systemImage: "photo", description: Text(job.status == "COMPLETED" ? "可以尝试刷新图片。" : "任务完成后会显示预览。"))
            }
        }
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoSection(_ job: AiGenerationJob) -> some View {
        Section("状态") {
            LabeledContent("状态", value: job.statusTitle)
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
                    .foregroundStyle(.red)
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
            Text("删除申请通过后，这张图会从你的历史和公共广场中隐藏，并清理 OSS 文件。管理员审计记录和本机归档不会随之删除。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("删除原因", text: $deleteReason, axis: .vertical)
            Button("提交删除申请", role: .destructive) {
                Task { await submitDeleteRequest() }
            }
            .disabled(job.deleted == true || job.deleteStatus == "WAITING" || job.deleteStatus == "APPROVED")
        }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            async let job = environment.aiGenerationClient.get(id: jobID)
            async let capabilityResponse = try? environment.aiGenerationClient.capabilities()
            state = .loaded(try await job)
            capabilities = await capabilityResponse
        } catch {
            state = .failed(error.localizedDescription)
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
