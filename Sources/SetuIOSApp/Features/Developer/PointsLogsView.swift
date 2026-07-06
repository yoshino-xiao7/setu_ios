import SetuIOSCore
import SwiftUI

struct PointsLogsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PointsLogPage> = .idle

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
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.bizType)
                                        .font(.headline)
                                    Spacer()
                                    Text(item.delta >= 0 ? "+\(item.delta)" : "\(item.delta)")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(item.delta >= 0 ? .green : .red)
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
                    }
                }
            }
        }
        .navigationTitle("积分流水")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.pointsClient.logs())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
