import SetuIOSCore
import SwiftUI

struct PointsLogsView: View {
    @Bindable var environment: AppEnvironment
    @State private var items: [PointsLogItem] = []
    @State private var total = 0
    @State private var nextPage = 1
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    private let pageSize = 10

    var body: some View {
        List {
            if isInitialLoading {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "list.bullet.rectangle", isLoading: true)
                    }
                }
            } else if items.isEmpty, let loadError {
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "积分明细加载失败",
                            message: loadError,
                            systemImage: "wifi.exclamationmark",
                            actionTitle: "重试",
                            action: { Task { await loadFirstPage() } }
                        )
                    }
                }
            } else if items.isEmpty {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "暂无积分明细", message: "积分获得和消耗记录会显示在这里。", systemImage: "list.bullet.rectangle")
                    }
                }
            } else {
                Section {
                    SetuCard {
                        SetuSectionHeader(title: "积分明细", subtitle: "共 \(total) 条")
                    }
                }
                Section {
                    ForEach(items) { item in
                        SetuCard {
                            PointsLogRow(item: item)
                        }
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                Section {
                    SetuLoadMoreFooter(state: loadMoreFooterState) {
                        Task { await loadMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle("积分明细")
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    private var hasMore: Bool { items.count < total }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !hasMore { return .complete("已加载全部 \(total) 条明细") }
        return .idle
    }

    private func loadFirstPage() async {
        isInitialLoading = items.isEmpty
        loadError = nil
        do {
            let result = try await environment.pointsClient.logs(page: 1, size: pageSize)
            items = result.items
            total = result.total
            nextPage = 2
        } catch {
            loadError = UserFacingErrorMapper.map(error).message
        }
        isInitialLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        let requestedPage = nextPage
        isLoadingMore = true
        loadError = nil
        defer { isLoadingMore = false }
        do {
            let result = try await environment.pointsClient.logs(page: requestedPage, size: pageSize)
            guard requestedPage == nextPage else { return }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: result.items.filter { !existingIDs.contains($0.id) })
            total = result.total
            nextPage += 1
        } catch {
            loadError = UserFacingErrorMapper.map(error).message
        }
    }
}

private struct PointsLogRow: View {
    let item: PointsLogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayTitle)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                Spacer()
                Text(deltaText)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(deltaColor)
            }
            if let createdAt = item.createdAt {
                Label(SetuDateFormatter.string(from: createdAt), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            Text(displayDescription)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    private var displayTitle: String {
        switch item.bizType {
        case "DAILY_LOGIN":
            return "每日登录奖励"
        case "SETU_CALL":
            return "获取图片"
        case "AI_GENERATION":
            return "AI 绘画消耗"
        case "ADMIN_CALL":
            return "管理员免费获取"
        case "REFUND":
            return "积分返还"
        default:
            return item.delta >= 0 ? "积分获得" : "积分消耗"
        }
    }

    private var displayDescription: String {
        switch item.bizType {
        case "DAILY_LOGIN":
            return "登录后获得的可用积分。"
        case "SETU_CALL":
            return "用于查看随机高清图或按条件获取图片。"
        case "AI_GENERATION":
            return "用于生成 AI 绘画作品。"
        case "ADMIN_CALL":
            return "管理员权限下免费获取图片。"
        case "REFUND":
            return "作品生成失败或取消后返还的积分。"
        default:
            return item.delta >= 0 ? "系统记录的一笔积分增加。" : "系统记录的一笔积分扣减。"
        }
    }

    private var deltaText: String {
        if item.bizType == "ADMIN_CALL" || item.delta == 0 {
            return "∞"
        }
        return item.delta >= 0 ? "+\(item.delta)" : "\(item.delta)"
    }

    private var deltaColor: Color {
        if item.bizType == "ADMIN_CALL" || item.delta == 0 {
            return SetuColor.warning
        }
        return item.delta >= 0 ? SetuColor.success : SetuColor.danger
    }
}
