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
                ImageDeleteStateSection(title: "申请详情", stateTitle: "正在加载申请详情", systemImage: "trash", isLoading: true)
            case .failed(let message):
                ImageDeleteStateSection(title: "申请详情", stateTitle: "申请详情加载失败", message: message, systemImage: "trash.slash")
            case .loaded(let detail):
                statusSection(detail)
                imageSection(detail)
                reasonSection(detail)
                if detail.status != 0 {
                    reviewSection(detail)
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("申请详情")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func statusSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "申请状态")
                    HStack {
                        RequestStatusBadge(title: detail.statusTitle, status: detail.status)
                        Spacer()
                        Label(detail.createdAt, systemImage: "calendar")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                    ImageDeleteMetadataRow(title: "申请人", value: detail.userNickname.isEmpty ? detail.userEmail : detail.userNickname)
                    ImageDeleteMetadataRow(title: "申请 ID", value: "\(detail.id)")
                }
            }
            .setuListRow()
        }
    }

    @ViewBuilder
    private func imageSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "图片信息")
                    if detail.status == 1 {
                        SetuPill(text: "该图片已被删除", systemImage: "checkmark.circle", tone: .success)
                    } else {
                        DetailImagePreview(urlString: detail.urlOriginal)
                    }

                    ImageDeleteMetadataRow(title: "PID", value: "\(detail.pid)_p\(detail.p)")
                    if let title = detail.title, !title.isEmpty {
                        ImageDeleteMetadataRow(title: "标题", value: title)
                    }
                    if let author = detail.author, !author.isEmpty {
                        ImageDeleteMetadataRow(title: "作者", value: author)
                    }
                    if let uid = detail.uid {
                        ImageDeleteMetadataRow(title: "作者 UID", value: "\(uid)")
                    }
                    if let width = detail.width, let height = detail.height {
                        ImageDeleteMetadataRow(title: "尺寸", value: "\(width) x \(height)")
                    }
                    if let ext = detail.ext, !ext.isEmpty {
                        ImageDeleteMetadataRow(title: "格式", value: ext)
                    }
                    if let r18 = detail.r18 {
                        ImageDeleteMetadataRow(title: "R18", value: r18 == 1 ? "是" : "否")
                    }
                    if let tags = detail.tags, !tags.isEmpty {
                        TagFlow(tags: tags)
                    }
                }
            }
            .setuListRow()
        }
    }

    @ViewBuilder
    private func reasonSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "申请原因")
                    Text(detail.reason.isEmpty ? "无" : detail.reason)
                        .font(SetuTypography.body)
                        .foregroundStyle(detail.reason.isEmpty ? SetuColor.textSecondary : SetuColor.textPrimary)
                }
            }
            .setuListRow()
        }
    }

    @ViewBuilder
    private func reviewSection(_ detail: ImageDeleteRequestDetail) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "审核信息")
                    ImageDeleteMetadataRow(title: "审核人", value: detail.adminEmail ?? "-")
                    ImageDeleteMetadataRow(title: "审核时间", value: detail.reviewedAt ?? "-")
                    if let remark = detail.adminRemark, !remark.isEmpty {
                        ImageDeleteMetadataRow(title: "备注", value: remark)
                    }
                }
            }
            .setuListRow()
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

struct ImageDeleteMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
    }
}

struct DetailImagePreview: View {
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
        .background(SetuColor.brandSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
            Text("暂无预览")
                .font(.caption)
        }
        .foregroundStyle(SetuColor.brandPink)
    }
}
