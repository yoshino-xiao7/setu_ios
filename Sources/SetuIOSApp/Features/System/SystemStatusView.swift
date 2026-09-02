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
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "系统状态加载失败", message: message, systemImage: "exclamationmark.triangle")
                            Button {
                                Task { await load() }
                            } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SetuColor.brandInk)
                        }
                    }
                }
            case .loaded(let snapshot):
                let overview = snapshot.overview
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            HStack(alignment: .top) {
                                SetuSectionHeader(title: "服务状态", subtitle: "近 5 分钟运行概览")
                                Spacer()
                                SetuPill(
                                    text: statusTitle(overview.status.status),
                                    systemImage: "waveform.path.ecg",
                                    tone: statusTone(overview.status.status)
                                )
                            }
                            LazyVGrid(columns: statColumns, spacing: SetuSpacing.sm) {
                                SetuStatTile(
                                    title: "今日使用",
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
                                    title: "平均响应时间",
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
                                    SetuSectionHeader(title: "运行检查", subtitle: "服务最近一次检查结果")
                                    Spacer()
                                    SetuPill(
                                        text: statusTitle(health.status, healthy: health.healthy),
                                        systemImage: "heart.text.square",
                                        tone: statusTone(health.status, healthy: health.healthy)
                                    )
                                }
                                StatusInfoRow(
                                    title: "检查时间",
                                    value: SetuDateFormatter.string(from: health.checkedAt, style: .full)
                                )
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
