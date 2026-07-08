import SetuIOSCore
import SwiftUI

struct AiDeleteRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    var showsCloseButton = false
    @State private var state: LoadState<PageResult<AiGenerationDeleteRequest>> = .idle
    @State private var statusFilter = "ALL"
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        List {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "筛选")
                        Picker("状态", selection: $statusFilter) {
                            Text("全部").tag("ALL")
                            Text("待审核").tag("WAITING")
                            Text("已通过").tag("APPROVED")
                            Text("已拒绝").tag("REJECTED")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: statusFilter) {
                            Task { await load(resetPage: true) }
                        }
                    }
                }
                .setuListRow()
            }

            content
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("AI 删除申请")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AiDeleteRequestStateSection(title: "删除申请", stateTitle: "正在加载 AI 删除申请", systemImage: "xmark.bin", isLoading: true)
        case .failed(let message):
            AiDeleteRequestStateSection(title: "删除申请", stateTitle: "AI 删除申请加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let result):
            if result.list.isEmpty {
                AiDeleteRequestStateSection(
                    title: "删除申请",
                    stateTitle: "暂无 AI 删除申请",
                    message: "在 AI 任务详情中提交删除申请后，会显示在这里。",
                    systemImage: "xmark.bin"
                )
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "删除申请", subtitle: "共 \(result.total) 条")
                            VStack(spacing: 0) {
                                ForEach(Array(result.list.enumerated()), id: \.element.id) { index, request in
                                    UserAiDeleteRequestRow(request: request)

                                    if index < result.list.count - 1 {
                                        Divider().overlay(SetuColor.separator)
                                    }
                                }
                            }
                        }
                    }
                    .setuListRow()
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationDeleteRequest>) -> some View {
        Section {
            SetuCard {
                HStack(spacing: SetuSpacing.md) {
                    Button {
                        Task {
                            page = max(1, page - 1)
                            await load(resetPage: false)
                        }
                    } label: {
                        Label("上一页", systemImage: "chevron.left")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(page <= 1 ? SetuColor.textTertiary : SetuColor.brandInk)
                    .frame(minHeight: 44)
                    .disabled(page <= 1)

                    Spacer()
                    Text("第 \(result.page) 页")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    Spacer()

                    Button {
                        Task {
                            page += 1
                            await load(resetPage: false)
                        }
                    } label: {
                        Label("下一页", systemImage: "chevron.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(result.page * result.pageSize >= result.total ? SetuColor.textTertiary : SetuColor.brandInk)
                    .frame(minHeight: 44)
                    .disabled(result.page * result.pageSize >= result.total)
                }
            }
            .setuListRow()
        }
    }

    private func load(resetPage: Bool) async {
        if resetPage {
            page = 1
        }
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.deleteRequests(
                status: statusFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AiDeleteRequestStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
                }
            }
            .setuListRow()
        }
    }
}

private struct UserAiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            HStack(alignment: .top, spacing: SetuSpacing.md) {
                AiDeleteRequestThumbnail(urlString: request.job?.imageUrl, status: request.job?.status)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("申请 #\(request.id) · 任务 #\(request.jobId)")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(request.job?.promptCn ?? "任务记录不可用")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        StatusBadge(title: request.statusTitle, status: request.status)
                        if let createdAt = request.createdAt {
                            Label(createdAt, systemImage: "calendar")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                }
            }

            if let reason = request.reason, !reason.isEmpty {
                Text("申请原因：\(reason)")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            if let rejectReason = request.rejectReason, !rejectReason.isEmpty {
                SetuPill(text: "拒绝原因：\(rejectReason)", systemImage: "xmark.circle", tone: .danger)
            }
            if let reviewedAt = request.reviewedAt {
                Label("审核时间：\(reviewedAt)", systemImage: "checkmark.seal")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
        .padding(.vertical, SetuSpacing.sm)
    }
}

private struct AiDeleteRequestThumbnail: View {
    let urlString: String?
    let status: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 72)
        .background(SetuColor.brandSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "photo")
            if let status {
                Text(status)
                    .font(.caption2)
            }
        }
        .foregroundStyle(SetuColor.brandPink)
    }
}
