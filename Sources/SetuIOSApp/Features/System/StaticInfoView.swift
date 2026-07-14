import SetuIOSCore
import SwiftUI

enum StaticInfoKind {
    case docs
    case about
    case privacy
    case terms

    var title: String {
        switch self {
        case .docs:
            "使用帮助"
        case .about:
            "关于雪涼云"
        case .privacy:
            "隐私政策"
        case .terms:
            "服务条款"
        }
    }

    var systemImage: String {
        switch self {
        case .docs:
            "questionmark.circle"
        case .about:
            "info.circle"
        case .privacy:
            "hand.raised"
        case .terms:
            "doc.text.magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .docs:
            "手机端常用功能与使用说明。"
        case .about:
            "雪涼云的定位、角色和 App 入口。"
        case .privacy:
            "了解个人数据的使用方式与安全措施。"
        case .terms:
            "了解服务范围、内容版权与使用规则。"
        }
    }
}

struct StaticInfoView: View {
    @Bindable var environment: AppEnvironment
    let kind: StaticInfoKind
    @State private var dailyState: LoadState<SetuImageItem> = .idle
    @State private var dailyFeedback: SetuFeedback?
    @State private var dailyFavoriteState: LoadState<Bool> = .idle
    @State private var dailyActionLoading = false
    @State private var dailyPreview: UserImagePreviewItem?

    var body: some View {
        List {
            SetuCard(padding: SetuSpacing.xl) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: kind.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(SetuColor.brandPink)
                    Text(kind.title)
                        .font(SetuTypography.display)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(kind.subtitle)
                        .font(SetuTypography.body)
                        .foregroundStyle(SetuColor.textSecondary)
                }
            }
            .setuListRow()

            switch kind {
            case .docs:
                docsContent
                dailyExampleContent
            case .about:
                aboutContent
            case .privacy:
                privacyContent
            case .terms:
                termsContent
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .accessibilityIdentifier("static.info.page")
        .navigationTitle(kind.title)
        .sheet(item: $dailyPreview) { item in
            UserImagePreviewSheet(item: item)
        }
        .task(id: kind.title) {
            if case .docs = kind {
                await loadDailyExample()
            }
        }
        .refreshable {
            if case .docs = kind {
                await loadDailyExample()
            }
        }
    }

    @ViewBuilder
    private var docsContent: some View {
        StaticInfoSectionCard(title: "图片") {
            InfoParagraph("图片页面向日常浏览设计，可以查看当前积分、单次消耗和刷图参数。进入刷图后，通过上下左右滑动继续获取新图片。")
            InfoPair(title: "批量找图", value: "设置内容级别、数量、关键词、标签、尺寸和是否排除 AI 图片。")
            InfoPair(title: "积分明细", value: "查看积分获得与消耗记录。")
            InfoPair(title: "图库投稿", value: "提交图片到图库并查看投稿状态。")
        }

        StaticInfoSectionCard(title: "音乐") {
            InfoParagraph("音乐页提供搜索、热门推荐、歌单、播放历史和原生播放。播放后可以从底部迷你播放器继续控制，进入歌词页查看当前队列。")
            InfoPair(title: "搜索", value: "按歌曲、歌手或专辑关键词检索。")
            InfoPair(title: "歌单", value: "支持创建、删除、详情、添加和移除歌曲。")
            InfoPair(title: "播放", value: "支持后台播放、锁屏信息、远程播放暂停和歌词查看。")
        }

        StaticInfoSectionCard(title: "AI 绘画与账号") {
            InfoParagraph("AI 绘画页可以输入提示词、选择画布比例和生成参数，并在历史记录中查看作品、申请删除或进入广场浏览公开作品。")
            InfoPair(title: "我的", value: "管理个人资料、QQ 绑定、修改密码、通行密钥、隐私政策和关于雪涼云。")
            InfoPair(title: "管理员模式", value: "仅管理员账号会显示入口，普通用户不会看到后台管理功能。")
        }
    }

