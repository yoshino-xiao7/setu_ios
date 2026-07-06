import SetuIOSCore
import SwiftUI

struct ImageDeleteRequestDetailView: View {
    @Bindable var environment: AppEnvironment
    let requestID: Int

    @State private var state: LoadState<ImageDeleteRequestDetail> = .idle

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("申请详情加载失败", systemImage: "trash.slash", description: Text(message))
            case .loaded(let detail):
                statusSection(detail)
                imageSection(detail)
                reasonSection(detail)
                if detail.status != 0 {
                    reviewSection(detail)
                }
            }
        }
        .navigationTitle("申请详情")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func statusSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section("申请状态") {
            HStack {
                RequestStatusBadge(title: detail.statusTitle, status: detail.status)
                Spacer()
                Text(detail.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("申请人", value: detail.userNickname.isEmpty ? detail.userEmail : detail.userNickname)
            LabeledContent("申请 ID", value: "\(detail.id)")
        }
    }

    @ViewBuilder
    private func imageSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section("图片信息") {
            if detail.status == 1 {
                Label("该图片已被删除", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                DetailImagePreview(urlString: detail.urlOriginal)
            }

            LabeledContent("PID", value: "\(detail.pid)_p\(detail.p)")
            if let title = detail.title, !title.isEmpty {
                LabeledContent("标题", value: title)
            }
            if let author = detail.author, !author.isEmpty {
                LabeledContent("作者", value: author)
            }
            if let uid = detail.uid {
                LabeledContent("作者 UID", value: "\(uid)")
            }
            if let width = detail.width, let height = detail.height {
                LabeledContent("尺寸", value: "\(width) x \(height)")
            }
            if let ext = detail.ext, !ext.isEmpty {
                LabeledContent("格式", value: ext)
            }
            if let r18 = detail.r18 {
                LabeledContent("R18", value: r18 == 1 ? "是" : "否")
            }
            if let tags = detail.tags, !tags.isEmpty {
                TagFlow(tags: tags)
            }
        }
    }

    @ViewBuilder
    private func reasonSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section("申请原因") {
            Text(detail.reason.isEmpty ? "无" : detail.reason)
                .font(.body)
                .foregroundStyle(detail.reason.isEmpty ? .secondary : .primary)
        }
    }

    @ViewBuilder
    private func reviewSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section("审核信息") {
            LabeledContent("审核人", value: detail.adminEmail ?? "-")
            LabeledContent("审核时间", value: detail.reviewedAt ?? "-")
            if let remark = detail.adminRemark, !remark.isEmpty {
                LabeledContent("备注", value: remark)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.imageDeleteRequestClient.detail(id: requestID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct DetailImagePreview: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
            Text("暂无预览")
                .font(.caption)
        }
        .foregroundStyle(.pink)
    }
}
