import SetuIOSCore
import SwiftUI

struct AdminOverviewView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AdminOverviewSnapshot> = .idle
    @State private var syncing = false
    @State private var message: String?

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查看后台概览。"))
            } else {
                headerSection
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                content
                adminEntrypoints
            }
        }
        .navigationTitle("后台概览")
        .task { await load() }
        .refreshable { await load() }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.title2.bold())
                Text(environment.authSession.currentUser?.nickname ?? environment.authSession.currentUser?.email ?? "Administrator")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载后台概览")
        case .failed(let message):
            ContentUnavailableView("后台概览加载失败", systemImage: "chart.bar.xaxis", description: Text(message))
        case .loaded(let snapshot):
            Section("统计") {
                AdminMetricRow(title: "图片 API 总调用", value: "\(snapshot.blogStats.totalCalls ?? 0)", systemImage: "chart.line.uptrend.xyaxis")
                AdminMetricRow(title: "用户总数", value: "\(snapshot.userCount)", systemImage: "person.2")
                AdminMetricRow(title: "黑名单 IP", value: "\(snapshot.blockedIpCount)", systemImage: "nosign")
                AdminMetricRow(title: "图库总数", value: "\(snapshot.imageCount)", systemImage: "photo.stack")
                AdminMetricRow(title: "AI 生成总量", value: "\(snapshot.blogStats.aiGenerationTotal ?? 0)", systemImage: "sparkles")
                AdminMetricRow(title: "今日 AI 生成", value: "\(snapshot.blogStats.aiGenerationToday ?? 0)", systemImage: "calendar")
                if let updatedAt = snapshot.blogStats.updatedAt {
                    LabeledContent("统计更新时间", value: updatedAt)
                }
            }

            Section {
                Button {
                    Task { await syncImageCount() }
                } label: {
                    if syncing {
                        ProgressView()
                    } else {
                        Label("同步图库统计", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncing)
            }
        }
    }

    private var adminEntrypoints: some View {
        Section("管理模块") {
            Button {
                router.navigate(to: .adminUsers)
            } label: {
                Label("用户管理", systemImage: "person.2")
            }
            Button {
                router.navigate(to: .adminBlacklist)
            } label: {
                Label("黑名单", systemImage: "nosign")
            }
            Button {
                router.navigate(to: .adminMusicTokens)
            } label: {
                Label("网易云 Token 管理", systemImage: "music.mic")
            }
            Button {
                router.navigate(to: .adminImageDeleteRequests)
            } label: {
                Label("图片删除申请", systemImage: "trash.square")
            }
            Button {
                router.navigate(to: .adminPixivCrawl)
            } label: {
                Label("新增图片", systemImage: "plus.square.on.square")
            }
            Button {
                router.navigate(to: .adminImageAudit)
            } label: {
                Label("图片库管理", systemImage: "photo.badge.checkmark")
            }
            Button {
                router.navigate(to: .adminGallerySubmissions)
            } label: {
                Label("投稿审核", systemImage: "tray.full")
            }
            Button {
                router.navigate(to: .adminAiGenerations)
            } label: {
                Label("AI 生成记录", systemImage: "sparkles.rectangle.stack")
            }
            Button {
                router.navigate(to: .adminAiWorkers)
            } label: {
                Label("AI Worker 状态", systemImage: "cpu")
            }
            Button {
                router.navigate(to: .adminAiReviews)
            } label: {
                Label("AI 审核队列", systemImage: "checklist")
            }
            Button {
                router.navigate(to: .adminAiDeleteRequests)
            } label: {
                Label("AI 删除申请", systemImage: "xmark.bin")
            }
            Button {
                router.navigate(to: .adminOperationLogs)
            } label: {
                Label("操作日志", systemImage: "doc.text.magnifyingglass")
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

private struct AdminMetricRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.pink)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
        }
    }
}