    @ViewBuilder
    private var dailyExampleContent: some View {
        StaticInfoSectionCard(title: "每日示例图") {
            switch dailyState {
            case .idle, .loading:
                SetuEmptyState(title: "正在加载示例图", systemImage: "photo", isLoading: true)
            case .failed(let message):
                SetuEmptyState(title: "示例图加载失败", message: message, systemImage: "photo.badge.exclamationmark")
            case .loaded(let item):
                DailySetuExampleCard(
                    item: item,
                    favoriteState: dailyFavoriteState,
                    isActionLoading: dailyActionLoading,
                    onFavorite: {
                        Task { await toggleFavorite(item) }
                    },
                    onDownload: {
                        Task { await openSignedDownload(for: item) }
                    },
                    onOpenOriginal: {
                        openOriginal(item)
                    }
                )

                if case .failed(let message) = dailyFavoriteState {
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        SetuFeedbackBanner(feedback: .error(message))
                        Button("重试收藏状态") {
                            Task { await loadDailyFavoriteStatus(for: item) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("daily.favorite.retry")
                    }
                    .accessibilityIdentifier("daily.favorite.failed")
                }
            }

            if let dailyFeedback {
                SetuFeedbackBanner(feedback: dailyFeedback)
            }
        }
    }

    @ViewBuilder
    private var aboutContent: some View {
        StaticInfoSectionCard(title: "雪涼云") {
            InfoParagraph("雪涼云是一个围绕图片浏览、AI 绘画、音乐播放和公开广场展开的个人内容 App。")
            InfoPair(title: "定位", value: "图片、AI 创作、音乐、收藏整理和个人账户管理。")
            InfoPair(title: "用途", value: "学习、研究、个人娱乐和内容收藏。")
        }

        StaticInfoSectionCard(title: "看板娘") {
            InfoPair(title: "雪涼 / Yuki Ryou", value: "负责前端体验、界面提示和 bot 交互，让页面看得舒服、点得顺手。")
            InfoPair(title: "鈴木 玲奈 / Suzuki Rena", value: "负责后端系统、数据和权限，让服务稳定运行。")
        }

        StaticInfoSectionCard(title: "快捷入口") {
            InfoPair(title: "AI 绘画", value: "生成作品、查看历史和管理删除申请。")
            InfoPair(title: "图片", value: "刷随机图片、查看积分明细、投稿图库。")
            InfoPair(title: "音乐", value: "搜索歌曲、播放歌单、查看播放历史。")
            InfoPair(title: "广场", value: "发现公开收藏夹和 AI 绘画作品。")
        }
    }

    @ViewBuilder
    private var privacyContent: some View {
        StaticInfoSectionCard(title: "个人数据") {
            InfoParagraph("平台会处理账户信息、图片与 AI 使用数据、积分记录、收藏数据、音乐数据和必要技术日志，用于身份验证、配额管理、防滥用和服务维护。")
            InfoPair(title: "安全措施", value: "密码加密存储、HTTPS 传输、访问日志保留和必要的权限校验。")
            InfoPair(title: "用户权利", value: "查看、修改、删除个人信息，导出数据，注销账户，撤回同意。")
        }

        StaticInfoSectionCard(title: "数据保留与选择") {
            InfoParagraph("只在提供服务、履行安全义务和处理争议所需的期限内保留数据。你可以在账号相关页面修改资料，并通过支持渠道申请导出或删除。")
            InfoPair(title: "权限选择", value: "通知与照片权限会在相关功能需要时说明用途，你可以随时在系统设置中更改。")
            InfoPair(title: "最后更新", value: "2026年7月10日")
        }
    }

    @ViewBuilder
    private var termsContent: some View {
        StaticInfoSectionCard(title: "服务说明") {
            InfoParagraph("雪涼云提供图片浏览、AI 绘画、音乐播放、个人收藏管理和公开广场。本服务仅供学习、研究和个人娱乐使用。")
        }

        StaticInfoSectionCard(title: "版权声明") {
            InfoPair(title: "图片内容", value: "图片内容来源于 Pixiv，版权归原作者所有，平台仅提供检索服务。")
            InfoPair(title: "音乐内容", value: "音乐播放功能基于网易云音乐服务，版权归网易云音乐及原版权方所有。")
            InfoPair(title: "平台内容", value: "前端代码、UI 设计和业务逻辑等归平台所有。")
        }

        StaticInfoSectionCard(title: "使用限制") {
            InfoParagraph("禁止恶意刷图、批量注册、绕过限制、商业化使用、传播违规内容或攻击服务。违规时可能限制账户或加入黑名单。")
        }

        StaticInfoSectionCard(title: "免责与变更") {
            InfoParagraph("服务按现状提供，可能因维护、升级或第三方服务故障中断。重大服务或条款变更会通过站内公告或邮件通知。")
            InfoPair(title: "最后更新", value: "2026年7月10日")
        }
    }

    private func loadDailyExample() async {
        dailyState = .loading
        dailyFavoriteState = .idle
        dailyFeedback = nil
        do {
            guard let item = try await environment.publicBlogClient.dailySetu() else {
                dailyState = .failed("公共示例服务暂未返回图片")
                return
            }
            dailyState = .loaded(item)
            await loadDailyFavoriteStatus(for: item)
        } catch {
            dailyState = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func loadDailyFavoriteStatus(for item: SetuImageItem) async {
        dailyFavoriteState = .loading
        do {
            dailyFavoriteState = .loaded(
                try await environment.favoriteClient.exists(pid: item.pid, p: item.page)
            )
        } catch {
            dailyFavoriteState = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func toggleFavorite(_ item: SetuImageItem) async {
        guard case .loaded(let isFavorited) = dailyFavoriteState else { return }
        dailyActionLoading = true
        defer { dailyActionLoading = false }

        do {
            if isFavorited {
                try await environment.favoriteClient.remove(pid: item.pid, p: item.page)
                dailyFavoriteState = .loaded(false)
                dailyFeedback = .success("已取消收藏")
            } else {
                try await environment.favoriteClient.add(pid: item.pid, p: item.page)
                dailyFavoriteState = .loaded(true)
                dailyFeedback = .success("已加入默认收藏夹")
            }
        } catch {
            dailyFeedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func openSignedDownload(for item: SetuImageItem) async {
        guard item.originalURLString != nil || item.previewURLString != nil else {
            dailyFeedback = .error("这张图片暂时无法下载")
            return
        }
        dailyPreview = UserImagePreviewItem(image: item)
    }

    private func openOriginal(_ item: SetuImageItem) {
        guard item.originalURLString != nil || item.previewURLString != nil else {
            dailyFeedback = .error("这张图片暂时无法打开")
            return
        }
        dailyPreview = UserImagePreviewItem(image: item)
        dailyFeedback = .success("已打开原图")
    }
}

private struct DailySetuExampleCard: View {
    let item: SetuImageItem
    let favoriteState: LoadState<Bool>
    let isActionLoading: Bool
    let onFavorite: () -> Void
    let onDownload: () -> Void
    let onOpenOriginal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuRemoteImage(
                urlString: item.previewURLString,
                accessibilityLabel: "每日图片：\(item.title)，作者 \(item.author)",
                width: nil,
                height: 220,
                cornerRadius: SetuRadius.md,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.author)
                    .font(.subheadline)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 10) {
                    Label("\(item.width)x\(item.height)", systemImage: "rectangle")
                    if item.r18 == 1 {
                        Text("成人内容")
                    }
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textTertiary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: SetuSpacing.sm) {
                    dailyImageActionButtons
                }

                VStack(spacing: SetuSpacing.xs) {
                    dailyImageActionButtons
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    @ViewBuilder
    private var dailyImageActionButtons: some View {
        Button(action: onFavorite) {
            Label(favoriteActionTitle, systemImage: favoriteActionSystemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isActionLoading || !favoriteActionIsAvailable)
        .accessibilityIdentifier("daily.favorite.action")

        Button(action: onDownload) {
            Label("下载", systemImage: "arrow.down.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isActionLoading)

        Button(action: onOpenOriginal) {
            Label("原图", systemImage: "arrow.up.forward.square")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var favoriteActionTitle: String {
        switch favoriteState {
        case .idle, .loading:
            return "正在确认"
        case .failed:
            return "暂不可收藏"
        case .loaded(let isFavorited):
            return isFavorited ? "取消收藏" : "收藏"
        }
    }

    private var favoriteActionSystemImage: String {
        if case .loaded(true) = favoriteState { return "heart.fill" }
        return "heart"
    }

    private var favoriteActionIsAvailable: Bool {
        if case .loaded = favoriteState { return true }
        return false
    }
}

private struct StaticInfoSectionCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                content
            }
        }
        .setuListRow()
    }
}

private struct InfoParagraph: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(.init(text))
            .font(.body)
            .foregroundStyle(SetuColor.textSecondary)
    }
}

private struct InfoPair: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
            Text(value)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
