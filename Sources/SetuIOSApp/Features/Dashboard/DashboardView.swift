import SetuIOSCore
import SwiftUI

struct DashboardView: View {
    @Bindable var environment: AppEnvironment
    @Environment(RouterPath.self) private var router
    @State private var state: LoadState<HomeDashboardSnapshot> = .idle
    @State private var usageLogPage = 1
    private let usageLogPageSize = 10

    var body: some View {
        List {
            Section {
                SetuCard(padding: SetuSpacing.xl) {
                    HStack(alignment: .top, spacing: SetuSpacing.lg) {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            Text(greetingTitle)
                                .font(SetuTypography.display)
                                .foregroundStyle(SetuColor.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                            Text("创作、刷图、听歌和发现公开内容都从这里开始。")
                                .foregroundStyle(SetuColor.textSecondary)
                                .font(SetuTypography.caption)
                        }

                        Spacer(minLength: SetuSpacing.sm)

                        HomeAccountAvatar(user: environment.authSession.currentUser)
                    }

                    if let user = environment.authSession.currentUser {
                        SetuPill(text: user.role == .admin ? "管理员" : "已登录", systemImage: "person.crop.circle.fill", tone: .brand)
                            .padding(.top, SetuSpacing.md)
                    }
                }
            }
            .setuListRow()

            primaryActionsSection
            accountStatusSection

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "继续使用")
                        SetuNavigationRow(title: "图片参数与批量获取", subtitle: "管理刷图参数、批量调用和积分消耗", systemImage: "slider.horizontal.3") {
                            router.navigate(to: .points)
                        }
                        SetuNavigationRow(title: "积分流水", subtitle: "查看积分获得与消耗记录", systemImage: "list.bullet.rectangle") {
                            router.navigate(to: .pointsLogs)
                        }
                        SetuNavigationRow(title: "通知中心", subtitle: "查看系统通知和待处理消息", systemImage: "bell") {
                            router.navigate(to: .notifications)
                        }
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "我的内容")
                        SetuNavigationRow(title: "AI 绘画历史", subtitle: "查看任务状态、结果图和复用参数", systemImage: "clock") {
                            router.navigate(to: .aiHistory)
                        }
                        SetuNavigationRow(title: "图库投稿", subtitle: "上传图片并跟踪投稿批次", systemImage: "square.and.arrow.up") {
                            router.navigate(to: .galleryUploads)
                        }
                        SetuNavigationRow(title: "我的收藏夹", subtitle: "整理自己的图片集合", systemImage: "heart.rectangle") {
                            router.navigate(to: .collections)
                        }
                        SetuNavigationRow(title: "我的收藏", subtitle: "查看默认收藏图片", systemImage: "heart.fill") {
                            router.navigate(to: .favorites)
                        }
                        SetuNavigationRow(title: "我的歌单", subtitle: "管理音乐歌单和收藏曲目", systemImage: "music.note.list") {
                            router.navigate(to: .playlists)
                        }
                    }
                }
            }
            .setuListRow()

            usageLogsSection
        }
        .listStyle(.plain)
        .setuBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.navigate(to: .account)
                } label: {
                    HomeAccountAvatar(user: environment.authSession.currentUser)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我的")
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private var primaryActionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "主要功能")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SetuSpacing.md) {
                    HomeActionTile(title: "AI 绘画", subtitle: "创建新作品", systemImage: "sparkles") {
                        router.navigate(to: .aiDraw)
                    }
                    HomeActionTile(title: "随机图片", subtitle: "刷图式浏览", systemImage: "photo.on.rectangle") {
                        router.navigate(to: .imageSwipe)
                    }
                    HomeActionTile(title: "音乐", subtitle: "搜索和播放", systemImage: "music.note") {
                        router.navigate(to: .musicHome)
                    }
                    HomeActionTile(title: "广场", subtitle: "发现公开内容", systemImage: "rectangle.stack") {
                        router.navigate(to: .squareHub)
                    }
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var accountStatusSection: some View {
        Section {
            switch state {
            case .idle, .loading:
                SetuCard {
                    SetuEmptyState(title: "正在加载今日状态", systemImage: "chart.bar", isLoading: true)
                }
            case .failed(let message):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        Label("加载失败", systemImage: "exclamationmark.triangle")
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.danger)
                        Text(message)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                        Button("重试") {
                            Task { await load() }
                        }
                    }
                }
            case .loaded(let snapshot):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "今日状态")
                        HStack(spacing: SetuSpacing.md) {
                            SetuStatTile(title: "积分余额", value: snapshot.points.map { String($0.points) } ?? "-", systemImage: "bolt.circle")
                            SetuStatTile(title: "未读通知", value: snapshot.unreadNotifications.map { String($0) } ?? "-", systemImage: "bell")
                            SetuStatTile(title: "今日刷图", value: snapshot.usage.map { String($0.todayCalls) } ?? "-", systemImage: "photo.on.rectangle")
                        }
                    }
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var usageLogsSection: some View {
        Section {
            switch state {
            case .idle, .loading:
                SetuCard {
                    SetuEmptyState(title: "正在加载刷图记录", systemImage: "clock.arrow.circlepath", isLoading: true)
                }
            case .failed:
                EmptyView()
            case .loaded(let snapshot):
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "最近刷图记录")
                        if let logs = snapshot.usageLogs?.list, !logs.isEmpty {
                            ForEach(logs.prefix(5)) { log in
                                UsageLogRow(log: log)
                            }
                            if let total = snapshot.usageLogs?.total {
                                usageLogControls(total: total)
                            }
                        } else {
                            SetuEmptyState(title: "暂无刷图记录", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
        }
        .setuListRow()
    }

    private func usageLogControls(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("上一页") {
                    Task {
                        usageLogPage = max(1, usageLogPage - 1)
                        await load()
                    }
                }
                .disabled(usageLogPage <= 1)
                .buttonStyle(.bordered)

                Spacer()
                Text("第 \(usageLogPage) / \(max(1, Int(ceil(Double(total) / Double(usageLogPageSize))))) 页")
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
                .buttonStyle(.bordered)
            }
        }
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:
            return "早上好，雪涼云"
        case 11..<14:
            return "中午好，雪涼云"
        case 14..<18:
            return "下午好，雪涼云"
        default:
            return "晚上好，雪涼云"
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
                Text("随机图片")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                SetuPill(text: statusText, systemImage: statusSystemImage, tone: statusTone)
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
        (200..<400).contains(log.status) ? SetuColor.success : SetuColor.danger
    }

    private var statusTone: SetuPillTone {
        (200..<400).contains(log.status) ? .success : .danger
    }

    private var statusText: String {
        (200..<400).contains(log.status) ? "成功" : "失败"
    }

    private var statusSystemImage: String {
        (200..<400).contains(log.status) ? "checkmark.circle" : "exclamationmark.triangle"
    }
}

private struct HomeActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(SetuSpacing.lg)
            .background(SetuColor.heroGradient, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
            .shadow(color: SetuColor.brandPink.opacity(0.16), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeAccountAvatar: View {
    let user: CurrentUser?

    var body: some View {
        Group {
            if let urlString = user?.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(borderColor, lineWidth: 0.5)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private var fallback: some View {
        Circle()
            .fill(backgroundColor)
            .overlay {
                Image(systemName: user?.role == .admin ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    private var borderColor: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #elseif os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color.secondary.opacity(0.25)
        #endif
    }

    private var backgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }
}
