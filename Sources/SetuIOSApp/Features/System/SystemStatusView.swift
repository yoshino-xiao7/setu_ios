import SetuIOSCore
import SwiftUI

struct SystemStatusView: View {
    @Bindable var environment: AppEnvironment
    let title: String
    @State private var state: LoadState<StatusOverview> = .idle

    init(environment: AppEnvironment, title: String = "系统状态") {
        self.environment = environment
        self.title = title
    }

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let overview):
                Section("API 状态") {
                    LabeledContent("状态", value: overview.status.status)
                    LabeledContent("今日调用", value: String(overview.status.callsToday))
                    LabeledContent("可用性", value: overview.status.availability.map { "\($0)%" } ?? "-")
                    LabeledContent("平均延迟", value: overview.status.avgLatencyMs.map { "\($0) ms" } ?? "-")
                }

                if let health = overview.health {
                    Section("健康检查") {
                        LabeledContent("状态", value: health.status)
                        LabeledContent("代码", value: health.code)
                        LabeledContent("检查时间", value: health.checkedAt)
                    }
                }
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.statusClient.overview())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
