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
                VStack(alignment: .leading, spacing: 10) {
                    Text("雪涼云")
                        .font(.largeTitle.bold())
                    Text("创作、刷图、听歌和发现公开内容都从这里开始。")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 8)
            }

            primaryActionsSection
            accountStatusSection

            Section("继续使用") {
                FeatureRow(title: "图片积分调用", systemImage: "bolt.circle") {
                    router.navigate(to: .points)
                }
                FeatureRow(title: "积分流水", systemImage: "list.bullet.rectangle") {
                    router.navigate(to: .pointsLogs)
                }
                FeatureRow(title: "通知中心", systemImage: "bell") {
                    router.navigate(to: .notifications)
                }
            }

            Section("我的内容") {
                FeatureRow(title: "AI 绘画历史", systemImage: "clock") {
                    router.navigate(to: .aiHistory)
                }
                FeatureRow(title: "图库投稿", systemImage: "square.and.arrow.up") {
                    router.navigate(to: .galleryUploads)
                }
                FeatureRow(title: "我的收藏夹", systemImage: "heart.rectangle") {
                    router.navigate(to: .collections)
                }
                FeatureRow(title: "我的收藏", systemImage: "heart.fill") {
                    router.navigate(to: .favorites)
                }
                FeatureRow(title: "我的歌单", systemImage: "music.note.list") {
                    router.navigate(to: .playlists)
                }
            }

            usageLogsSection
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
    private var primaryActionsSection: some View {
        Section("主要功能") {
            HomeActionRow(
                title: "AI 绘画",
                subtitle: "输入提示词创建新作品",
                systemImage: "sparkles",
                tint: .purple
            ) {
                router.navigate(to: .aiDraw)
            }
            HomeActionRow(
                title: "随机图片",
                subtitle: "刷图式浏览，支持参数筛选",
                systemImage: "photo.on.rectangle",
                tint: .pink
            ) {
                router.navigate(to: .imageSwipe)
            }
            HomeActionRow(
                title: "音乐播放器",
                subtitle: "搜索、播放、歌词和队列",
                systemImage: "music.note",
                tint: .green
            ) {
                router.navigate(to: .feature(.musicPlayer))
            }
            HomeActionRow(
                title: "广场",
                subtitle: "浏览收藏夹广场和 AI 绘画广场",
                systemImage: "rectangle.stack",
                tint: .blue
            ) {
                router.navigate(to: .squareHub)
            }
        }
    }

    @ViewBuilder
    private var accountStatusSection: some View {
        Section("账户状态") {
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
                    title: "今日图片调用",
                    value: snapshot.usage.map { String($0.todayCalls) } ?? "-",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }
        }
    }

    @ViewBuilder
    private var usageLogsSection: some View {
        Section("最近积分调用") {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载积分记录")
            case .failed:
                EmptyView()
            case .loaded(let snapshot):
                if let logs = snapshot.usageLogs?.list, !logs.isEmpty {
                    ForEach(logs.prefix(5)) { log in
                        UsageLogRow(log: log)
                    }
                    if let total = snapshot.usageLogs?.total {
                        usageLogControls(total: total)
                    }
                } else {
                    ContentUnavailableView("暂无积分调用记录", systemImage: "clock.arrow.circlepath")
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
                Text("图片接口调用")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(statusText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(statusColor)
            }
            HStack(spacing: 12) {
                Label(log.timestamp, systemImage: "clock")
                Label(statusText, systemImage: statusSystemImage)
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

    private var statusText: String {
        (200..<400).contains(log.status) ? "成功" : "失败"
    }

    private var statusSystemImage: String {
        (200..<400).contains(log.status) ? "checkmark.circle" : "exclamationmark.triangle"
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

private struct HomeActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
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
