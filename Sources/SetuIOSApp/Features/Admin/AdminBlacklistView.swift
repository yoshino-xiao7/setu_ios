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

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后管理黑名单。"))
            } else {
                addSection
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                searchSection
                blacklistSection
                tempBlockSection
            }
        }
        .navigationTitle("黑名单")
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var addSection: some View {
        Section("添加封禁") {
            TextEditor(text: $ipInput)
                .frame(minHeight: 96)
                .overlay(alignment: .topLeading) {
                    if ipInput.isEmpty {
                        Text("每行一个 IP，也支持逗号分隔")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
            TextField("封禁原因", text: $reason)
            Button {
                Task { await addIps() }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label("添加到黑名单", systemImage: "nosign")
                }
            }
            .disabled(isSubmitting || parsedIps.isEmpty)
        }
    }

    private var searchSection: some View {
        Section {
            TextField("搜索 IP 或原因", text: $searchText)
        }
    }

    @ViewBuilder
    private var blacklistSection: some View {
        Section("固定黑名单") {
            switch blacklistState {
            case .idle, .loading:
                ProgressView("正在加载黑名单")
            case .failed(let message):
                ContentUnavailableView("黑名单加载失败", systemImage: "exclamationmark.shield", description: Text(message))
            case .loaded(let items):
                let filtered = filteredBlacklist(items)
                if filtered.isEmpty {
                    ContentUnavailableView("暂无封禁记录", systemImage: "shield")
                } else {
                    ForEach(filtered, id: \.stableID) { item in
                        BlacklistRow(item: item) {
                            Task { await removeIp(item.ip) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tempBlockSection: some View {
        Section("临时封禁") {
            switch tempBlockState {
            case .idle, .loading:
                ProgressView("正在加载临时封禁")
            case .failed(let message):
                ContentUnavailableView("临时封禁加载失败", systemImage: "clock.badge.exclamationmark", description: Text(message))
            case .loaded(let items):
                if items.isEmpty {
                    ContentUnavailableView("暂无临时封禁", systemImage: "clock")
                } else {
                    Button(role: .destructive) {
                        Task { await clearAllTempBlocks() }
                    } label: {
                        Label("清空全部临时封禁", systemImage: "trash")
                    }
                    .disabled(isSubmitting)

                    ForEach(items) { item in
                        TempBlockRow(item: item) {
                            Task { await clearTempBlock(item.ip) }
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
            blacklistState = .loaded(try await environment.adminClient.ipBlacklist())
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
            message = "已移除 \(ip)"
            await loadBlacklist()
        } catch {
            message = error.localizedDescription
        }
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
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(item.ip, systemImage: "network")
                    .font(.headline.monospaced())
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Text(item.reason?.isEmpty == false ? item.reason ?? "" : "未填写原因")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let createdAt = item.createdAt {
                Label(createdAt, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TempBlockRow: View {
    let item: AdminTempBlockItem
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(item.ip, systemImage: "clock.badge.exclamationmark")
                    .font(.headline.monospaced())
                Spacer()
                Button("解除", role: .destructive, action: onClear)
                    .buttonStyle(.borderless)
            }
            if let reason = item.reason, !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
