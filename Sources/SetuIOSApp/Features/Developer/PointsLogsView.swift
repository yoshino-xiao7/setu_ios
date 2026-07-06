import SetuIOSCore
import SwiftUI

struct PointsLogsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PointsLogPage> = .idle
    @State private var page = 1
    private let pageSize = 10

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentUnavailableView("暂无积分流水", systemImage: "list.bullet.rectangle")
                } else {
                    Section("共 \(page.total) 条") {
                        ForEach(page.items) { item in
                            PointsLogRow(item: item)
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .navigationTitle("积分流水")
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PointsLogPage) -> some View {
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
                .disabled(result.page * result.size >= result.total)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.pointsClient.logs(page: page, size: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct PointsLogRow: View {
    let item: PointsLogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.bizType)
                    .font(.headline)
                Spacer()
                Text(deltaText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(deltaColor)
            }
            if let endpoint = item.endpoint {
                Text(endpoint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let createdAt = item.createdAt {
                Text(createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var deltaText: String {
        if item.bizType == "ADMIN_CALL" || item.delta == 0 {
            return "∞"
        }
        return item.delta >= 0 ? "+\(item.delta)" : "\(item.delta)"
    }

    private var deltaColor: Color {
        if item.bizType == "ADMIN_CALL" || item.delta == 0 {
            return .orange
        }
        return item.delta >= 0 ? .green : .red
    }
}
