import SetuIOSCore
import SwiftUI

struct SystemStatusView: View {
    @Bindable var environment: AppEnvironment
    let title: String
    @State private var state: LoadState<SystemStatusSnapshot> = .idle
    @State private var lastUpdatedAt: Date?

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
            case .loaded(let snapshot):
                let overview = snapshot.overview
                Section("API 状态") {
                    LabeledContent("状态", value: overview.status.status)
                    LabeledContent("今日调用", value: String(overview.status.callsToday))
                    LabeledContent("服务可用性 (5min)", value: availabilityText(overview.status.availability))
                    LabeledContent("平均响应延迟", value: latencyText(overview.status.avgLatencyMs))
                    LabeledContent("图库数量", value: snapshot.imageCount.map(String.init) ?? "-")
                    if let lastUpdatedAt {
                        LabeledContent("更新于", value: lastUpdatedAt.formatted(date: .omitted, time: .standard))
                    }
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
            async let overview = environment.statusClient.overview()
            async let imageCount = optionalImageCount()
            state = .loaded(try await SystemStatusSnapshot(overview: overview, imageCount: imageCount))
            lastUpdatedAt = Date()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func optionalImageCount() async -> Int? {
        try? await environment.statusClient.imageCount()
    }

    private func availabilityText(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "暂无样本"
        }
        let percent = max(0, min(100, value * 100))
        return percent.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func latencyText(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else {
            return "无近期调用"
        }
        return "\(Int(value.rounded())) ms"
    }
}

private struct SystemStatusSnapshot: Sendable {
    let overview: StatusOverview
    let imageCount: Int?
}
