import SetuIOSCore
import SwiftUI

struct ApiKeyListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[ApiKeyItem]> = .idle
    @State private var newKeyName = ""
    @State private var createdKey: String?
    @State private var copyMessage: String?
    @State private var errorMessage: String?
    @State private var renameTarget: ApiKeyItem?

    var body: some View {
        List {
            Section("新建") {
                TextField("Key 名称", text: $newKeyName)
                Button("创建 API Key") {
                    Task { await createKey() }
                }
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let createdKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(createdKey)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)

                        Button {
                            copyCreatedKey(createdKey)
                        } label: {
                            Label("复制新 Key", systemImage: "doc.on.doc")
                        }
                    }
                }

                if let copyMessage {
                    Text(copyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("我的 API Keys") {
                content
            }
        }
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
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("加载失败")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task { await load() }
                }
            }
        case .loaded(let keys):
            if keys.isEmpty {
                ContentUnavailableView("暂无 API Key", systemImage: "key", description: Text("创建一个 Key 后即可用于程序化调用。"))
            } else {
                ForEach(keys) { key in
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
            createdKey = try await environment.apiKeyClient.create(name: name)
            newKeyName = ""
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
                    .font(.headline)
                Spacer()
                Text(key.isEnabled ? "启用" : "禁用")
                    .font(.caption)
                    .foregroundStyle(key.isEnabled ? .green : .secondary)
            }
            HStack {
                Label("今日 \(key.callsToday)", systemImage: "calendar")
                Spacer()
                Label("总计 \(key.totalCalls)", systemImage: "sum")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack {
                Button(key.isEnabled ? "禁用" : "启用", action: onToggle)
                Button("重命名", action: onRename)
                Spacer()
                Button("删除", role: .destructive, action: onDelete)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
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
            Form {
                Section("API Key") {
                    LabeledContent("当前名称", value: key.name)
                    TextField("新名称", text: $name)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
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
