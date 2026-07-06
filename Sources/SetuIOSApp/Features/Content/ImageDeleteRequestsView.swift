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
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("删除申请加载失败", systemImage: "trash.slash", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无删除申请", systemImage: "trash", description: Text("你提交过的图片删除申请会显示在这里。"))
                } else {
                    Section("共 \(page.total) 条") {
                        ForEach(page.list) { request in
                            Button {
                                router.navigate(to: .imageDeleteRequestDetail(request.id))
                            } label: {
                                ImageDeleteRequestRow(request: request)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .navigationTitle("我的删除申请")
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PageResult<ImageDeleteRequestItem>) -> some View {
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
        do {
            state = .loaded(try await environment.imageDeleteRequestClient.listMine(page: page, pageSize: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct ImageDeleteRequestRow: View {
    let request: ImageDeleteRequestItem

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: request.thumbnailUrl)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Text(request.imageTitle ?? "PID \(request.pid)")
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    RequestStatusBadge(title: request.statusTitle, status: request.status)
                }

                if let author = request.imageAuthor, !author.isEmpty {
                    Text(author)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(request.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label("\(request.pid)-\(request.p)", systemImage: "number")
                    Label(request.createdAt, systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
            return .orange
        case 1:
            return .green
        case 2:
            return .red
        default:
            return .secondary
        }
    }
}
