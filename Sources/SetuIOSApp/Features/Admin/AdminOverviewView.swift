import SetuIOSCore
import SwiftUI

struct AdminOverviewView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AdminOverviewSnapshot> = .idle
    @State private var syncing = false
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "需要管理员权限", message: "请使用管理员账号登录后查看后台概览。", systemImage: "shield.slash")
                    }
                }
                .setuListRow()
            } else {
                headerSection
                if let message {
                    Section {
                        SetuPill(text: message, systemImage: "checkmark.circle", tone: .brand)
                    }
                    .setuListRow()
                }
                content
                adminEntrypoints
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("后台概览")
        .task {
            // Popping a management page starts this task again; retain the loaded snapshot.
            if case .loaded = state { return }
            await load()
        }
        .refreshable { await load() }
    }

    private var headerSection: some View {
        Section {
            SetuCard(padding: SetuSpacing.xl) {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    Text(greeting)
                        .font(SetuTypography.display)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(environment.authSession.currentUser?.nickname ?? environment.authSession.currentUser?.email ?? "Administrator")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    SetuPill(text: "管理后台", systemImage: "shield.lefthalf.filled", tone: .brand)
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            Section {
                SetuCard {
                    SetuEmptyState(title: "正在加载后台概览", systemImage: "chart.bar.xaxis", isLoading: true)
                }
            }
            .setuListRow()
        case .failed(let message):
            Section {
                SetuCard {
                    SetuEmptyState(title: "后台概览加载失败", message: message, systemImage: "chart.bar.xaxis")
                }
            }
            .setuListRow()
        case .loaded(let snapshot):
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "统计")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SetuSpacing.md) {
                            SetuStatTile(title: "图片 API 总调用", value: "\(snapshot.blogStats.totalCalls ?? 0)", systemImage: "chart.line.uptrend.xyaxis")
                            SetuStatTile(title: "用户总数", value: "\(snapshot.userCount)", systemImage: "person.2")
                            SetuStatTile(title: "黑名单 IP", value: "\(snapshot.blockedIpCount)", systemImage: "nosign")
                            SetuStatTile(title: "图库总数", value: "\(snapshot.imageCount)", systemImage: "photo.stack")
                            SetuStatTile(title: "AI 生成总量", value: "\(snapshot.blogStats.aiGenerationTotal ?? 0)", systemImage: "sparkles")
                            SetuStatTile(title: "今日 AI 生成", value: "\(snapshot.blogStats.aiGenerationToday ?? 0)", systemImage: "calendar")
                        }
                        if let updatedAt = snapshot.blogStats.updatedAt {
                            LabeledContent("统计更新时间", value: updatedAt)
                                .font(.footnote)
                                .accessibilityIdentifier("admin-overview-updated-at")
                                .accessibilityValue(updatedAt)
                        }
                    }
                }
            }
            .setuListRow()

            Section {
                SetuPrimaryButton {
                    Task { await syncImageCount() }
                } label: {
                    if syncing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("同步图库统计", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncing || isLoading)
            }
            .setuListRow()
        }
    }

    private var adminEntrypoints: some View {
        Section {
            SetuCard {
                VStack(spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "管理模块")
                    SetuNavigationRow(title: "用户管理", subtitle: "用户资料、权限与状态", systemImage: "person.2") { router.navigate(to: .adminUsers) }
                    SetuNavigationRow(title: "黑名单", subtitle: "管理封禁 IP 与访问控制", systemImage: "nosign") { router.navigate(to: .adminBlacklist) }
                    SetuNavigationRow(title: "系统监控", subtitle: "服务状态与健康检查", systemImage: "waveform.path.ecg.rectangle") { router.navigate(to: .adminSystemStatus) }
                    SetuNavigationRow(title: "网易云 Token 管理", subtitle: "音乐服务凭据状态", systemImage: "music.mic") { router.navigate(to: .adminMusicTokens) }
                    SetuNavigationRow(title: "图片任务", subtitle: "PID 导入、抓取进度与入库结果", systemImage: "photo.badge.plus") { router.navigate(to: .adminPixivCrawl) }
                    SetuNavigationRow(title: "图片审核与详情", subtitle: "图片库、投稿、删除申请", systemImage: "photo.badge.checkmark") { router.navigate(to: .adminImageAudit) }
                    SetuNavigationRow(title: "AI 生成与审核", subtitle: "生成记录、Worker、审核队列", systemImage: "sparkles.rectangle.stack") { router.navigate(to: .adminAiGenerations) }
                    SetuNavigationRow(title: "操作日志", subtitle: "后台行为审计", systemImage: "doc.text.magnifyingglass") { router.navigate(to: .adminOperationLogs) }
                }
            }
        }
        .setuListRow()
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
        guard environment.authSession.currentUser?.role == .admin, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let hasSnapshot: Bool
        if case .loaded = state { hasSnapshot = true } else { hasSnapshot = false }
        if !hasSnapshot { state = .loading }
        message = nil
        do {
            state = .loaded(try await environment.adminClient.overview())
        } catch {
            if Task.isCancelled {
                if !hasSnapshot { state = .idle }
            } else if hasSnapshot {
                message = "统计更新失败：\(error.localizedDescription)"
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func syncImageCount() async {
        guard !syncing, !isLoading else { return }
        syncing = true
        message = nil
        do {
            try await environment.adminClient.syncImageCount()
            await load()
            if message == nil { message = "同步成功，数据已更新" }
        } catch {
            message = error.localizedDescription
        }
        syncing = false
    }
}
