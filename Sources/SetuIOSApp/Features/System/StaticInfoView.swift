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
            "手机端常用功能与使用说明。"
        case .about:
            "雪涼云的定位、角色和 App 入口。"
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
        Section("图片") {
            InfoParagraph("图片页面向日常浏览设计，可以查看当前积分、单次消耗和刷图参数。进入刷图后，通过上下左右滑动继续获取新图片。")
            InfoPair(title: "积分调用", value: "设置 R18、数量、关键词、标签、尺寸和排除 AI 图片等参数。")
            InfoPair(title: "积分流水", value: "查看积分获得与消耗记录。")
            InfoPair(title: "图库投稿", value: "提交图片到图库并查看投稿状态。")
        }

        Section("音乐") {
            InfoParagraph("音乐页提供搜索、热门推荐、歌单、播放历史和原生播放。播放后可以从底部迷你播放器继续控制，进入歌词页查看当前队列。")
            InfoPair(title: "搜索", value: "按歌曲、歌手或专辑关键词检索。")
            InfoPair(title: "歌单", value: "支持创建、删除、详情、添加和移除歌曲。")
            InfoPair(title: "播放", value: "支持后台播放、锁屏信息、远程播放暂停和歌词查看。")
        }

        Section("AI 绘画与账号") {
            InfoParagraph("AI 绘画页可以输入提示词、选择画布比例和生成参数，并在历史记录中查看作品、申请删除或进入广场浏览公开作品。")
            InfoPair(title: "我的", value: "管理个人资料、QQ 绑定、修改密码、通行密钥、隐私政策和关于本站。")
            InfoPair(title: "管理员模式", value: "仅管理员账号会显示入口，普通用户不会看到后台管理功能。")
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
            InfoParagraph("雪涼云是一个围绕图片浏览、AI 绘画、音乐播放和公开广场展开的个人内容 App。")
            InfoPair(title: "定位", value: "图片、AI 创作、音乐、收藏整理和个人账户管理。")
            InfoPair(title: "用途", value: "学习、研究、个人娱乐和内容收藏。")
        }

        Section("看板娘") {
            InfoPair(title: "雪涼 / Yuki Ryou", value: "负责前端体验、界面提示和 bot 交互，让页面看得舒服、点得顺手。")
            InfoPair(title: "鈴木 玲奈 / Suzuki Rena", value: "负责后端系统、接口、数据和权限，让服务稳定运行。")
        }

        Section("快捷入口") {
            InfoPair(title: "AI 绘画", value: "生成作品、查看历史和管理删除申请。")
            InfoPair(title: "图片", value: "刷随机图片、查看积分流水、投稿图库。")
            InfoPair(title: "音乐", value: "搜索歌曲、播放歌单、查看播放历史。")
            InfoPair(title: "广场", value: "发现公开收藏夹和 AI 绘画作品。")
        }
    }

    @ViewBuilder
    private var privacyContent: some View {
        Section("服务说明") {
            InfoParagraph("雪涼云提供图片浏览、AI 绘画、音乐播放、个人收藏管理和公开广场。本服务仅供学习、研究和个人娱乐使用。")
        }

        Section("版权声明") {
            InfoPair(title: "图片内容", value: "图片内容来源于 Pixiv，版权归原作者所有，平台仅提供检索服务。")
            InfoPair(title: "音乐内容", value: "音乐播放功能基于网易云音乐 API，版权归网易云音乐及原版权方所有。")
            InfoPair(title: "平台内容", value: "前端代码、UI 设计和业务逻辑等归平台所有。")
        }

        Section("个人数据") {
            InfoParagraph("平台会处理账户信息、图片与 AI 使用数据、积分记录、收藏数据、音乐数据和必要技术日志，用于身份验证、配额管理、防滥用和服务维护。")
            InfoPair(title: "安全措施", value: "密码加密存储、HTTPS 传输、访问日志保留和必要的权限校验。")
            InfoPair(title: "用户权利", value: "查看、修改、删除个人信息，导出数据，注销账户，撤回同意。")
        }

        Section("使用限制") {
            InfoParagraph("禁止恶意刷图、批量注册、绕过限制、商业化使用、传播违规内容或攻击服务。违规时可能限制账户或加入黑名单。")
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
