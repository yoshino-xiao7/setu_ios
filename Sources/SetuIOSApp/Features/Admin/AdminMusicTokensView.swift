import SetuIOSCore
import SwiftUI

struct AdminMusicTokensView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[NeteaseToken]> = .idle
    @State private var checkResults: [Int: NeteaseTokenCheckResult] = [:]
    @State private var checkingIDs: Set<Int> = []
    @State private var probeSongID = "32358362"
    @State private var editor: TokenEditor?
    @State private var message: String?
    @State private var isSubmitting = false

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminMusicTokenStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后管理网易云 Token。", systemImage: "shield.slash")
            } else {
                controlSection
                if let message {
                    SetuCard {
                        Label(message, systemImage: "checkmark.circle")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                tokenSection
            }
        }
        .setuBackground()
        .navigationTitle("网易云 Token")
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
        .toolbar {
            Button {
                editor = TokenEditor()
            } label: {
                Label("添加", systemImage: "plus")
            }
        }
        .sheet(item: $editor) { editor in
            TokenEditorSheet(editor: editor, isSubmitting: isSubmitting) { draft in
                Task { await save(draft) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var controlSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "检测")
            TextField("VIP 测试歌曲 ID", text: $probeSongID)
                    .textFieldStyle(.roundedBorder)
            Text("默认使用 32358362，并以 exhigh 音质检测 Cookie 登录态和完整可播性。")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }

    }

    @ViewBuilder
    private var tokenSection: some View {
        switch state {
        case .idle, .loading:
            AdminMusicTokenStateSection(title: "Token 列表", stateTitle: "正在加载 Token", systemImage: "music.note.list", isLoading: true)
        case .failed(let message):
            AdminMusicTokenStateSection(title: "Token 列表", stateTitle: "Token 加载失败", message: message, systemImage: "music.note.list")
        case .loaded(let tokens):
            if tokens.isEmpty {
                AdminMusicTokenStateSection(title: "Token 列表", stateTitle: "暂无 Token", message: "添加网易云 Cookie 后即可用于代理音乐服务。", systemImage: "music.mic")
            } else {
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "Token 列表", subtitle: "\(tokens.count) 个")
                        SetuRecordBoard(items: tokens) { token in
                            TokenRow(
                                token: token,
                                checkResult: checkResults[token.id],
                                isChecking: checkingIDs.contains(token.id),
                                onToggle: { pendingActionTitle = "确认更改 Token 启用状态？"; pendingAction = { Task { await toggle(token) } } },
                                onCheck: { Task { await check(token) } },
                                onEdit: { editor = TokenEditor(token: token) },
                                onDelete: { pendingActionTitle = "确认删除此音乐 Token？"; pendingAction = { Task { await delete(token) } } }
                            )
                        }
                    }
                }

            }
        }
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.neteaseTokens())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func save(_ draft: TokenEditor) async {
        let cookie = draft.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = draft.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else {
            message = "请填写 Cookie"
            return
        }
        isSubmitting = true
        message = nil
        do {
            if let id = draft.id {
                try await environment.adminClient.updateNeteaseToken(
                    id: id,
                    cookie: cookie,
                    nickname: nickname.isEmpty ? nil : nickname,
                    status: draft.status
                )
                message = "Token 已更新"
            } else {
                let name = nickname.isEmpty ? "未命名账号" : nickname
                _ = try await environment.adminClient.addNeteaseToken(cookie: cookie, nickname: name)
                message = "Token 已添加"
            }
            editor = nil
            await load()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func toggle(_ token: NeteaseToken) async {
        message = nil
        do {
            try await environment.adminClient.updateNeteaseToken(id: token.id, status: token.status == 1 ? 0 : 1)
            message = "状态已更新"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func check(_ token: NeteaseToken) async {
        checkingIDs.insert(token.id)
        message = nil
        do {
            let probe = probeSongID.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await environment.adminClient.checkNeteaseToken(
                id: token.id,
                probeSongID: probe.isEmpty ? "32358362" : probe
            )
            checkResults[token.id] = result
            message = result.reason
        } catch {
            message = error.localizedDescription
        }
        checkingIDs.remove(token.id)
    }

    private func delete(_ token: NeteaseToken) async {
        message = nil
        do {
            try await environment.adminClient.deleteNeteaseToken(id: token.id)
            message = "Token「\(token.nickname)」已删除"
            checkResults[token.id] = nil
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct TokenRow: View {
    let token: NeteaseToken
    let checkResult: NeteaseTokenCheckResult?
    let isChecking: Bool
    let onToggle: () -> Void
    let onCheck: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SetuRecordCard(headline: token.nickname.isEmpty ? "Token #\(token.id)" : token.nickname,
            status: .init(token.statusTitle, tone: token.status == 1 ? .success : .muted),
            fields: [.init("ID", "\(token.id)"), .init("Cookie", token.maskedCookie),
                     .init("创建时间", token.createdAt ?? "-"), .init("更新时间", token.updatedAt ?? "-")], density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                if let checkResult {
                    SetuPill(text: checkResult.label, tone: checkResult.cookieValid ? .success : .danger)
                    Text(checkResult.reason).font(SetuTypography.caption)
                } else {
                    Text("点击检测确认 Cookie 与 VIP 歌曲可播性").font(SetuTypography.caption)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { tokenActions }
                    VStack(alignment: .leading) { tokenActions }
                }
            }
        }
    }
    @ViewBuilder private var tokenActions: some View {
        Button(token.status == 1 ? "禁用" : "启用", action: onToggle).frame(minHeight: 44)
        Button(isChecking ? "检测中" : "检测", action: onCheck).frame(minHeight: 44).disabled(isChecking)
        Button("编辑", action: onEdit).frame(minHeight: 44)
        Button("删除", role: .destructive, action: onDelete).frame(minHeight: 44)
    }

}

private struct TokenEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var editor: TokenEditor
    let isSubmitting: Bool
    let onSave: (TokenEditor) -> Void

    var body: some View {
        NavigationStack {
            SetuBoard {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "Cookie")
                    TextEditor(text: $editor.cookie)
                        .frame(minHeight: 140)
                            .padding(SetuSpacing.xs)
                            .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                    Text("请粘贴完整网易云 Cookie，例如 MUSIC_U=...; __csrf=...")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                }
                }

                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "信息")
                    TextField("昵称", text: $editor.nickname)
                            .textFieldStyle(.roundedBorder)
                    SetuFilterBar(options: [
                    .init(value: 1, title: "启用"),
                    .init(value: 0, title: "禁用")
                ], selection: $editor.status, accessibilityTitle: "状态")

                }
                }

            }
            .setuBackground()
            .navigationTitle(editor.id == nil ? "添加 Token" : "编辑 Token")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(editor)
                    } label: {
                        Text(isSubmitting ? "保存中" : "保存")
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}

private typealias AdminMusicTokenStateSection = AdminRecordStateSection

private struct TokenEditor: Identifiable {
    let id: Int?
    var cookie: String
    var nickname: String
    var status: Int

    init(id: Int? = nil, cookie: String = "", nickname: String = "", status: Int = 1) {
        self.id = id
        self.cookie = cookie
        self.nickname = nickname
        self.status = status
    }

    init(token: NeteaseToken) {
        self.id = token.id
        self.cookie = token.cookie
        self.nickname = token.nickname
        self.status = token.status
    }
}
