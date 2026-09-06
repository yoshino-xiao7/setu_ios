import AuthenticationServices
import SetuIOSCore
import SwiftUI

struct PasskeyListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[PasskeyItem]> = .idle
    @State private var renameTarget: PasskeyItem?
    @State private var deleteTarget: PasskeyItem?
    @State private var showingDeleteConfirmation = false
    @State private var feedback: SetuFeedback?
    @State private var nickname = "我的通行密钥"
    @State private var passkeyService = PasskeyAuthorizationService()
    @State private var isRegistering = false

    var body: some View {
        SetuBoard {
            SetuBento(items: [AccountSurfaceItem(title: "通行密钥", value: passkeyCountText, systemImage: "touchid")], span: { _ in .wide }) { item in
                SetuBentoTile(title: item.title, subtitle: item.value, systemImage: item.systemImage)
            }
            Text("使用 Face ID、Touch ID 或设备密码安全登录，无需记住密码。")
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textSecondary)

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
                                HStack(spacing: SetuSpacing.sm) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("正在开通通行密钥")
                                }
                            } else {
                                Label("开通通行密钥", systemImage: "touchid")
                            }
                        }
                        .disabled(isRegistering || trimmedNickname.isEmpty)
                        .opacity(isRegistering || trimmedNickname.isEmpty ? 0.55 : 1)
                    }
                }
            }

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }
            }

            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        AccountSurfaceSkeleton(title: "正在加载通行密钥")
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "通行密钥加载失败",
                            message: message,
                            systemImage: "touchid",
                            actionTitle: "重试",
                            action: { Task { await load() } }
                        )
                    }
                }
            case .loaded(let passkeys):
                if passkeys.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(
                                title: "未开通通行密钥",
                                message: "请使用上方“开通通行密钥”完成设置，下次登录即可使用 Face ID、Touch ID 或设备密码验证。",
                                systemImage: "touchid"
                            )
                        }
                    }
                } else {
                    SetuSectionHeader(title: "已开通", subtitle: "共 \(passkeys.count) 个")
                    SetuRecordBoard(items: passkeys) { item in
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
        .setuFeedbackPresentation($feedback)
        .navigationTitle("通行密钥")
        .sheet(item: $renameTarget) { item in
            PasskeyRenameSheet(environment: environment, item: item) {
                feedback = .success("通行密钥已重命名")
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

    private var passkeyCountText: String {
        switch state {
        case .idle, .loading: "正在确认已开通设备"
        case .failed: "设备数量暂未同步"
        case .loaded(let items): items.isEmpty ? "尚未开通" : "已开通 \(items.count) 个"
        }
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
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func delete(_ item: PasskeyItem) async {
        do {
            try await environment.passkeyClient.delete(id: item.id)
            feedback = .success("通行密钥已删除")
            await load()
        } catch {
            feedback = passkeyFeedback(for: error)
        }
    }

    private func registerPasskey() async {
        guard !trimmedNickname.isEmpty else { return }
        isRegistering = true
        feedback = nil
        do {
            let options = try await environment.passkeyClient.beginRegistration(nickname: trimmedNickname)
            let credential = try await passkeyService.createCredential(options: options.publicKey.publicKey)
            _ = try await environment.passkeyClient.finishRegistration(
                challengeID: options.challengeId,
                nickname: trimmedNickname,
                credential: credential
            )
            feedback = .success("通行密钥已开通")
            await load()
        } catch {
            feedback = passkeyFeedback(for: error)
        }
        isRegistering = false
    }
}

private struct PasskeyRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: PasskeyItem
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SetuRecordCard(
            headline: item.displayName,
            status: .init("已开通", tone: .success),
            fields: details
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SetuSpacing.md) { actionButtons }
                VStack(alignment: .leading, spacing: SetuSpacing.sm) { actionButtons }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onRename) { Label("重命名", systemImage: "pencil").frame(minHeight: 44) }
            .buttonStyle(.bordered)
        Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash").frame(minHeight: 44) }
            .buttonStyle(.bordered)
    }

    private var details: [SetuRecordField] {
        var fields: [SetuRecordField] = []
        if let createdAt = item.createdAt { fields.append(.init("创建时间", SetuDateFormatter.string(from: createdAt))) }
        if let lastUsedAt = item.lastUsedAt { fields.append(.init("最近使用", SetuDateFormatter.string(from: lastUsedAt))) }
        if let transportTitle { fields.append(.init("可用于", transportTitle, isNumeric: false)) }
        return fields
    }

    private var transportTitle: String? {
        guard let transports = item.transports else { return nil }
        let titles = Set(transports.compactMap { transport -> String? in
            switch transport.lowercased() {
            case "internal": "此设备"
            case "hybrid": "附近设备"
            case "usb", "nfc", "ble": "安全密钥"
            default: nil
            }
        })
        return titles.isEmpty ? nil : titles.sorted().joined(separator: "、")
    }
}

private struct PasskeyRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: PasskeyItem
    let onSaved: () -> Void

    @State private var nickname: String
    @State private var feedback: SetuFeedback?
    @State private var saving = false

    init(environment: AppEnvironment, item: PasskeyItem, onSaved: @escaping () -> Void) {
        self.environment = environment
        self.item = item
        self.onSaved = onSaved
        _nickname = State(initialValue: item.nickname ?? "")
    }

    var body: some View {
        NavigationStack {
            SetuBoard {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "名称", subtitle: "换一个更容易识别的设备名称")
                            TextField("通行密钥名称", text: $nickname)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
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
        feedback = nil
        do {
            _ = try await environment.passkeyClient.rename(id: item.id, nickname: trimmedNickname)
            onSaved()
            dismiss()
        } catch {
            feedback = passkeyFeedback(for: error)
        }
        saving = false
    }
}

@MainActor
private func passkeyFeedback(for error: Error) -> SetuFeedback {
    let message = PasskeyAuthorizationService.userMessage(for: error)
    if let authorizationError = error as? ASAuthorizationError,
       authorizationError.code == .canceled {
        return .info(message)
    }
    return .error(message)
}
