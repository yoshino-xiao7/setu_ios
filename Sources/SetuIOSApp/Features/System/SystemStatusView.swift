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
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "waveform.path.ecg", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "系统状态加载失败", message: message, systemImage: "exclamationmark.triangle")
                    }
                }
            case .loaded(let snapshot):
                let overview = snapshot.overview
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            HStack(alignment: .top) {
                                SetuSectionHeader(title: "API 状态", subtitle: "近 5 分钟服务概览")
                                Spacer()
                                SetuPill(
                                    text: overview.status.status,
                                    systemImage: "waveform.path.ecg",
                                    tone: statusTone(overview.status.status)
                                )
                            }
                            LazyVGrid(columns: statColumns, spacing: SetuSpacing.sm) {
                                SetuStatTile(
                                    title: "今日调用",
                                    value: String(overview.status.callsToday),
                                    systemImage: "arrow.left.arrow.right",
                                    color: SetuColor.brandPink
                                )
                                SetuStatTile(
                                    title: "服务可用性",
                                    value: availabilityText(overview.status.availability),
                                    systemImage: "checkmark.seal",
                                    color: SetuColor.success
                                )
                                SetuStatTile(
                                    title: "平均响应延迟",
                                    value: latencyText(overview.status.avgLatencyMs),
                                    systemImage: "timer",
                                    color: SetuColor.info
                                )
                                SetuStatTile(
                                    title: "图库数量",
                                    value: snapshot.imageCount.map(String.init) ?? "-",
                                    systemImage: "photo.on.rectangle",
                                    color: SetuColor.warning
                                )
                            }
                            if let lastUpdatedAt {
                                Label("更新于 \(lastUpdatedAt.formatted(date: .omitted, time: .standard))", systemImage: "clock")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                        }
                    }
                }

                if let health = overview.health {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                HStack {
                                    SetuSectionHeader(title: "健康检查", subtitle: "后端返回的最近一次检查结果")
                                    Spacer()
                                    SetuPill(
                                        text: health.status,
                                        systemImage: "heart.text.square",
                                        tone: statusTone(health.status)
                                    )
                                }
                                StatusInfoRow(title: "代码", value: health.code)
                                StatusInfoRow(title: "检查时间", value: health.checkedAt)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private var statColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: SetuSpacing.sm),
            GridItem(.flexible(), spacing: SetuSpacing.sm)
        ]
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

    private func statusTone(_ value: String) -> SetuPillTone {
        let normalized = value.lowercased()
        if normalized.contains("up") || normalized.contains("ok") || normalized.contains("healthy") || value.contains("正常") {
            return .success
        }
        if normalized.contains("warn") || value.contains("警告") {
            return .warning
        }
        if normalized.contains("down") || normalized.contains("error") || value.contains("异常") {
            return .danger
        }
        return .info
    }
}

private struct SystemStatusSnapshot: Sendable {
    let overview: StatusOverview
    let imageCount: Int?
}

private struct StatusInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
            Spacer(minLength: SetuSpacing.md)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
