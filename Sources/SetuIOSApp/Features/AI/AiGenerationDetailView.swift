import SetuIOSCore
import SwiftUI

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
                infoSection(job)
                promptSection(job)
                linkSection
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
                ContentUnavailableView("暂无图片", systemImage: "photo")
            }
        }
    }

    private func infoSection(_ job: AiGenerationJob) -> some View {
        Section("状态") {
            LabeledContent("状态", value: job.statusTitle)
            LabeledContent("尺寸", value: "\(job.width)x\(job.height)")
            LabeledContent("步数", value: "\(job.steps)")
            LabeledContent("CFG", value: job.cfg.formatted(.number.precision(.fractionLength(1))))
            if let checkpoint = job.checkpoint, !checkpoint.isEmpty {
                LabeledContent("Checkpoint", value: checkpoint)
            }
            if let lora = job.loraName, !lora.isEmpty {
                LabeledContent("LoRA", value: lora)
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

    private var linkSection: some View {
        Section("链接") {
            Button("获取临时图片链接") {
                Task { await fetchImageURL() }
            }
            Button("获取下载链接") {
                Task { await fetchDownload() }
            }
            if let imageURL {
                Text(imageURL.url)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Text("\(imageURL.expiresInSeconds) 秒内有效")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let download {
                Text(download.downloadUrl)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
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
            TextField("删除原因", text: $deleteReason, axis: .vertical)
            Button("提交删除申请", role: .destructive) {
                Task { await submitDeleteRequest() }
            }
            .disabled(deleteReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            state = .loaded(try await environment.aiGenerationClient.get(id: jobID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchImageURL() async {
        do {
            imageURL = try await environment.aiGenerationClient.imageURL(id: jobID)
            message = "已获取临时图片链接"
        } catch {
            message = error.localizedDescription
        }
    }

    private func fetchDownload() async {
        do {
            download = try await environment.aiGenerationClient.download(id: jobID)
            message = "已获取下载链接"
        } catch {
            message = error.localizedDescription
        }
    }

    private func submitReview() async {
        do {
            let review = try await environment.aiGenerationClient.submitReview(
                id: jobID,
                category: publicCategory,
                note: reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            message = "审核申请已提交：\(review.status)"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func submitDeleteRequest() async {
        let reason = deleteReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        do {
            let request = try await environment.aiGenerationClient.submitDeleteRequest(id: jobID, reason: reason)
            message = "删除申请已提交：\(request.status)"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}
