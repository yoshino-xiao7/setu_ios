import SetuIOSCore
import SwiftUI

struct ImageDeleteRequestDetailView: View {
    @Bindable var environment: AppEnvironment
    let requestID: Int

    @State private var state: LoadState<ImageDeleteRequestDetail> = .idle

    var body: some View {
        SetuBoard {
            switch state {
            case .idle, .loading:
                ImageDeleteStateSection(title: "申请详情", stateTitle: "正在加载申请详情", systemImage: "trash", isLoading: true)
            case .failed(let message):
                ImageDeleteStateSection(
                    title: "申请详情",
                    stateTitle: "申请详情加载失败",
                    message: message,
                    systemImage: "trash.slash",
                    actionTitle: "重试",
                    action: { Task { await load() } }
                )
            case .loaded(let detail):
                statusSection(detail)
                imageSection(detail)
                reasonSection(detail)
                if detail.status != 0 {
                    reviewSection(detail)
                }
            }
        }

        .setuBackground()
        .navigationTitle("申请详情")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func statusSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuRecordCard(
            headline: "申请状态",
            status: .init(detail.statusTitle, tone: detail.status == 0 ? .warning : detail.status == 1 ? .success : .danger),
            fields: [
                .init("申请人", detail.userNickname.isEmpty ? detail.userEmail : detail.userNickname, isNumeric: false),
                .init("申请时间", SetuDateFormatter.string(from: detail.createdAt), isNumeric: false),
            ])
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

                    if let title = detail.title, !title.isEmpty {
                        ImageDeleteMetadataRow(title: "标题", value: title)
                    }
                    if let author = detail.author, !author.isEmpty {
                        ImageDeleteMetadataRow(title: "作者", value: author)
                    }
                    if let width = detail.width, let height = detail.height {
                        ImageDeleteMetadataRow(title: "画幅", value: "\(width) × \(height)")
                    }
                    if let ext = detail.ext, !ext.isEmpty {
                        ImageDeleteMetadataRow(title: "格式", value: ext)
                    }
                    if let r18 = detail.r18 {
                        ImageDeleteMetadataRow(title: "内容级别", value: r18 == 1 ? "包含 18+ 内容" : "普通内容")
                    }
                    if let tags = detail.tags, !tags.isEmpty {
                        TagFlow(tags: tags)
                    }
                }
            }

        }
    }

    @ViewBuilder
    private func reasonSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuRecordCard(headline: "申请原因", supporting: detail.reason.isEmpty ? "无" : detail.reason)
    }

    @ViewBuilder
    private func reviewSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuRecordCard(
            headline: "处理结果", supporting: detail.adminRemark,
            fields: [.init("处理时间", detail.reviewedAt.map { SetuDateFormatter.string(from: $0, style: .full) } ?? "尚未处理", isNumeric: false)])
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.imageDeleteRequestClient.detail(id: requestID))
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

struct ImageDeleteMetadataRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String

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
            valueLabel
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 32)
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            titleLabel
            valueLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLabel: some View {
        Text(title)
            .font(SetuTypography.caption)
            .foregroundStyle(SetuColor.textSecondary)
    }

    private var valueLabel: some View {
        Text(value)
            .font(SetuTypography.body)
            .foregroundStyle(SetuColor.textPrimary)
    }
}

struct DetailImagePreview: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, URL(string: urlString) != nil {
                SetuRemoteImage(
                    urlString: urlString,
                    accessibilityLabel: "待处理图片预览",
                    width: nil,
                    height: 260,
                    cornerRadius: SetuRadius.sm,
                    contentMode: .fit
                )
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
