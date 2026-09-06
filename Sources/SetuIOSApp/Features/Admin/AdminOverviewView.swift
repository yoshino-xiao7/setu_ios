import SetuIOSCore
import SwiftUI

struct AdminOverviewView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AdminOverviewSnapshot> = .idle
    @State private var syncing = false
    @State private var message: String?

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                Group {
                    SetuCard {
                        SetuEmptyState(title: "需要管理员权限", message: "请使用管理员账号登录后查看后台概览。", systemImage: "shield.slash")
                    }
                }

            } else {
                headerSection
                if let message {
                    Group {
                        SetuPill(text: message, systemImage: "checkmark.circle", tone: .brand)
                    }

                }
                content
                adminEntrypoints
            }
        }
        .setuBackground()
        .navigationTitle("后台概览")
        .setuActionDock {
            if environment.authSession.currentUser?.role == .admin, case .loaded = state {
                SetuPrimaryButton { Task { await syncImageCount() } } label: {
                    Label(syncing ? "同步中" : "同步图库统计", systemImage: "arrow.triangle.2.circlepath")
                }.disabled(syncing)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var headerSection: some View {
        SetuBentoTile(title: greeting,
            subtitle: environment.authSession.currentUser?.nickname ?? environment.authSession.currentUser?.email ?? "Administrator",
            systemImage: "shield.lefthalf.filled", tone: .brand, status: .init("管理后台"))
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            SetuBento(items: (0..<4).map { AdminOverviewTile(title: "加载指标 \($0)", icon: "chart.bar") }, span: { _ in .small }) { _ in
                SetuSkeleton().frame(height: 100)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在加载后台概览")

        case .failed(let message):
            Group {
                SetuCard {
                    SetuEmptyState(title: "后台概览加载失败", message: message, systemImage: "chart.bar.xaxis")
                }
            }

        case .loaded(let snapshot):
            SetuBento(items: [
                AdminOverviewTile(title: "图片 API 总调用", value: "\(snapshot.blogStats.totalCalls ?? 0)", icon: "chart.line.uptrend.xyaxis"),
                AdminOverviewTile(title: "用户总数", value: "\(snapshot.userCount)", icon: "person.2"),
                AdminOverviewTile(title: "黑名单 IP", value: "\(snapshot.blockedIpCount)", icon: "nosign"),
                AdminOverviewTile(title: "图库总数", value: "\(snapshot.imageCount)", icon: "photo.stack"),
                AdminOverviewTile(title: "AI 生成总量", value: "\(snapshot.blogStats.aiGenerationTotal ?? 0)", icon: "sparkles"),
                AdminOverviewTile(title: "今日 AI 生成", value: "\(snapshot.blogStats.aiGenerationToday ?? 0)", icon: "calendar")
            ], span: { _ in .small }) { tile in
                SetuBentoTile(title: tile.title, value: tile.value, systemImage: tile.icon)
            }
            if let updatedAt = snapshot.blogStats.updatedAt {
                Text("统计更新时间：\(updatedAt)").font(SetuTypography.caption)
            }
        }
    }

    private var adminEntrypoints: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: "管理模块")
            SetuBento(items: [
                AdminOverviewTile(title: "用户管理", subtitle: "用户资料、权限与状态", icon: "person.2", route: .adminUsers),
                AdminOverviewTile(title: "黑名单", subtitle: "管理封禁 IP 与访问控制", icon: "nosign", route: .adminBlacklist),
                AdminOverviewTile(title: "系统监控", subtitle: "服务状态与健康检查", icon: "waveform.path.ecg.rectangle", route: .adminSystemStatus),
                AdminOverviewTile(title: "网易云 Token 管理", subtitle: "音乐服务凭据状态", icon: "music.mic", route: .adminMusicTokens),
                AdminOverviewTile(title: "图片审核与详情", subtitle: "图片库、投稿、删除申请", icon: "photo.badge.checkmark", route: .adminImageAudit),
                AdminOverviewTile(title: "AI 生成与审核", subtitle: "生成记录、Worker、审核队列", icon: "sparkles.rectangle.stack", route: .adminAiGenerations),
                AdminOverviewTile(title: "操作日志", subtitle: "后台行为审计", icon: "doc.text.magnifyingglass", route: .adminOperationLogs)
            ], span: { _ in .small }) { tile in
                SetuBentoTile(title: tile.title, subtitle: tile.subtitle, systemImage: tile.icon) {
                    if let route = tile.route { router.navigate(to: route) }
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6:
            return "夜深了"
        case 6..<11:
            return "早上好"
        case 11..<14:
            return "中午好"
        case 14..<18:
            return "下午好"
        default:
            return "晚上好"
        }
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        message = nil
        do {
            state = .loaded(try await environment.adminClient.overview())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func syncImageCount() async {
        syncing = true
        message = nil
        do {
            try await environment.adminClient.syncImageCount()
            message = "同步成功，数据已更新"
            await load()
        } catch {
            message = error.localizedDescription
        }
        syncing = false
    }
}

private struct AdminOverviewTile: Identifiable {
    let title: String
    var value: String? = nil
    var subtitle: String? = nil
    let icon: String
    var route: AppRoute? = nil
    var id: String { title }
}

/// Shared only by the admin pages; keeps all four states inside the record surface vocabulary.
struct AdminRecordStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    let systemImage: String
    var isLoading = false
    var actionTitle: String?
    var action: (() -> Void)?
    var error: UserFacingError?

    var body: some View {
        SetuRecordCard(headline: title, status: .init(stateTitle, tone: error == nil ? .muted : .danger), density: .compact) {
            if isLoading {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    SetuSkeleton().frame(height: 24)
                    SetuSkeleton().frame(height: 64)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stateTitle)
            } else if let error {
                SetuEmptyState(error: error, retry: action)
            } else {
                SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage,
                               actionTitle: actionTitle, action: action)
            }
        }
    }
}

extension AdminRecordStateSection {
    init(title: String, stateTitle: String, message: UserFacingError, systemImage: String,
         isLoading: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.init(title: title, stateTitle: stateTitle, systemImage: systemImage, isLoading: isLoading,
                  actionTitle: actionTitle, action: action, error: message)
    }
}
