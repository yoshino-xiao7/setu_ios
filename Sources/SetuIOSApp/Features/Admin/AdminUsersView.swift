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
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后管理用户。"))
            } else {
                filterSection
                content
            }
        }
        .navigationTitle("用户管理")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        Section("筛选") {
            TextField("邮箱", text: $email)
            TextField("昵称", text: $nickname)
            Picker("状态", selection: $statusFilter) {
                ForEach(AdminUserStatusFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            Button {
                Task { await load(resetPage: true) }
            } label: {
                Label("搜索用户", systemImage: "magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载用户")
        case .failed(let message):
            ContentUnavailableView("用户列表加载失败", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(message))
        case .loaded(let result):
            let users = result.list ?? []
            if users.isEmpty {
                ContentUnavailableView("暂无用户", systemImage: "person.2.slash", description: Text("调整筛选条件后再试一次。"))
            } else {
                Section("共 \(result.total) 位用户") {
                    ForEach(users) { user in
                        Button {
                            router.navigate(to: .adminUserDetail(user.id))
                        } label: {
                            AdminUserRow(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                pagerSection(result: result)
            }
        }
    }

    private func pagerSection(result: AdminUserListResponse) -> some View {
        Section {
            HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load(resetPage: false)
                    }
                }
                .disabled(page <= 1)
                Spacer()
                Text("第 \(result.page ?? page) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下一页") {
                    Task {
                        page += 1
                        await load(resetPage: false)
                    }
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
    @Bindable var environment: AppEnvironment
    let userID: Int
    @State private var state: LoadState<AdminUserDetail> = .idle
    @State private var actionMessage: String?
    @State private var pointsAmount = ""
    @State private var pointsReason = ""
    @State private var isSubmitting = false

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查看用户详情。"))
            } else {
                if let actionMessage {
                    Section {
                        Text(actionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
        }
        .navigationTitle("用户详情")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载用户详情")
        case .failed(let message):
            ContentUnavailableView("用户详情加载失败", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(message))
        case .loaded(let user):
            summarySection(user)
            actionSection(user)
            pointsSection
            apiKeysSection(user.apiKeys ?? [])
        }
    }

    private func summarySection(_ user: AdminUserDetail) -> some View {
        Section("基础信息") {
            LabeledContent("ID", value: "\(user.id)")
            LabeledContent("邮箱", value: user.email)
            LabeledContent("昵称", value: user.nickname ?? "-")
            LabeledContent("角色", value: user.roleTitle)
            LabeledContent("状态", value: user.statusTitle)
            LabeledContent("邮箱验证", value: user.emailVerified == true ? "已验证" : "未验证")
            LabeledContent("注册 IP", value: user.registerIp ?? "-")
            LabeledContent("最后登录 IP", value: user.lastLoginIp ?? "-")
            LabeledContent("创建时间", value: user.createdAt ?? "-")
            LabeledContent("更新时间", value: user.updatedAt ?? "-")
        }
    }

    private func actionSection(_ user: AdminUserDetail) -> some View {
        Section("账号操作") {
            Button(role: user.status == 0 ? nil : .destructive) {
                Task { await toggleBan(user) }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label(user.status == 0 ? "解除封禁" : "封禁用户", systemImage: user.status == 0 ? "lock.open" : "lock")
                }
            }
            .disabled(isSubmitting)
        }
    }

    private var pointsSection: some View {
        Section("发放积分") {
            TextField("积分数量", text: $pointsAmount)
            TextField("原因", text: $pointsReason)
            Button {
                Task { await grantPoints() }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label("发放积分", systemImage: "plus.circle")
                }
            }
            .disabled(isSubmitting || Int(pointsAmount) == nil)
        }
    }

    private func apiKeysSection(_ apiKeys: [AdminUserApiKey]) -> some View {
        Section("API Keys") {
            if apiKeys.isEmpty {
                ContentUnavailableView("暂无 API Key", systemImage: "key.slash")
            } else {
                ForEach(apiKeys) { key in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(key.name)
                                .font(.headline)
                            Spacer()
                            Text(key.statusTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(key.status == 1 ? .green : .secondary)
                        }
                        HStack {
                            Label("今日 \(key.callsToday ?? 0)", systemImage: "calendar")
                            Spacer()
                            Label("总计 \(key.totalCalls ?? 0)", systemImage: "sum")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        if let createdAt = key.createdAt {
                            Text("创建于 \(createdAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.nickname ?? user.email)
                        .font(.headline)
                    Text(user.email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AdminStatusBadge(title: user.statusTitle, isBanned: user.status == 0)
            }
            HStack(spacing: 12) {
                Label(user.roleTitle, systemImage: user.role == 1 ? "shield" : "person")
                if let createdAt = user.createdAt {
                    Label(createdAt, systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AdminStatusBadge: View {
    let title: String
    let isBanned: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isBanned ? Color.red : Color.green).opacity(0.14), in: Capsule())
            .foregroundStyle(isBanned ? .red : .green)
    }
}

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
