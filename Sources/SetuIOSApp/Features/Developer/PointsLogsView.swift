import SetuIOSCore
import SwiftUI

struct PointsLogsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PointsLogPage> = .idle
    @State private var page = 1
    private let pageSize = 10

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "list.bullet.rectangle", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "积分流水加载失败", message: message, systemImage: "exclamationmark.triangle")
                    }
                }
            case .loaded(let page):
                if page.items.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(title: "暂无积分流水", message: "积分获得和消耗记录会显示在这里。", systemImage: "list.bullet.rectangle")
                        }
                    }
                } else {
                    Section {
                        SetuCard {
                            SetuSectionHeader(title: "积分流水", subtitle: "共 \(page.total) 条")
                        }
                    }
                    Section {
                        ForEach(page.items) { item in
                            SetuCard {
                                PointsLogRow(item: item)
                            }
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle("积分流水")
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PointsLogPage) -> some View {
        Section {
            SetuCard {
                HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(result.page * result.size >= result.total)
                }
                .buttonStyle(.bordered)
                .tint(SetuColor.brandPink)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.pointsClient.logs(page: page, size: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
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
                Label(createdAt, systemImage: "clock")
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
            return "图片积分调用"
        case "AI_GENERATION":
            return "AI 绘画消耗"
        case "ADMIN_CALL":
            return "管理员免费调用"
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
            return "用于随机图片查看或图片参数调用。"
        case "AI_GENERATION":
            return "用于提交 AI 绘画任务。"
        case "ADMIN_CALL":
            return "管理员权限下的免费图片调用。"
        case "REFUND":
            return "任务失败或撤销后返还的积分。"
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
