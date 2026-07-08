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
                AdminUserStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后管理用户。", systemImage: "shield.slash")
            } else {
                filterSection
                content
            }
        }
        .listStyle(.plain)
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
                Picker("状态", selection: $statusFilter) {
                    ForEach(AdminUserStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("搜索用户", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
            }
        }
        .setuListRow()
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
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 位用户", subtitle: "用户管理")
                    ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                        Button {
                            router.navigate(to: .adminUserDetail(user.id))
                        } label: {
                            AdminUserRow(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
                .setuListRow()
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
        .setuListRow()
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

    var body: some View {
        List {
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
                    .setuListRow()
                }
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("用户详情")
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
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "基础信息")
                AdminUserMetadataRow(title: "ID", value: "\(user.id)")
                AdminUserMetadataRow(title: "邮箱", value: user.email)
                AdminUserMetadataRow(title: "昵称", value: user.nickname ?? "-")
                AdminUserMetadataRow(title: "角色", value: user.roleTitle)
                AdminUserMetadataRow(title: "状态") {
                    AdminStatusBadge(title: user.statusTitle, isBanned: user.status == 0)
                }
                AdminUserMetadataRow(title: "邮箱验证", value: user.emailVerified == true ? "已验证" : "未验证")
                AdminUserMetadataRow(title: "注册 IP", value: user.registerIp ?? "-")
                AdminUserMetadataRow(title: "最后登录 IP", value: user.lastLoginIp ?? "-")
                AdminUserMetadataRow(title: "创建时间", value: user.createdAt ?? "-")
                AdminUserMetadataRow(title: "更新时间", value: user.updatedAt ?? "-")
            }
        }
        .setuListRow()
    }

    private func actionSection(_ user: AdminUserDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "账号操作")
            Button(role: user.status == 0 ? nil : .destructive) {
                Task { await toggleBan(user) }
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
        .setuListRow()
    }

    private var pointsSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "发放积分")
            TextField("积分数量", text: $pointsAmount)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            TextField("原因", text: $pointsReason)
                    .textFieldStyle(.roundedBorder)
            Button {
                Task { await grantPoints() }
            } label: {
                    Label(isSubmitting ? "发放中" : "发放积分", systemImage: isSubmitting ? "hourglass" : "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
            .disabled(isSubmitting || Int(pointsAmount) == nil)
        }
        }
        .setuListRow()
    }

    private func apiKeysSection(_ apiKeys: [AdminUserApiKey]) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "API Keys")
            if apiKeys.isEmpty {
                    SetuEmptyState(title: "暂无 API Key", systemImage: "key.slash")
            } else {
                    ForEach(Array(apiKeys.enumerated()), id: \.element.id) { index, key in
                        if index > 0 {
                            Divider()
                                .overlay(SetuColor.separator)
                        }
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        HStack {
                            Text(key.name)
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                            Spacer()
                                SetuPill(text: key.statusTitle, systemImage: "key", tone: key.status == 1 ? .success : .muted)
                        }
                        HStack {
                            Label("今日 \(key.callsToday ?? 0)", systemImage: "calendar")
                            Spacer()
                            Label("总计 \(key.totalCalls ?? 0)", systemImage: "sum")
                        }
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                        if let createdAt = key.createdAt {
                            Text("创建于 \(createdAt)")
                                .font(.caption)
                                    .foregroundStyle(SetuColor.textTertiary)
                        }
                    }
                        .padding(.vertical, SetuSpacing.xs)
                }
            }
        }
        }
        .setuListRow()
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
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.nickname ?? user.email)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(user.email)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
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
            .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct AdminStatusBadge: View {
    let title: String
    let isBanned: Bool

    var body: some View {
        SetuPill(text: title, systemImage: isBanned ? "lock" : "checkmark.circle", tone: isBanned ? .danger : .success)
    }
}

private struct AdminUserStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
            }
        }
        .setuListRow()
    }
}

private struct AdminUserMetadataRow<Value: View>: View {
    let title: String
    private let value: Value

    init(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 84, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private extension AdminUserMetadataRow where Value == Text {
    init(title: String, value: String) {
        self.title = title
        self.value = Text(value)
            .font(SetuTypography.body)
            .foregroundStyle(SetuColor.textPrimary)
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
