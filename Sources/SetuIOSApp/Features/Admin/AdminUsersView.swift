import SetuIOSCore
import SwiftUI

struct AdminUsersView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AdminUserListResponse> = .idle
    @State private var email = ""
    @State private var nickname = ""
    @State private var statusFilter: AdminUserStatusFilter = .all
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminUserStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后管理用户。", systemImage: "shield.slash")
            } else {
                filterSection
                content
            }
        }
        .setuBackground()
        .navigationTitle("用户管理")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                TextField("邮箱", text: $email)
                    .textFieldStyle(.roundedBorder)
                TextField("昵称", text: $nickname)
                    .textFieldStyle(.roundedBorder)
                SetuFilterBar(options: AdminUserStatusFilter.allCases.map { .init(value: $0, title: $0.title) }, selection: $statusFilter, accessibilityTitle: "状态")

                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("搜索用户", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandOnLight)
                .foregroundStyle(.white)
            }
        }

    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminUserStateSection(title: "用户列表", stateTitle: "正在加载用户", systemImage: "person.2", isLoading: true)
        case .failed(let message):
            AdminUserStateSection(title: "用户列表", stateTitle: "用户列表加载失败", message: message, systemImage: "person.crop.circle.badge.exclamationmark")
        case .loaded(let result):
            let users = result.list ?? []
            if users.isEmpty {
                AdminUserStateSection(title: "用户列表", stateTitle: "暂无用户", message: "调整筛选条件后再试一次。", systemImage: "person.2.slash")
            } else {
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 位用户", subtitle: "用户管理")
                    SetuRecordBoard(items: users) { user in
                        Button {
                            router.navigate(to: .adminUserDetail(user.id))
                        } label: {
                            AdminUserRow(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }

                pagerSection(result: result)
            }
        }
    }

    private func pagerSection(result: AdminUserListResponse) -> some View {
        SetuCard {
            HStack {
                Button {
                    Task {
                        page = max(1, page - 1)
                        await load(resetPage: false)
                    }
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .disabled(page <= 1)
                Spacer()
                Text("第 \(result.page ?? page) 页")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()
                Button {
                    Task {
                        page += 1
                        await load(resetPage: false)
                    }
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .frame(minHeight: 44)
                }
                .disabled((result.page ?? page) * (result.pageSize ?? pageSize) >= result.total)
            }
        }

    }

    private func load(resetPage: Bool) async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        if resetPage {
            page = 1
        }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.users(
                page: page,
                pageSize: pageSize,
                email: clean(email),
                nickname: clean(nickname),
                status: statusFilter.queryValue
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AdminUserDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let userID: Int
    @State private var state: LoadState<AdminUserDetail> = .idle
    @State private var actionMessage: String?
    @State private var pointsAmount = ""
    @State private var pointsReason = ""
    @State private var isSubmitting = false
    @State private var showingDeleteConfirmation = false

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminUserStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看用户详情。", systemImage: "shield.slash")
            } else {
                if let actionMessage {
                    SetuCard {
                        Label(actionMessage, systemImage: "checkmark.circle")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                content
            }
        }
        .setuBackground()
        .navigationTitle("用户详情")
        .confirmationDialog(pendingActionTitle, isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            Button("确认执行", role: .destructive) {
                let action = pendingAction
                pendingAction = nil
                action?()
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text("此操作将改变当前记录或服务状态，请核对目标后确认。")
        }
        .confirmationDialog("永久删除这个用户？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("确认删除", role: .destructive) {
                Task { await deleteUser() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后该用户账号将无法恢复，请确认已经完成必要备份或风险判断。")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminUserStateSection(title: "用户详情", stateTitle: "正在加载用户详情", systemImage: "person.crop.circle", isLoading: true)
        case .failed(let message):
            AdminUserStateSection(title: "用户详情", stateTitle: "用户详情加载失败", message: message, systemImage: "person.crop.circle.badge.exclamationmark")
        case .loaded(let user):
            summarySection(user)
            actionSection(user)
            pointsSection
            apiKeysSection(user.apiKeys ?? [])
        }
    }

    private func summarySection(_ user: AdminUserDetail) -> some View {
        SetuRecordCard(headline: user.nickname ?? user.email, supporting: user.email,
            status: .init(user.statusTitle, tone: user.status == 0 ? .danger : .success),
            fields: [.init("ID", "\(user.id)"), .init("角色", user.roleTitle),
                     .init("邮箱验证", user.emailVerified == true ? "已验证" : "未验证"),
                     .init("注册 IP", user.registerIp ?? "-"), .init("最后登录 IP", user.lastLoginIp ?? "-"),
                     .init("创建时间", user.createdAt ?? "-"), .init("更新时间", user.updatedAt ?? "-")], density: .compact)
    }

    private func actionSection(_ user: AdminUserDetail) -> some View {
        SetuRecordCard(headline: "账号操作", status: .init("请核对后操作", tone: .danger), density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "账号操作")
            Button(role: user.status == 0 ? nil : .destructive) {
                pendingActionTitle = "确认更改用户封禁状态？"; pendingAction = { Task { await toggleBan(user) } }
            } label: {
                    Label(isSubmitting ? "处理中" : (user.status == 0 ? "解除封禁" : "封禁用户"), systemImage: isSubmitting ? "hourglass" : (user.status == 0 ? "lock.open" : "lock"))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(isSubmitting)

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("永久删除用户", systemImage: "person.crop.circle.badge.xmark")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(isSubmitting)
        }
        }

    }

    private var pointsSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "发放积分")
            TextField("积分数量", text: $pointsAmount)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            TextField("原因", text: $pointsReason)
                    .textFieldStyle(.roundedBorder)
            Button {
                Task { await grantPoints() }
            } label: {
                    Label(isSubmitting ? "发放中" : "发放积分", systemImage: isSubmitting ? "hourglass" : "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandOnLight)
                .foregroundStyle(.white)
            .disabled(isSubmitting || Int(pointsAmount) == nil)
        }
        }

    }

    private func apiKeysSection(_ apiKeys: [AdminUserApiKey]) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: "API Keys")
            if apiKeys.isEmpty { SetuEmptyState(title: "暂无 API Key", systemImage: "key.slash") }
            SetuRecordBoard(items: apiKeys) { key in
                SetuRecordCard(headline: key.name, status: .init(key.statusTitle, tone: key.status == 1 ? .success : .muted),
                    fields: [.init("今日调用", "\(key.callsToday ?? 0)"), .init("总调用", "\(key.totalCalls ?? 0)"),
                             .init("创建时间", key.createdAt ?? "-")], density: .compact)
            }
        }
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.userDetail(id: userID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func toggleBan(_ user: AdminUserDetail) async {
        isSubmitting = true
        actionMessage = nil
        do {
            if user.status == 0 {
                try await environment.adminClient.unbanUser(id: user.id)
                actionMessage = "已解除封禁"
            } else {
                try await environment.adminClient.banUser(id: user.id)
                actionMessage = "已封禁用户"
            }
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func deleteUser() async {
        isSubmitting = true
        actionMessage = nil
        do {
            try await environment.adminClient.deleteUser(id: userID)
            dismiss()
        } catch {
            actionMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func grantPoints() async {
        guard let amount = Int(pointsAmount) else { return }
        isSubmitting = true
        actionMessage = nil
        do {
            let response = try await environment.adminClient.grantPoints(
                userID: userID,
                amount: amount,
                reason: clean(pointsReason)
            )
            actionMessage = "已发放 \(response.grantedPoints) 积分，当前余额 \(response.balance)"
            pointsAmount = ""
            pointsReason = ""
        } catch {
            actionMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AdminUserRow: View {
    let user: AdminUserItem

    var body: some View {
        SetuRecordCard(headline: user.nickname ?? user.email, supporting: user.email,
            status: .init(user.statusTitle, tone: user.status == 0 ? .danger : .success),
            fields: [.init("角色", user.roleTitle), .init("创建时间", user.createdAt ?? "-")], density: .compact)
    }
}

private typealias AdminUserStateSection = AdminRecordStateSection

private enum AdminUserStatusFilter: String, CaseIterable, Identifiable {
    case all
    case normal
    case banned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .normal: "正常"
        case .banned: "已封禁"
        }
    }

    var queryValue: Int? {
        switch self {
        case .all: nil
        case .normal: 1
        case .banned: 0
        }
    }
}
