import SetuIOSCore
import SwiftUI

struct PasskeyListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[PasskeyItem]> = .idle
    @State private var renameTarget: PasskeyItem?
    @State private var deleteTarget: PasskeyItem?
    @State private var showingDeleteConfirmation = false
    @State private var message: String?
    @State private var nickname = "我的通行密钥"
    @State private var passkeyService = PasskeyAuthorizationService()
    @State private var isRegistering = false

    var body: some View {
        List {
            Section {
                Label("通行密钥可用于免密码登录。若开通失败，通常需要先完成应用域名和后端 WebAuthn 域名配置。", systemImage: "touchid")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("开通") {
                TextField("通行密钥名称", text: $nickname)
                Button {
                    Task { await registerPasskey() }
                } label: {
                    if isRegistering {
                        ProgressView()
                    } else {
                        Label("开通通行密钥", systemImage: "touchid")
                    }
                }
                .disabled(isRegistering || trimmedNickname.isEmpty)
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("通行密钥加载失败", systemImage: "touchid", description: Text(message))
            case .loaded(let passkeys):
                if passkeys.isEmpty {
                    ContentUnavailableView("未开通通行密钥", systemImage: "touchid", description: Text("在当前设备开通后，下次登录可以直接使用 Face ID、Touch ID 或设备密码验证。"))
                } else {
                    Section("共 \(passkeys.count) 个") {
                        ForEach(passkeys) { item in
                            PasskeyRow(item: item) {
                                renameTarget = item
                            } onDelete: {
                                deleteTarget = item
                                showingDeleteConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("通行密钥")
        .sheet(item: $renameTarget) { item in
            PasskeyRenameSheet(environment: environment, item: item) {
                message = "通行密钥已重命名"
                Task { await load() }
            }
        }
        .confirmationDialog("删除通行密钥？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(deleteButtonTitle, role: .destructive) {
                if let deleteTarget {
                    Task { await delete(deleteTarget) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，这个设备或凭据将不能再用于通行密钥登录。")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var deleteButtonTitle: String {
        "删除「\(deleteTarget?.displayName ?? "通行密钥")」"
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.passkeyClient.list())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func delete(_ item: PasskeyItem) async {
        do {
            try await environment.passkeyClient.delete(id: item.id)
            message = "通行密钥已删除"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func registerPasskey() async {
        guard !trimmedNickname.isEmpty else { return }
        isRegistering = true
        message = nil
        do {
            let options = try await environment.passkeyClient.beginRegistration(nickname: trimmedNickname)
            let credential = try await passkeyService.createCredential(options: options.publicKey.publicKey)
            _ = try await environment.passkeyClient.finishRegistration(
                challengeID: options.challengeId,
                nickname: trimmedNickname,
                credential: credential
            )
            message = "通行密钥已开通"
            await load()
        } catch {
            message = error.localizedDescription
        }
        isRegistering = false
    }
}

private struct PasskeyRow: View {
    let item: PasskeyItem
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "touchid")
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayName)
                    .font(.headline)
                HStack(spacing: 10) {
                    if let createdAt = item.createdAt {
                        Label(createdAt, systemImage: "calendar")
                    }
                    if let lastUsedAt = item.lastUsedAt {
                        Label(lastUsedAt, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let transports = item.transports, !transports.isEmpty {
                    Text(transports.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button(action: onRename) {
                    Label("重命名", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct PasskeyRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: PasskeyItem
    let onSaved: () -> Void

    @State private var nickname: String
    @State private var message: String?
    @State private var saving = false

    init(environment: AppEnvironment, item: PasskeyItem, onSaved: @escaping () -> Void) {
        self.environment = environment
        self.item = item
        self.onSaved = onSaved
        _nickname = State(initialValue: item.nickname ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("通行密钥名称", text: $nickname)
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("重命名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(saving || trimmedNickname.isEmpty)
                }
            }
        }
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !trimmedNickname.isEmpty else { return }
        saving = true
        message = nil
        do {
            _ = try await environment.passkeyClient.rename(id: item.id, nickname: trimmedNickname)
            onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
        saving = false
    }
}
