import SetuIOSCore
import SwiftUI

struct DashboardView: View {
    @Bindable var environment: AppEnvironment
    @Environment(RouterPath.self) private var router
    @State private var state: LoadState<HomeDashboardSnapshot> = .idle
    @State private var usageLogPage = 1
    @State private var usageLogPageSize = 10

    private let usageLogPageSizes = [10, 20, 50]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("雪涼云")
                        .font(.largeTitle.bold())
                    Text("原生 iOS 控制台")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            dashboardSummary
            usageLogsSection

            Section("常用功能") {
                FeatureRow(title: "API Keys", systemImage: "key") {
                    router.navigate(to: .apiKeys)
                }
                FeatureRow(title: "积分调用", systemImage: "bolt.circle") {
                    router.navigate(to: .points)
                }
                FeatureRow(title: "积分流水", systemImage: "list.bullet.rectangle") {
                    router.navigate(to: .pointsLogs)
                }
                FeatureRow(title: "通知中心", systemImage: "bell") {
                    router.navigate(to: .notifications)
                }
            }

            Section("创作与内容") {
                FeatureRow(title: "AI 绘图历史", systemImage: "clock") {
                    router.navigate(to: .aiHistory)
                }
                FeatureRow(title: "收藏夹广场", systemImage: "globe.asia.australia") {
                    router.navigate(to: .collectionSquare)
                }
                FeatureRow(title: "音乐歌单", systemImage: "music.note.list") {
                    router.navigate(to: .playlists)
                }
            }
        }
        .navigationTitle("首页")
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private var dashboardSummary: some View {
        Section("概览") {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("加载失败")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        Task { await load() }
                    }
                }
                .padding(.vertical, 4)
            case .loaded(let snapshot):
                DashboardMetricRow(
                    title: "今日调用",
                    value: snapshot.usage.map { String($0.todayCalls) } ?? "-",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                DashboardMetricRow(
                    title: "总调用",
                    value: snapshot.usage.map { String($0.totalCalls) } ?? "-",
                    systemImage: "sum"
                )
                DashboardMetricRow(
                    title: "Key 使用",
                    value: snapshot.apiKeyCount.map { "\($0)/10" } ?? "-",
                    systemImage: "key"
                )
                DashboardMetricRow(
                    title: "上次活跃",
                    value: snapshot.usage?.lastCalledAt ?? "-",
                    systemImage: "clock"
                )
                DashboardMetricRow(
                    title: "积分余额",
                    value: snapshot.points.map { String($0.points) } ?? "-",
                    systemImage: "bolt.circle"
                )
                DashboardMetricRow(
                    title: "未读通知",
                    value: snapshot.unreadNotifications.map { String($0) } ?? "-",
                    systemImage: "bell"
                )
                DashboardMetricRow(
                    title: "服务状态",
                    value: snapshot.status?.status.status ?? "-",
                    systemImage: "waveform.path.ecg"
                )
            }
        }
    }

    @ViewBuilder
    private var usageLogsSection: some View {
        Section("最近调用日志") {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载调用日志")
            case .failed:
                EmptyView()
            case .loaded(let snapshot):
                if let logs = snapshot.usageLogs?.list, !logs.isEmpty {
                    ForEach(logs) { log in
                        UsageLogRow(log: log)
                    }
                    if let total = snapshot.usageLogs?.total {
                        usageLogControls(total: total)
                    }
                } else {
                    ContentUnavailableView("暂无调用日志", systemImage: "clock.arrow.circlepath")
                }
            }
        }
    }

    private func usageLogControls(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu("每页 \(usageLogPageSize)") {
                ForEach(usageLogPageSizes, id: \.self) { size in
                    Button("\(size) 条") {
                        usageLogPageSize = size
                        usageLogPage = 1
                        Task { await load() }
                    }
                }
            }

            HStack {
                Button("上一页") {
                    Task {
                        usageLogPage = max(1, usageLogPage - 1)
                        await load()
                    }
                }
                .disabled(usageLogPage <= 1)

                Spacer()
                Text("第 \(usageLogPage) / \(max(1, Int(ceil(Double(total) / Double(usageLogPageSize))))) 页，共 \(total) 条")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()

                Button("下一页") {
                    Task {
                        usageLogPage += 1
                        await load()
                    }
                }
                .disabled(usageLogPage * usageLogPageSize >= total)
            }
        }
    }

    private func load() async {
        state = .loading
        let snapshot = await environment.dashboardClient.fetchHomeSnapshot(usageLogPage: usageLogPage, usageLogLimit: usageLogPageSize)
        state = .loaded(snapshot)
    }
}

private struct UsageLogRow: View {
    let log: UsageLogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(log.endpoint)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(log.status)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(statusColor)
            }
            HStack(spacing: 12) {
                Label(log.ip, systemImage: "network")
                Label(log.timestamp, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        (200..<400).contains(log.status) ? .green : .red
    }
}

private struct DashboardMetricRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.pink)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}
