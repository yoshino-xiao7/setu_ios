import Foundation

public enum AppFeatureGroup: String, Codable, CaseIterable, Sendable {
    case account
    case developer
    case content
    case ai
    case music
    case system
    case admin

    public var title: String {
        switch self {
        case .account: "账号"
        case .developer: "开发者"
        case .content: "内容"
        case .ai: "AI"
        case .music: "音乐"
        case .system: "系统"
        case .admin: "管理"
        }
    }
}

public enum AppFeatureID: String, Codable, CaseIterable, Sendable {
    case dashboard
    case apiKeys
    case profile
    case qqBinding
    case docs
    case systemStatus
    case points
    case pointsLogs
    case collections
    case collectionSquare
    case galleryUpload
    case aiDraw
    case aiAssets
    case aiHistory
    case aiSquare
    case musicPlayer
    case playlists
    case musicHistory
    case notifications
    case about
    case privacy
    case deleteRequests
    case adminOverview
    case adminUsers
    case adminBlacklist
    case adminMusicTokens
    case adminImageDeleteRequests
    case adminPixivCrawl
    case adminImageAudit
    case adminGallerySubmissions
    case adminAiGenerations
    case adminAiWorkers
    case adminAiReviews
    case adminAiDeleteRequests
    case adminOperationLogs
}

public struct AppFeature: Identifiable, Hashable, Sendable {
    public let id: AppFeatureID
    public let group: AppFeatureGroup
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let webRoute: String

    public init(
        id: AppFeatureID,
        group: AppFeatureGroup,
        title: String,
        subtitle: String,
        systemImage: String,
        webRoute: String
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.webRoute = webRoute
    }
}

