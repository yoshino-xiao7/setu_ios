import SetuIOSCore
import SwiftUI

enum StaticInfoKind {
    case docs
    case about
    case privacy

    var title: String {
        switch self {
        case .docs:
            "开发文档"
        case .about:
            "关于本站"
        case .privacy:
            "隐私政策"
        }
    }

    var systemImage: String {
        switch self {
        case .docs:
            "doc.text"
        case .about:
            "info.circle"
        case .privacy:
            "hand.raised"
        }
    }

    var subtitle: String {
        switch self {
        case .docs:
            "图片与音乐 API 接入指南。"
        case .about:
            "雪涼云的定位、角色和常用入口。"
        case .privacy:
            "隐私政策、版权声明和服务条款。"
        }
    }
}

struct StaticInfoView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var environment: AppEnvironment
    let kind: StaticInfoKind
    @State private var dailyState: LoadState<SetuImageItem> = .idle
    @State private var dailyMessage: String?
    @State private var dailyFavorited = false
    @State private var dailyActionLoading = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: kind.systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.pink)
                    Text(kind.title)
                        .font(.title.bold())
                    Text(kind.subtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            switch kind {
            case .docs:
                docsContent
                dailyExampleContent
            case .about:
                aboutContent
            case .privacy:
                privacyContent
            }
        }
        .navigationTitle(kind.title)
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
        Section("图片 API") {
            InfoParagraph("`/setu/v2` 用于图片检索和随机调用，支持 R18 模式、数量、关键词、标签、图片尺寸和排除 AI 图片。")
            InfoPair(title: "基础端点", value: "GET /setu/v2")
            InfoPair(title: "常用参数", value: "r18, num, keyword, tag, size, excludeAI")
            InfoParagraph("返回字段包含 PID、页码、作者、标题、尺寸、标签和多尺寸图片链接。iOS 的积分调用页已经接入这一接口。")
        }

        Section("音乐 API") {
            InfoParagraph("音乐能力用于搜索、热门关键词、歌单、播放历史、播放链接和原生播放。当前 iOS 已完成搜索、热门搜索、歌单、播放历史和后台播放第一版。")
            InfoPair(title: "搜索", value: "按歌曲、歌手或专辑关键词检索。")
            InfoPair(title: "歌单", value: "支持创建、删除、详情、添加和移除歌曲。")
            InfoPair(title: "播放", value: "支持获取播放 URL、歌词、AVPlayer 播放、锁屏信息和远程播放暂停。")
        }

        Section("认证与积分") {
            InfoParagraph("浏览器和 iOS 均沿用 `SID` Cookie + `signSecret` 的 HMAC 签名模型。API Key 主要服务程序化图片和音乐 API 调用。")
            InfoPair(title: "积分", value: "每日登录可获取积分，调用 `/setu/v2` 会消耗积分。")
            InfoPair(title: "密钥", value: "在 API Keys 页面创建、启停、重命名和删除。")
        }
    }

    @ViewBuilder
    private var dailyExampleContent: some View {
        Section("每日示例图") {
            switch dailyState {
            case .idle, .loading:
                ProgressView("正在加载示例图")
            case .failed(let message):
                ContentUnavailableView("示例图加载失败", systemImage: "photo.badge.exclamationmark", description: Text(message))
            case .loaded(let item):
                DailySetuExampleCard(
                    item: item,
                    isFavorited: dailyFavorited,
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
            }

            if let dailyMessage {
                Text(dailyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var aboutContent: some View {
        Section("SETU CLOUD") {
            InfoParagraph("雪涼云是一个给开发者、bot 和收藏夹准备的轻量 API 控制台，把图片 API、音乐能力、收藏整理和使用统计放在同一个面板里。")
            InfoPair(title: "定位", value: "接口文档、调用控制台、内容收藏和使用统计。")
            InfoPair(title: "用途", value: "学习、研究、个人娱乐和 bot 接入。")
        }

        Section("看板娘") {
            InfoPair(title: "雪涼 / Yuki Ryou", value: "负责前端体验、界面提示和 bot 交互，让页面看得舒服、点得顺手。")
            InfoPair(title: "鈴木 玲奈 / Suzuki Rena", value: "负责后端系统、接口、数据和权限，让服务稳定运行。")
        }

        Section("快捷入口") {
            InfoPair(title: "API Key 管理", value: "创建和管理你的 API Key。")
            InfoPair(title: "我的收藏", value: "管理收藏夹和图片。")
            InfoPair(title: "收藏夹广场", value: "发现其他用户公开收藏。")
            InfoPair(title: "开发文档", value: "查看图片与音乐 API 使用指南。")
        }
    }

    @ViewBuilder
    private var privacyContent: some View {
        Section("服务说明") {
            InfoParagraph("雪涼云提供图片 API、音乐播放、个人收藏管理和 API Key 管理。本服务仅供学习、研究和个人娱乐使用。")
        }

        Section("版权声明") {
            InfoPair(title: "图片内容", value: "图片内容来源于 Pixiv，版权归原作者所有，平台仅提供检索服务。")
            InfoPair(title: "音乐内容", value: "音乐播放功能基于网易云音乐 API，版权归网易云音乐及原版权方所有。")
            InfoPair(title: "平台内容", value: "前端代码、UI 设计和业务逻辑等归平台所有。")
        }

        Section("个人数据") {
            InfoParagraph("平台会处理账户信息、API 使用数据、积分记录、收藏数据、音乐数据和必要技术日志，用于身份验证、配额管理、防滥用和服务维护。")
            InfoPair(title: "安全措施", value: "密码加密存储、API Key 不可逆加密、HTTPS 传输、访问日志保留。")
            InfoPair(title: "用户权利", value: "查看、修改、删除个人信息，导出数据，注销账户，撤回同意。")
        }

        Section("API 使用限制") {
            InfoParagraph("禁止恶意刷接口、批量注册、绕过限制、商业化使用、传播违规内容、攻击服务或泄露 API Key。违规时可能限制账户、封禁 Key 或加入黑名单。")
        }

        Section("免责与变更") {
            InfoParagraph("服务按现状提供，可能因维护、升级或第三方服务故障中断。重大服务或条款变更会通过站内公告或邮件通知。")
            InfoPair(title: "最后更新", value: "2025年12月28日")
        }
    }

    private func loadDailyExample() async {
        dailyState = .loading
        dailyMessage = nil
        do {
            guard let item = try await environment.publicBlogClient.dailySetu() else {
                dailyState = .failed("公共示例接口暂未返回图片")
                return
            }
            dailyState = .loaded(item)
            dailyFavorited = (try? await environment.favoriteClient.exists(pid: item.pid, p: item.page)) == true
        } catch {
            dailyState = .failed(error.localizedDescription)
        }
    }

    private func toggleFavorite(_ item: SetuImageItem) async {
        dailyActionLoading = true
        defer { dailyActionLoading = false }

        do {
            if dailyFavorited {
                try await environment.favoriteClient.remove(pid: item.pid, p: item.page)
                dailyFavorited = false
                dailyMessage = "已取消收藏"
            } else {
                try await environment.favoriteClient.add(pid: item.pid, p: item.page)
                dailyFavorited = true
                dailyMessage = "已加入默认收藏夹"
            }
        } catch {
            dailyMessage = error.localizedDescription
        }
    }

    private func openSignedDownload(for item: SetuImageItem) async {
        guard let url = item.originalURLString ?? item.previewURLString else {
            dailyMessage = "这张图片没有可下载链接"
            return
        }

        dailyActionLoading = true
        defer { dailyActionLoading = false }

        do {
            let signed = try await environment.downloadClient.sign(url: url, filename: "\(item.pid)_p\(item.page).\(item.ext ?? "jpg")")
            if let downloadURL = URL(string: signed.downloadUrl) {
                openURL(downloadURL)
                dailyMessage = "已打开下载链接"
            } else {
                dailyMessage = "下载链接无效"
            }
        } catch {
            dailyMessage = error.localizedDescription
        }
    }

    private func openOriginal(_ item: SetuImageItem) {
        guard let urlString = item.originalURLString ?? item.previewURLString, let url = URL(string: urlString) else {
            dailyMessage = "这张图片没有可打开链接"
            return
        }
        openURL(url)
        dailyMessage = "已打开原图"
    }
}

private struct DailySetuExampleCard: View {
    let item: SetuImageItem
    let isFavorited: Bool
    let isActionLoading: Bool
    let onFavorite: () -> Void
    let onDownload: () -> Void
    let onOpenOriginal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: item.previewURLString.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Rectangle()
                            .fill(.quaternary)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ContentUnavailableView("图片加载失败", systemImage: "photo")
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.page)", systemImage: "number")
                    Label("\(item.width)x\(item.height)", systemImage: "rectangle")
                    if item.r18 == 1 {
                        Text("R18")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(action: onFavorite) {
                    Label(isFavorited ? "取消收藏" : "收藏", systemImage: isFavorited ? "heart.fill" : "heart")
                }
                .disabled(isActionLoading)

                Button(action: onDownload) {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .disabled(isActionLoading)

                Button(action: onOpenOriginal) {
                    Label("原图", systemImage: "arrow.up.forward.square")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
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
            .foregroundStyle(.secondary)
    }
}

private struct InfoPair: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
