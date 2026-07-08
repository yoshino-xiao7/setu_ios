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

    var body: some View {
        List {
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
                    .setuListRow()
                }
                searchSection
                blacklistSection
                tempBlockSection
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("黑名单")
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var addSection: some View {
        SetuCard {
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
                    Task { await addIps() }
                } label: {
                    Label(isSubmitting ? "提交中" : "添加到黑名单", systemImage: isSubmitting ? "hourglass" : "nosign")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
                .disabled(isSubmitting || parsedIps.isEmpty)
            }
        }
        .setuListRow()
    }

    private var searchSection: some View {
        SetuCard {
            TextField("搜索 IP 或原因", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .setuListRow()
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
            let filteredIPs = Set(filtered.map(\.ip))
            if filtered.isEmpty {
                AdminBlacklistStateSection(title: "固定黑名单", stateTitle: "暂无封禁记录", message: "当前筛选条件下没有固定封禁记录。", systemImage: "shield")
            } else {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "固定黑名单", subtitle: "\(filtered.count) 条")
                        HStack {
                            Button(selectedBlacklistIPs.isSuperset(of: filteredIPs) ? "取消选择当前结果" : "选择当前结果") {
                                if selectedBlacklistIPs.isSuperset(of: filteredIPs) {
                                    selectedBlacklistIPs.subtract(filteredIPs)
                                } else {
                                    selectedBlacklistIPs.formUnion(filteredIPs)
                                }
                            }
                            .disabled(isSubmitting)

                            Spacer()

                            Text("已选 \(selectedBlacklistIPs.intersection(filteredIPs).count) / \(filtered.count)")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }

                        HStack {
                            Button("清空选择") {
                                selectedBlacklistIPs.removeAll()
                            }
                            .disabled(isSubmitting || selectedBlacklistIPs.isEmpty)

                            Spacer()

                            Button(role: .destructive) {
                                Task { await batchRemoveIps(currentIPs: filteredIPs) }
                            } label: {
                                Label(isSubmitting ? "处理中" : "批量解封", systemImage: isSubmitting ? "hourglass" : "lock.open")
                                    .frame(minHeight: 44)
                            }
                            .disabled(isSubmitting || selectedBlacklistIPs.intersection(filteredIPs).isEmpty)
                        }

                        ForEach(Array(filtered.enumerated()), id: \.element.stableID) { index, item in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                            BlacklistRow(item: item, isSelected: selectedBlacklistIPs.contains(item.ip)) {
                                toggleBlacklistSelection(item.ip)
                            } onRemove: {
                                Task { await removeIp(item.ip) }
                            }
                        }
                    }
                }
                .setuListRow()
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
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "临时封禁", subtitle: "\(items.count) 条")
                        Button(role: .destructive) {
                            Task { await clearAllTempBlocks() }
                        } label: {
                            Label("清空全部临时封禁", systemImage: "trash")
                                .frame(minHeight: 44)
                        }
                        .disabled(isSubmitting)

                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                            TempBlockRow(item: item) {
                                Task { await clearTempBlock(item.ip) }
                            }
                        }
                    }
                }
                .setuListRow()
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
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? SetuColor.warning : SetuColor.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                Label(item.ip, systemImage: "network")
                    .font(.headline.monospaced())
                    .foregroundStyle(SetuColor.textPrimary)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
            }
            Text(item.reason?.isEmpty == false ? item.reason ?? "" : "未填写原因")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
            if let createdAt = item.createdAt {
                Label(createdAt, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textTertiary)
            }
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct TempBlockRow: View {
    let item: AdminTempBlockItem
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack {
                Label(item.ip, systemImage: "clock.badge.exclamationmark")
                    .font(.headline.monospaced())
                    .foregroundStyle(SetuColor.textPrimary)
                Spacer()
                Button(role: .destructive, action: onClear) {
                    Label("解除", systemImage: "lock.open")
                        .frame(minHeight: 44)
                }
                    .buttonStyle(.borderless)
            }
            if let reason = item.reason, !reason.isEmpty {
                Text(reason)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            HStack(spacing: 12) {
                if let blockedAt = item.blockedAt {
                    Label(blockedAt, systemImage: "lock")
                }
                if let expiresAt = item.expiresAt {
                    Label(expiresAt, systemImage: "timer")
                }
            }
            .font(.caption)
            .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct AdminBlacklistStateSection: View {
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