public enum AppFeatureCatalog {
    public static let all: [AppFeature] = [
        AppFeature(id: .dashboard, group: .system, title: "仪表盘", subtitle: "调用概览、积分、通知和服务状态", systemImage: "gauge", webRoute: "/dashboard"),
        AppFeature(id: .apiKeys, group: .developer, title: "API Keys", subtitle: "创建、启停、重命名和删除调用密钥", systemImage: "key", webRoute: "/dashboard/api-keys"),
        AppFeature(id: .profile, group: .account, title: "个人中心", subtitle: "资料、头像、昵称和密码", systemImage: "person.crop.circle", webRoute: "/dashboard/profile"),
        AppFeature(id: .qqBinding, group: .account, title: "QQ 绑定", subtitle: "绑定 QQ 邮箱通知身份", systemImage: "link", webRoute: "/dashboard/qq-binding"),
        AppFeature(id: .docs, group: .developer, title: "开发文档", subtitle: "图片 API 与音乐 API 接入指南", systemImage: "doc.text", webRoute: "/dashboard/docs"),
        AppFeature(id: .systemStatus, group: .system, title: "系统状态", subtitle: "服务可用性、延迟和健康检查", systemImage: "waveform.path.ecg", webRoute: "/dashboard/status"),
        AppFeature(id: .points, group: .developer, title: "积分调用", subtitle: "查看余额并执行积分调用", systemImage: "bolt.circle", webRoute: "/dashboard/points"),
        AppFeature(id: .pointsLogs, group: .developer, title: "积分流水", subtitle: "积分变动、业务类型和调用记录", systemImage: "list.bullet.rectangle", webRoute: "/dashboard/points-logs"),
        AppFeature(id: .collections, group: .content, title: "我的收藏夹", subtitle: "收藏夹管理、分享和封面设置", systemImage: "heart", webRoute: "/dashboard/collections"),
        AppFeature(id: .collectionSquare, group: .content, title: "收藏夹广场", subtitle: "公开收藏夹发现、点赞和收藏", systemImage: "globe.asia.australia", webRoute: "/dashboard/square"),
        AppFeature(id: .galleryUpload, group: .content, title: "图库投稿", subtitle: "批次直传、状态恢复和提交审核", systemImage: "square.and.arrow.up", webRoute: "/dashboard/gallery-upload"),
        AppFeature(id: .aiDraw, group: .ai, title: "AI 绘图", subtitle: "创建生成任务、翻译提示词和查看进度", systemImage: "sparkles", webRoute: "/dashboard/ai-draw"),
        AppFeature(id: .aiAssets, group: .ai, title: "AI 资产选择", subtitle: "选择角色、参考图和生成资产", systemImage: "photo.stack", webRoute: "/dashboard/ai-assets"),
        AppFeature(id: .aiHistory, group: .ai, title: "AI 绘图历史", subtitle: "生成记录、下载、公开审核和删除申请", systemImage: "clock", webRoute: "/dashboard/ai-history"),
        AppFeature(id: .aiSquare, group: .ai, title: "AI 广场", subtitle: "浏览公开 AI 作品", systemImage: "photo.on.rectangle", webRoute: "/dashboard/ai-square"),
        AppFeature(id: .musicPlayer, group: .music, title: "音乐播放器", subtitle: "搜索、播放、歌词和后台播放基础", systemImage: "music.note", webRoute: "/dashboard/music"),
        AppFeature(id: .playlists, group: .music, title: "我的歌单", subtitle: "歌单、歌曲和歌单详情", systemImage: "music.note.list", webRoute: "/dashboard/my-playlists"),
        AppFeature(id: .musicHistory, group: .music, title: "播放历史", subtitle: "最近播放记录", systemImage: "clock.arrow.circlepath", webRoute: "/dashboard/music-history"),
        AppFeature(id: .notifications, group: .system, title: "通知中心", subtitle: "系统、审核和 AI 完成通知", systemImage: "bell", webRoute: "/dashboard/notifications"),
        AppFeature(id: .about, group: .account, title: "关于本站", subtitle: "站点定位、看板娘和快捷入口", systemImage: "info.circle", webRoute: "/dashboard/about"),
        AppFeature(id: .privacy, group: .account, title: "隐私政策", subtitle: "用户隐私和数据使用说明", systemImage: "hand.raised", webRoute: "/dashboard/privacy"),
        AppFeature(id: .deleteRequests, group: .content, title: "我的删除申请", subtitle: "图片删除申请记录和详情", systemImage: "trash", webRoute: "/dashboard/my-delete-requests"),
        AppFeature(id: .adminOverview, group: .admin, title: "后台概览", subtitle: "管理端统计和运营入口", systemImage: "chart.bar", webRoute: "/admin/overview"),
        AppFeature(id: .adminUsers, group: .admin, title: "用户管理", subtitle: "用户列表、封禁、积分发放", systemImage: "person.2", webRoute: "/admin/users"),
        AppFeature(id: .adminBlacklist, group: .admin, title: "黑名单", subtitle: "IP 黑名单和临时封禁", systemImage: "nosign", webRoute: "/admin/blacklist"),
        AppFeature(id: .adminMusicTokens, group: .admin, title: "网易云 Token 管理", subtitle: "音乐代理 Cookie 状态维护", systemImage: "music.mic", webRoute: "/admin/music-tokens"),
        AppFeature(id: .adminImageDeleteRequests, group: .admin, title: "图片删除申请", subtitle: "审核用户图片删除申请", systemImage: "trash.square", webRoute: "/admin/image-delete-requests"),
        AppFeature(id: .adminPixivCrawl, group: .admin, title: "新增图片", subtitle: "Pixiv 爬虫和入库管理", systemImage: "plus.square.on.square", webRoute: "/admin/pixiv-crawl"),
        AppFeature(id: .adminImageAudit, group: .admin, title: "图片库管理", subtitle: "图片审核、可用性和批量提交", systemImage: "photo.badge.checkmark", webRoute: "/admin/image-audit"),
        AppFeature(id: .adminGallerySubmissions, group: .admin, title: "投稿审核", subtitle: "图库投稿批次审核", systemImage: "tray.full", webRoute: "/admin/gallery-submissions"),
        AppFeature(id: .adminAiGenerations, group: .admin, title: "AI 生成记录", subtitle: "管理 AI 生成任务和作品", systemImage: "sparkles.rectangle.stack", webRoute: "/admin/ai-generations"),
        AppFeature(id: .adminAiWorkers, group: .admin, title: "AI Worker 状态", subtitle: "Worker 在线状态和控制", systemImage: "cpu", webRoute: "/admin/ai-workers"),
        AppFeature(id: .adminAiReviews, group: .admin, title: "AI 审核队列", subtitle: "公开作品审核", systemImage: "checklist", webRoute: "/admin/ai-reviews"),
        AppFeature(id: .adminAiDeleteRequests, group: .admin, title: "AI 删除申请", subtitle: "AI 作品删除申请审核", systemImage: "xmark.bin", webRoute: "/admin/ai-delete-requests"),
        AppFeature(id: .adminOperationLogs, group: .admin, title: "操作日志", subtitle: "后台操作审计追踪", systemImage: "doc.text.magnifyingglass", webRoute: "/admin/operation-logs"),
    ]

    public static func features(in group: AppFeatureGroup) -> [AppFeature] {
        all.filter { $0.group == group }
    }

    public static func feature(id: AppFeatureID) -> AppFeature? {
        all.first { $0.id == id }
    }
}
