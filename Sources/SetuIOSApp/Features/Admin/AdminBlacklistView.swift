import SetuIOSCore
import SwiftUI

struct AdminBlacklistView: View {
    @Bindable var environment: AppEnvironment
    @State private var blacklistState: LoadState<[AdminBlacklistIpItem]> = .idle
    @State private var tempBlockState: LoadState<[AdminTempBlockItem]> = .idle
    @State private var searchText = ""
    @State private var ipInput = ""
    @State private var reason = ""
    @State private var message: String?
    @State private var isSubmitting = false
    @State private var selectedBlacklistIPs = Set<String>()

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminBlacklistStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后管理黑名单。", systemImage: "shield.slash")
            } else {
                addSection
                if let message {
                    SetuCard {
                        Label(message, systemImage: "checkmark.circle")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                searchSection
                blacklistSection
                tempBlockSection
            }
        }
        .setuBackground()
        .navigationTitle("黑名单")
        .setuActionDock {
            if environment.authSession.currentUser?.role == .admin {
                Menu {
                    if case .loaded(let items) = blacklistState {
                        let filteredIPs = Set(filteredBlacklist(items).map(\.ip))
                        Button(selectedBlacklistIPs.isSuperset(of: filteredIPs) ? "取消选择当前结果" : "选择当前结果") {
                            if selectedBlacklistIPs.isSuperset(of: filteredIPs) { selectedBlacklistIPs.subtract(filteredIPs) }
                            else { selectedBlacklistIPs.formUnion(filteredIPs) }
                        }
                        Button("清空选择") { selectedBlacklistIPs.removeAll() }.disabled(selectedBlacklistIPs.isEmpty)
                        Button("批量解封", role: .destructive) {
                            pendingActionTitle = "确认批量解封已选 IP？"
                            pendingAction = { Task { await batchRemoveIps(currentIPs: filteredIPs) } }
                        }.disabled(selectedBlacklistIPs.intersection(filteredIPs).isEmpty)
                    }
                    if case .loaded(let items) = tempBlockState, !items.isEmpty {
                        Button("清空全部临时封禁", role: .destructive) {
                            pendingActionTitle = "确认清空全部临时封禁？"
                            pendingAction = { Task { await clearAllTempBlocks() } }
                        }
                    }
                } label: {
                    Label("批量管理 · 已选 \(selectedBlacklistIPs.count)", systemImage: "checklist")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }.disabled(isSubmitting)
            }
        }
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
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var addSection: some View {
        SetuRecordCard(headline: "添加封禁", status: .init("请核对后操作", tone: .danger), density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "添加封禁")
                TextEditor(text: $ipInput)
                    .frame(minHeight: 96)
                    .padding(SetuSpacing.xs)
                    .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if ipInput.isEmpty {
                            Text("每行一个 IP，也支持逗号分隔")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textTertiary)
                                .padding(.top, SetuSpacing.md)
                                .padding(.leading, SetuSpacing.md)
                        }
                    }
                TextField("封禁原因", text: $reason)
                    .textFieldStyle(.roundedBorder)
                Button {
                    pendingActionTitle = "确认封禁输入的 IP？"; pendingAction = { Task { await addIps() } }
                } label: {
                    Label(isSubmitting ? "提交中" : "添加到黑名单", systemImage: isSubmitting ? "hourglass" : "nosign")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandOnLight)
                .foregroundStyle(.white)
                .disabled(isSubmitting || parsedIps.isEmpty)
            }
        }

    }

    private var searchSection: some View {
        SetuCard {
            TextField("搜索 IP 或原因", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }

    }

    @ViewBuilder
    private var blacklistSection: some View {
        switch blacklistState {
        case .idle, .loading:
            AdminBlacklistStateSection(title: "固定黑名单", stateTitle: "正在加载黑名单", systemImage: "shield", isLoading: true)
        case .failed(let message):
            AdminBlacklistStateSection(title: "固定黑名单", stateTitle: "黑名单加载失败", message: message, systemImage: "exclamationmark.shield")
        case .loaded(let items):
            let filtered = filteredBlacklist(items)

            if filtered.isEmpty {
                AdminBlacklistStateSection(title: "固定黑名单", stateTitle: "暂无封禁记录", message: "当前筛选条件下没有固定封禁记录。", systemImage: "shield")
            } else {
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "固定黑名单", subtitle: "\(filtered.count) 条")
                        SetuRecordBoard(items: filtered) { item in
                            BlacklistRow(item: item, isSelected: selectedBlacklistIPs.contains(item.ip)) {
                                toggleBlacklistSelection(item.ip)
                            } onRemove: {
                                pendingActionTitle = "确认解除此 IP 的封禁？"; pendingAction = { Task { await removeIp(item.ip) } }
                            }
                        }
                    }
                }

            }
        }
    }

    @ViewBuilder
    private var tempBlockSection: some View {
        switch tempBlockState {
        case .idle, .loading:
            AdminBlacklistStateSection(title: "临时封禁", stateTitle: "正在加载临时封禁", systemImage: "clock", isLoading: true)
        case .failed(let message):
            AdminBlacklistStateSection(title: "临时封禁", stateTitle: "临时封禁加载失败", message: message, systemImage: "clock.badge.exclamationmark")
        case .loaded(let items):
            if items.isEmpty {
                AdminBlacklistStateSection(title: "临时封禁", stateTitle: "暂无临时封禁", systemImage: "clock")
            } else {
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "临时封禁", subtitle: "\(items.count) 条")
                        SetuRecordBoard(items: items) { item in
                            TempBlockRow(item: item) {
                                pendingActionTitle = "确认解除临时封禁？"; pendingAction = { Task { await clearTempBlock(item.ip) } }
                            }
                        }
                    }
                }

            }
        }
    }

    private var parsedIps: [String] {
        ipInput
            .split { character in
                character == "\n" || character == "," || character == " "
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func filteredBlacklist(_ items: [AdminBlacklistIpItem]) -> [AdminBlacklistIpItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return items }
        return items.filter { item in
            item.ip.lowercased().contains(keyword) || (item.reason?.lowercased().contains(keyword) == true)
        }
    }

    private func loadAll() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadBlacklist() }
            group.addTask { await loadTempBlocks() }
        }
    }

    private func loadBlacklist() async {
        blacklistState = .loading
        do {
            let items = try await environment.adminClient.ipBlacklist()
            selectedBlacklistIPs.formIntersection(Set(items.map(\.ip)))
            blacklistState = .loaded(items)
        } catch {
            blacklistState = .failed(error.localizedDescription)
        }
    }

    private func loadTempBlocks() async {
        tempBlockState = .loading
        do {
            tempBlockState = .loaded(try await environment.adminClient.tempBlocks())
        } catch {
            tempBlockState = .failed(error.localizedDescription)
        }
    }

    private func addIps() async {
        let targets = parsedIps
        guard !targets.isEmpty else { return }
        isSubmitting = true
        message = nil
        do {
            for ip in targets {
                try await environment.adminClient.addIpBlacklist(ip: ip, reason: reason)
            }
            message = "已封禁 \(targets.count) 个 IP"
            ipInput = ""
            reason = ""
            await loadBlacklist()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func removeIp(_ ip: String) async {
        isSubmitting = true
        message = nil
        do {
            try await environment.adminClient.removeIpBlacklist(ip: ip)
            selectedBlacklistIPs.remove(ip)
            message = "已移除 \(ip)"
            await loadBlacklist()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func toggleBlacklistSelection(_ ip: String) {
        if selectedBlacklistIPs.contains(ip) {
            selectedBlacklistIPs.remove(ip)
        } else {
            selectedBlacklistIPs.insert(ip)
        }
    }

    private func batchRemoveIps(currentIPs: Set<String>) async {
        let targets = Array(selectedBlacklistIPs.intersection(currentIPs)).sorted()
        guard !targets.isEmpty else { return }
        isSubmitting = true
        message = nil
        var successCount = 0
        var failures: [(ip: String, message: String)] = []

        for ip in targets {
            do {
                try await environment.adminClient.removeIpBlacklist(ip: ip)
                selectedBlacklistIPs.remove(ip)
                successCount += 1
            } catch {
                failures.append((ip: ip, message: error.localizedDescription))
            }
        }

        if failures.isEmpty {
            message = "成功解封 \(successCount) 个 IP"
        } else if successCount > 0, let firstFailure = failures.first {
            message = "已解封 \(successCount) 个，\(failures.count) 个失败：\(firstFailure.ip) \(firstFailure.message)"
        } else {
            message = failures.first?.message ?? "批量解封失败"
        }
        await loadBlacklist()
        isSubmitting = false
    }

    private func clearTempBlock(_ ip: String) async {
        isSubmitting = true
        message = nil
        do {
            try await environment.adminClient.clearTempBlock(ip: ip)
            message = "已解除 \(ip) 的临时封禁"
            await loadTempBlocks()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func clearAllTempBlocks() async {
        isSubmitting = true
        message = nil
        do {
            try await environment.adminClient.clearAllTempBlocks()
            message = "已清空全部临时封禁"
            await loadTempBlocks()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }
}

private struct BlacklistRow: View {
    let item: AdminBlacklistIpItem
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SetuRecordCard(headline: item.ip, status: .init("已封禁", tone: .danger),
            fields: [.init("原因", item.reason?.isEmpty == false ? item.reason! : "未填写原因"),
                     .init("创建时间", item.createdAt ?? "-")], density: .compact) {
            HStack {
                Button(action: onToggleSelection) {
                    Label(isSelected ? "取消选择" : "选择", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .frame(minHeight: 44)
                }.buttonStyle(.borderless)
                Spacer()
                Button("解除封禁", role: .destructive, action: onRemove).frame(minHeight: 44)
            }
        }
    }
}

private struct TempBlockRow: View {
    let item: AdminTempBlockItem
    let onClear: () -> Void

    var body: some View {
        SetuRecordCard(headline: item.ip, status: .init("临时封禁", tone: .danger),
            fields: [.init("原因", item.reason ?? "-"), .init("封禁时间", item.blockedAt ?? "-"),
                     .init("到期时间", item.expiresAt ?? "-")], density: .compact) {
            Button("解除", role: .destructive, action: onClear).frame(minHeight: 44)
        }
    }
}

private typealias AdminBlacklistStateSection = AdminRecordStateSection
