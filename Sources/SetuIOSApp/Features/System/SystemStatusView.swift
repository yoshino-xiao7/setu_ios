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
        SetuBoard {
            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        AccountSurfaceSkeleton(title: "正在加载系统状态")
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "系统状态加载失败", message: message, systemImage: "exclamationmark.triangle")
                            Button {
                                Task { await load() }
                            } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SetuColor.brandOnLight)
                            .foregroundStyle(.white)
                        }
                    }
                }
            case .loaded(let snapshot):
                let overview = snapshot.overview
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                SetuSectionHeader(title: "服务状态", subtitle: "近 5 分钟运行概览")
                                SetuPill(
                                    text: statusTitle(overview.status.status),
                                    systemImage: "waveform.path.ecg",
                                    tone: statusTone(overview.status.status)
                                )
                            }
                            SetuMetricRing(
                                value: availabilityText(overview.status.availability),
                                caption: "服务可用性",
                                progress: overview.status.availability ?? 0,
                                tone: statusTone(overview.status.status).foreground,
                                accessibilityDescription: "服务可用性，" + availabilityText(overview.status.availability)
                            )
                            if let lastUpdatedAt {
                                Label("更新于 \(lastUpdatedAt.formatted(date: .omitted, time: .standard))", systemImage: "clock")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                        }
                    }
                }

                SetuBento(items: metricItems(snapshot), span: { _ in .small }) { item in
                    SetuBentoTile(title: item.title, subtitle: item.value, systemImage: item.systemImage)
                }

                if let health = overview.health {
                    SetuRecordCard(
                        headline: "运行检查",
                        supporting: "服务最近一次检查结果",
                        status: .init(statusTitle(health.status, healthy: health.healthy), tone: statusTone(health.status, healthy: health.healthy)),
                        fields: [.init("检查时间", SetuDateFormatter.string(from: health.checkedAt, style: .full))]
                    )
                }
            }
        }
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private func metricItems(_ snapshot: SystemStatusSnapshot) -> [AccountSurfaceItem] {
        [
            .init(title: "今日使用", value: String(snapshot.overview.status.callsToday), systemImage: "arrow.left.arrow.right"),
            .init(title: "平均响应时间", value: latencyText(snapshot.overview.status.avgLatencyMs), systemImage: "timer"),
            .init(title: "图库数量", value: snapshot.imageCount.map(String.init) ?? "暂未同步", systemImage: "photo.on.rectangle"),
            .init(title: "服务状态", value: statusTitle(snapshot.overview.status.status), systemImage: "waveform.path.ecg")
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
            state = .failed(UserFacingErrorMapper.map(error))
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
            return "暂无近期数据"
        }
        return "\(Int(value.rounded())) ms"
    }

    private func statusTitle(_ value: String, healthy: Bool? = nil) -> String {
        if healthy == true {
            return "运行正常"
        }

        let normalized = value.lowercased()
        if isWarningStatus(normalized, original: value) {
            return "部分服务波动"
        }
        if healthy == false || isUnavailableStatus(normalized, original: value) {
            return "暂不可用"
        }
        if isHealthyStatus(normalized, original: value) {
            return "运行正常"
        }
        return "状态待确认"
    }

    private func statusTone(_ value: String, healthy: Bool? = nil) -> SetuPillTone {
        if healthy == true {
            return .success
        }

        let normalized = value.lowercased()
        if isWarningStatus(normalized, original: value) {
            return .warning
        }
        if healthy == false || isUnavailableStatus(normalized, original: value) {
            return .danger
        }
        if isHealthyStatus(normalized, original: value) {
            return .success
        }
        return .info
    }

    private func isHealthyStatus(_ normalized: String, original: String) -> Bool {
        normalized == "up"
            || normalized == "ok"
            || normalized == "healthy"
            || normalized == "available"
            || original.contains("正常")
    }

    private func isWarningStatus(_ normalized: String, original: String) -> Bool {
        normalized.contains("warn")
            || normalized.contains("degrad")
            || normalized.contains("partial")
            || original.contains("警告")
            || original.contains("波动")
    }

    private func isUnavailableStatus(_ normalized: String, original: String) -> Bool {
        normalized.contains("unhealthy")
            || normalized.contains("down")
            || normalized.contains("error")
            || normalized.contains("fail")
            || normalized.contains("offline")
            || normalized.contains("unavailable")
            || original.contains("异常")
            || original.contains("不可用")
            || original.contains("离线")
            || original.contains("故障")
            || original.contains("失败")
    }
}

private struct SystemStatusSnapshot: Sendable {
    let overview: StatusOverview
    let imageCount: Int?
}
