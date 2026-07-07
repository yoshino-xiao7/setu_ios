import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct AiHistoryView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationJob>> = .idle
    @State private var statusFilter = ""
    @State private var page = 1
    @State private var message: String?
    @State private var showingDeleteRequests = false
    @State private var previewSelection: AiHistoryPreviewSelection?
    private let pageSize = 12

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

            Picker("状态", selection: $statusFilter) {
                Text("全部").tag("")
                Text("排队中").tag("QUEUED")
                Text("生成中").tag("RUNNING")
                Text("已完成").tag("COMPLETED")
                Text("失败").tag("FAILED")
            }
            .pickerStyle(.segmented)
            .onChange(of: statusFilter) {
                Task {
                    page = 1
                    await load()
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("历史加载失败", systemImage: "clock.badge.exclamationmark", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无 AI 生成记录", systemImage: "sparkles", description: Text("创建绘图任务后，任务状态和结果会显示在这里。"))
                } else {
                    Section("共 \(page.total) 条") {
                        ForEach(page.list) { job in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    router.navigate(to: .aiGenerationDetail(job.id))
                                } label: {
                                    AiGenerationRow(job: job)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    reuse(job)
                                } label: {
                                    Label("复用参数", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .font(.footnote)
                                .buttonStyle(.borderless)

                                HStack {
                                    Button {
                                        copyPrompt(job)
                                    } label: {
                                        Label("复制提示词", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)

                                    if job.status == "COMPLETED" {
                                        Button {
                                            previewSelection = AiHistoryPreviewSelection(job: job)
                                        } label: {
                                            Label("查看", systemImage: "eye")
                                        }
                                        .buttonStyle(.borderless)

                                        Button {
                                            Task { await download(job) }
                                        } label: {
                                            Label("下载", systemImage: "arrow.down.circle")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .font(.footnote)
                            }
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .navigationTitle("AI 绘画历史")
        .toolbar {
            Button {
                showingDeleteRequests = true
            } label: {
                Label("删除申请", systemImage: "xmark.bin")
            }
        }
        .sheet(isPresented: $showingDeleteRequests) {
            AiDeleteRequestsView(environment: environment)
        }
        .sheet(item: $previewSelection) { selection in
            AiGenerationImagePreviewSheet(
                environment: environment,
                job: selection.job,
                onOpenDetail: {
                    previewSelection = nil
                    router.navigate(to: .aiGenerationDetail(selection.job.id))
                },
                onMessage: { message = $0 }
            )
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PageResult<AiGenerationJob>) -> some View {
        Section {
            HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(result.page * result.pageSize >= result.total)
            }
        }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            state = .loaded(try await environment.aiGenerationClient.listMine(status: statusFilter, page: page, pageSize: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func reuse(_ job: AiGenerationJob) {
        AiDrawDraftStore.applyHistoryJob(job)
        router.navigate(to: .aiDraw)
    }

    private func copyPrompt(_ job: AiGenerationJob) {
        let text = [
            "正向提示词：\(job.promptPositive ?? job.promptCn)",
            "反向提示词：\(job.promptNegative ?? "")"
        ].joined(separator: "\n")
        PlatformClipboard.copy(text)
        message = "提示词已复制"
    }

    private func download(_ job: AiGenerationJob) async {
        do {
            let result = try await environment.aiGenerationClient.download(id: job.id)
            openURLString(result.downloadUrl, successMessage: "已打开下载链接")
        } catch {
            message = error.localizedDescription
        }
    }

    private func openURLString(_ value: String, successMessage: String) {
        guard let url = URL(string: value) else {
            message = "链接无效"
            return
        }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
        message = successMessage
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
                    ImageThumbnailView(urlString: job.imageUrl)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.promptCn)
                        .font(.headline)
                        .lineLimit(2)
                    Text("#\(job.id) · \(job.width)x\(job.height) · \(job.steps) 步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(title: job.statusTitle, status: job.status)
            }

            if let detail = job.userErrorMessage ?? job.workerDetail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(job.status == "FAILED" ? .red : .secondary)
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
                    Label(createdAt, systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if job.status == "COMPLETED" {
                HStack(spacing: 8) {
                    StatusBadge(title: "公开：\(reviewStatusTitle)", status: job.reviewStatus)
                    if let publicCategory = job.publicCategory {
                        StatusBadge(title: publicCategory == "R18" ? "R18" : "全年龄", status: publicCategory)
                    }
                    if let deleteStatus = job.deleteStatus, deleteStatus != "NONE" {
                        StatusBadge(title: deleteStatusTitle(deleteStatus), status: deleteStatus)
                    }
                }
            }

            if job.privateOssStatus == "EXPIRED" || job.privateOssStatus == "EXPLICITLY_DELETED" {
                Label("云端原图已清理，生成历史仍会保留", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if job.status == "COMPLETED", let expiresAt = job.privateOssExpiresAt {
                Label("图片仅保留 30 天，预计 \(expiresAt) 清理", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        default: job.reviewStatus
        }
    }

    private func deleteStatusTitle(_ status: String) -> String {
        switch status {
        case "WAITING": "删除待审核"
        case "APPROVED": "删除已通过"
        case "REJECTED": "删除已拒绝"
        default: status
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
    let onMessage: (String) -> Void

    @State private var imageState: LoadState<String> = .idle
    @State private var localMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageStage

                    VStack(alignment: .leading, spacing: 8) {
                        Text(job.promptCn)
                            .font(.headline)
                            .textSelection(.enabled)
                        Text("#\(job.id) · \(job.width)x\(job.height) · \(job.statusTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let localMessage {
                            Text(localMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    actions
                }
                .padding()
            }
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
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        switch imageState {
        case .idle, .loading:
            ProgressView("正在加载图片")
                .frame(maxWidth: .infinity, minHeight: 320)
        case .failed(let message):
            ContentUnavailableView("图片加载失败", systemImage: "photo", description: Text(message))
                .frame(maxWidth: .infinity, minHeight: 320)
        case .loaded(let urlString):
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    case .failure:
                        ContentUnavailableView("图片加载失败", systemImage: "photo", description: Text("可以尝试刷新临时链接。"))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    default:
                        ProgressView("正在加载图片")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
            } else {
                ContentUnavailableView("图片链接无效", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await refreshImageURL() }
            } label: {
                Label("刷新临时链接", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                Task { await download() }
            } label: {
                Label("下载图片", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                copyPrompt()
            } label: {
                Label("复制提示词", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                onOpenDetail()
            } label: {
                Label("查看任务详情", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
            localMessage = "\(result.expiresInSeconds) 秒内有效"
        } catch {
            imageState = .failed(error.localizedDescription)
            localMessage = error.localizedDescription
        }
    }

    private func download() async {
        do {
            let result = try await environment.aiGenerationClient.download(id: job.id)
            guard let url = URL(string: result.downloadUrl) else {
                localMessage = "下载地址无效"
                return
            }
            #if os(iOS)
            await UIApplication.shared.open(url)
            #endif
            localMessage = "已打开下载链接"
            onMessage("已打开下载链接")
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func copyPrompt() {
        let text = [
            "正向提示词：\(job.promptPositive ?? job.promptCn)",
            "反向提示词：\(job.promptNegative ?? "")"
        ].joined(separator: "\n")
        PlatformClipboard.copy(text)
        localMessage = "提示词已复制"
        onMessage("提示词已复制")
    }
}

struct StatusBadge: View {
    let title: String
    let status: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case "COMPLETED": .green
        case "FAILED": .red
        case "RUNNING", "UPLOADING": .blue
        case "APPROVED", "GENERAL": .green
        case "REJECTED", "R18": .red
        case "WAITING": .orange
        default: .orange
        }
    }
}
