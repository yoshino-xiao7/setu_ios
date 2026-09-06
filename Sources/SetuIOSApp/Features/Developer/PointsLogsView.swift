import SetuIOSCore
import SwiftUI

struct PointsLogsView: View {
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<PointsLogItem>(pageSize: 10)

    var body: some View {
        SetuBoard {
            if pager.phase == .loadingInitial {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "list.bullet.rectangle", isLoading: true)
                    }
                }
            } else if pager.items.isEmpty, let loadError = pager.loadMoreError ?? pager.initialError {
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
            } else if pager.items.isEmpty {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "暂无积分明细", message: "积分获得和消耗记录会显示在这里。", systemImage: "list.bullet.rectangle")
                    }
                }
            } else {
                Section {
                    SetuCard {
                        SetuSectionHeader(title: "积分明细", subtitle: "共 \(pager.total) 条")
                    }
                }
                Section {
                    SetuRecordBoard(items: pager.items) { item in
                        PointsLogRow(item: item)
                            .onAppear {
                                if item.id == pager.items.last?.id {
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

        .setuBackground()
        .navigationTitle("积分明细")
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    private var hasMore: Bool { pager.hasMore }

    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if pager.phase == .loadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !pager.hasMore { return .complete("已加载全部 \(pager.total) 条明细") }
        return .idle
    }

    private func loadFirstPage() async {
        await pager.loadFirstPage(
            { [environment] page in
                let result = try await environment.pointsClient.logs(page: page, size: 10)
                return .init(items: result.items, total: result.total)
            },
            onError: { UserFacingErrorMapper.map($0).message })
    }

    private func loadMore() async {
        await pager.loadMore(
            { [environment] page in
                let result = try await environment.pointsClient.logs(page: page, size: 10)
                return .init(items: result.items, total: result.total)
            },
            onError: { UserFacingErrorMapper.map($0).message })
    }
}

private struct PointsLogRow: View {
    let item: PointsLogItem

    var body: some View {
        SetuRecordCard(
            headline: displayTitle, supporting: displayDescription,
            status: .init(deltaText, tone: item.delta >= 0 ? .success : .warning),
            fields: [
                .init("积分变动", deltaText),
                .init("时间", item.createdAt.map { SetuDateFormatter.string(from: $0) } ?? "暂无", isNumeric: false),
            ])
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
