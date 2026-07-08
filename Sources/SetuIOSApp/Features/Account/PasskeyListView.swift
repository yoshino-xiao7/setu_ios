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
                SetuCard {
                    Label {
                        Text("通行密钥可用于免密码登录。若开通失败，通常需要先完成应用域名配置。")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    } icon: {
                        Image(systemName: "touchid")
                            .foregroundStyle(SetuColor.brandPink)
                    }
                }
            }

            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "开通", subtitle: "为当前设备创建一枚新的通行密钥")
                        TextField("通行密钥名称", text: $nickname)
                            .textFieldStyle(.roundedBorder)
                        SetuPrimaryButton {
                            Task { await registerPasskey() }
                        } label: {
                            if isRegistering {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("开通通行密钥", systemImage: "touchid")
                            }
                        }
                        .disabled(isRegistering || trimmedNickname.isEmpty)
                        .opacity(isRegistering || trimmedNickname.isEmpty ? 0.55 : 1)
                    }
                }
            }

            if let message {
                Section {
                    SetuPill(text: message, systemImage: "checkmark.seal", tone: .info)
                }
            }

            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "touchid", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "通行密钥加载失败", message: message, systemImage: "touchid")
                    }
                }
            case .loaded(let passkeys):
                if passkeys.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(
                                title: "未开通通行密钥",
                                message: "在当前设备开通后，下次登录可以直接使用 Face ID、Touch ID 或设备密码验证。",
                                systemImage: "touchid"
                            )
                        }
                    }
                } else {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "已开通", subtitle: "共 \(passkeys.count) 个")
                                ForEach(passkeys) { item in
                                    PasskeyRow(item: item) {
                                        renameTarget = item
                                    } onDelete: {
                                        deleteTarget = item
                                        showingDeleteConfirmation = true
                                    }
                                    if item.id != passkeys.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
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
            message = PasskeyAuthorizationService.userMessage(for: error)
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
            message = PasskeyAuthorizationService.userMessage(for: error)
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(SetuColor.brandPink)
                .frame(width: 40, height: 40)
                .background(SetuColor.brandSoft.opacity(0.2), in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayName)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                HStack(spacing: 10) {
                    if let createdAt = item.createdAt {
                        Label(createdAt, systemImage: "calendar")
                    }
                    if let lastUsedAt = item.lastUsedAt {
                        Label(lastUsedAt, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)

                if let transports = item.transports, !transports.isEmpty {
                    Text(transports.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
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
                    .font(.title3)
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SetuSpacing.xs)
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
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "名称", subtitle: "换一个更容易识别的设备名称")
                            TextField("通行密钥名称", text: $nickname)
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
            message = PasskeyAuthorizationService.userMessage(for: error)
        }
        saving = false
    }
}
