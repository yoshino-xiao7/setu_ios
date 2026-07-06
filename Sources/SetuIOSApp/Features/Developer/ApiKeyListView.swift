import SetuIOSCore
import SwiftUI

struct ApiKeyListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[ApiKeyItem]> = .idle
    @State private var newKeyName = ""
    @State private var createdKey: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("新建") {
                TextField("Key 名称", text: $newKeyName)
                Button("创建 API Key") {
                    Task { await createKey() }
                }
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let createdKey {
                    Text(createdKey)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
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
        do {
            createdKey = try await environment.apiKeyClient.create(name: name)
            newKeyName = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                Spacer()
                Button("删除", role: .destructive, action: onDelete)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
