import SetuIOSCore
import SwiftUI

struct ApiKeyListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[ApiKeyItem]> = .idle
    @State private var newKeyName = ""
    @State private var dailyQuota = 1000
    @State private var totalQuotaText = ""
    @State private var createdKey: String?
    @State private var copyMessage: String?
    @State private var errorMessage: String?
    @State private var renameTarget: ApiKeyItem?

    var body: some View {
        List {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "新建", subtitle: "用于程序化调用图片和音乐接口")
                        TextField("Key 名称", text: $newKeyName)
                            .textFieldStyle(.roundedBorder)
                        Stepper("每日调用配额 \(dailyQuota)", value: $dailyQuota, in: 1...100_000, step: 100)
                            .foregroundStyle(SetuColor.textPrimary)
                        TextField("总调用配额（留空为无限制）", text: $totalQuotaText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                        SetuPrimaryButton {
                            Task { await createKey() }
                        } label: {
                            Label("创建 API Key", systemImage: "key")
                        }
                        .disabled(!canCreate)
                        .opacity(canCreate ? 1 : 0.55)

                        if let createdKey {
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                Text(createdKey)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(SetuColor.textPrimary)
                                    .textSelection(.enabled)
                                    .padding(SetuSpacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))

                                Button {
                                    copyCreatedKey(createdKey)
                                } label: {
                                    Label("复制新 Key", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(SetuColor.brandPink)
                            }
                        }

                        if let copyMessage {
                            SetuPill(text: copyMessage, systemImage: "checkmark.seal", tone: .success)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    SetuPill(text: errorMessage, systemImage: "exclamationmark.triangle", tone: .danger)
                }
            }

            apiKeyStats

            content
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle("API Keys")
        .sheet(item: $renameTarget) { key in
            ApiKeyRenameSheet(environment: environment, key: key) {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var apiKeyStats: some View {
        if case .loaded(let keys) = state, !keys.isEmpty {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "概览", subtitle: "API Key 使用情况")
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: SetuSpacing.sm),
                            GridItem(.flexible(), spacing: SetuSpacing.sm)
                        ], spacing: SetuSpacing.sm) {
                            SetuStatTile(title: "全部 Key", value: "\(keys.count)", systemImage: "key", color: SetuColor.brandPink)
                            SetuStatTile(title: "启用中", value: "\(keys.filter(\.isEnabled).count)", systemImage: "checkmark.circle", color: SetuColor.success)
                            SetuStatTile(title: "今日调用", value: "\(keys.reduce(0) { $0 + $1.callsToday })", systemImage: "calendar", color: SetuColor.info)
                            SetuStatTile(title: "历史总量", value: "\(keys.reduce(0) { $0 + $1.totalCalls })", systemImage: "chart.line.uptrend.xyaxis", color: SetuColor.warning)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            Section {
                SetuCard {
                    SetuEmptyState(title: "正在加载", systemImage: "key", isLoading: true)
                }
            }
        case .failed(let message):
            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.md) {
                        SetuEmptyState(title: "API Key 加载失败", message: message, systemImage: "key.slash")
                        Button {
                            Task { await load() }
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(SetuColor.brandPink)
                    }
                }
            }
        case .loaded(let keys):
            if keys.isEmpty {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "暂无 API Key", message: "创建一个 Key 后即可用于程序化调用。", systemImage: "key")
                    }
                }
            } else {
                Section {
                    SetuCard {
                        SetuSectionHeader(title: "我的 API Keys", subtitle: "共 \(keys.count) 个")
                    }
                }
                Section {
                    ForEach(keys) { key in
                        SetuCard {
                            ApiKeyRow(key: key) {
                                Task { await toggle(key) }
                            } onRename: {
                                renameTarget = key
                            } onDelete: {
                                Task { await delete(key) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var canCreate: Bool {
        !newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dailyQuota >= 1
            && totalQuotaIsValid
    }

    private var parsedTotalQuota: Int? {
        let text = totalQuotaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Int(text)
    }

    private var totalQuotaIsValid: Bool {
        let text = totalQuotaText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || (Int(text) ?? 0) >= 1
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.apiKeyClient.list())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func createKey() async {
        let name = newKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        errorMessage = nil
        copyMessage = nil
        do {
            createdKey = try await environment.apiKeyClient.create(name: name, dailyQuota: dailyQuota, totalQuota: parsedTotalQuota)
            newKeyName = ""
            dailyQuota = 1000
            totalQuotaText = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyCreatedKey(_ key: String) {
        PlatformClipboard.copy(key)
        copyMessage = "新 API Key 已复制"
    }

    private func toggle(_ key: ApiKeyItem) async {
        errorMessage = nil
        do {
            try await environment.apiKeyClient.setEnabled(id: key.id, enabled: !key.isEnabled)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ key: ApiKeyItem) async {
        errorMessage = nil
        do {
            try await environment.apiKeyClient.delete(id: key.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ApiKeyRow: View {
    let key: ApiKeyItem
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(key.name)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                Spacer()
                SetuPill(
                    text: key.isEnabled ? "启用" : "禁用",
                    systemImage: key.isEnabled ? "checkmark.circle" : "pause.circle",
                    tone: key.isEnabled ? .success : .muted
                )
            }
            HStack {
                Label("今日 \(key.callsToday)", systemImage: "calendar")
                Spacer()
                Label("总计 \(key.totalCalls)", systemImage: "sum")
            }
            .font(.footnote)
            .foregroundStyle(SetuColor.textSecondary)
            HStack {
                Label("每日限额 \(key.dailyQuota)", systemImage: "speedometer")
                Spacer()
                Label("总限额 \(key.totalQuota.map(String.init) ?? "∞")", systemImage: "chart.bar")
            }
            .font(.footnote)
            .foregroundStyle(SetuColor.textSecondary)
            HStack {
                Button(key.isEnabled ? "禁用" : "启用", action: onToggle)
                Button("重命名", action: onRename)
                Spacer()
                Button("删除", role: .destructive, action: onDelete)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct ApiKeyRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let key: ApiKeyItem
    let onSaved: () -> Void

    @State private var name: String
    @State private var message: String?

    init(environment: AppEnvironment, key: ApiKeyItem, onSaved: @escaping () -> Void) {
        self.environment = environment
        self.key = key
        self.onSaved = onSaved
        _name = State(initialValue: key.name)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "API Key", subtitle: "为这枚 Key 换一个易识别的名称")
                            ApiKeyInfoRow(title: "当前名称", value: key.name)
                            TextField("新名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if let message {
                    Section {
                        SetuPill(text: message, systemImage: "exclamationmark.triangle", tone: .danger)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle("重命名 API Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(trimmedName.isEmpty || trimmedName == key.name)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !trimmedName.isEmpty, trimmedName != key.name else { return }
        message = nil
        do {
            try await environment.apiKeyClient.rename(id: key.id, name: trimmedName)
            onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ApiKeyInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
            Spacer(minLength: SetuSpacing.md)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
