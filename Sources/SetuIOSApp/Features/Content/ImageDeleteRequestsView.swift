import SetuIOSCore
import SwiftUI

struct ImageDeleteRequestsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<ImageDeleteRequestItem>> = .idle
    @State private var page = 1
    private let pageSize = 10

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ImageDeleteStateSection(title: "删除申请", stateTitle: "正在加载删除申请", systemImage: "trash", isLoading: true)
            case .failed(let message):
                ImageDeleteStateSection(title: "删除申请", stateTitle: "删除申请加载失败", message: message, systemImage: "trash.slash")
            case .loaded(let page):
                if page.list.isEmpty {
                    ImageDeleteStateSection(title: "删除申请", stateTitle: "暂无删除申请", message: "你提交过的图片删除申请会显示在这里。", systemImage: "trash")
                } else {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "删除申请", subtitle: "共 \(page.total) 条")
                                VStack(spacing: 0) {
                                    ForEach(Array(page.list.enumerated()), id: \.element.id) { index, request in
                                        Button {
                                            router.navigate(to: .imageDeleteRequestDetail(request.id))
                                        } label: {
                                            ImageDeleteRequestRow(request: request)
                                        }
                                        .buttonStyle(.plain)

                                        if index < page.list.count - 1 {
                                            Divider().overlay(SetuColor.separator)
                                        }
                                    }
                                }
                            }
                        }
                        .setuListRow()
                    }
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("我的删除申请")
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PageResult<ImageDeleteRequestItem>) -> some View {
        Section {
            SetuCard {
                HStack(spacing: SetuSpacing.md) {
                    Button {
                        Task {
                            page = max(1, page - 1)
                            await load()
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
                            await load()
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

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.imageDeleteRequestClient.listMine(page: page, pageSize: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct ImageDeleteStateSection: View {
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

struct ImageDeleteRequestRow: View {
    let request: ImageDeleteRequestItem

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            ImageThumbnailView(urlString: request.thumbnailUrl)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                HStack(alignment: .top) {
                    Text(request.imageTitle ?? "PID \(request.pid)")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    RequestStatusBadge(title: request.statusTitle, status: request.status)
                }

                if let author = request.imageAuthor, !author.isEmpty {
                    Text(author)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }

                Text(request.reason)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(2)

                HStack(spacing: SetuSpacing.md) {
                    Label("\(request.pid)-\(request.p)", systemImage: "number")
                    Label(request.createdAt, systemImage: "calendar")
                }
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
    }
}

struct RequestStatusBadge: View {
    let title: String
    let status: Int

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
        case 0:
            return SetuColor.warning
        case 1:
            return SetuColor.success
        case 2:
            return SetuColor.danger
        default:
            return SetuColor.textSecondary
        }
    }
}
