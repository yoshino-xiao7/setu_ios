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

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后管理网易云 Token。"))
            } else {
                controlSection
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                tokenSection
            }
        }
        .navigationTitle("网易云 Token")
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
        Section("检测") {
            TextField("VIP 测试歌曲 ID", text: $probeSongID)
            Text("默认使用 32358362，并以 exhigh 音质检测 Cookie 登录态和完整可播性。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tokenSection: some View {
        Section("Token 列表") {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载 Token")
            case .failed(let message):
                ContentUnavailableView("Token 加载失败", systemImage: "music.note.list", description: Text(message))
            case .loaded(let tokens):
                if tokens.isEmpty {
                    ContentUnavailableView("暂无 Token", systemImage: "music.mic", description: Text("添加网易云 Cookie 后即可用于代理音乐服务。"))
                } else {
                    ForEach(tokens) { token in
                        TokenRow(
                            token: token,
                            checkResult: checkResults[token.id],
                            isChecking: checkingIDs.contains(token.id),
                            onToggle: { Task { await toggle(token) } },
                            onCheck: { Task { await check(token) } },
                            onEdit: { editor = TokenEditor(token: token) },
                            onDelete: { Task { await delete(token) } }
                        )
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(token.nickname.isEmpty ? "Token #\(token.id)" : token.nickname)
                        .font(.headline)
                    Text("#\(token.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(token.statusTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((token.status == 1 ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
                    .foregroundStyle(token.status == 1 ? .green : .secondary)
            }

            Text(token.maskedCookie)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            if let checkResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(checkResult.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(checkResult.cookieValid ? .green : .red)
                    Text(checkResult.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("点击检测确认 Cookie 与 VIP 歌曲可播性")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(token.status == 1 ? "禁用" : "启用", action: onToggle)
                Button {
                    onCheck()
                } label: {
                    if isChecking {
                        ProgressView()
                    } else {
                        Text("检测")
                    }
                }
                Button("编辑", action: onEdit)
                Spacer()
                Button("删除", role: .destructive, action: onDelete)
            }
            .buttonStyle(.borderless)

            HStack(spacing: 12) {
                if let createdAt = token.createdAt {
                    Label(createdAt, systemImage: "calendar")
                }
                if let updatedAt = token.updatedAt {
                    Label(updatedAt, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TokenEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var editor: TokenEditor
    let isSubmitting: Bool
    let onSave: (TokenEditor) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Cookie") {
                    TextEditor(text: $editor.cookie)
                        .frame(minHeight: 140)
                    Text("请粘贴完整网易云 Cookie，例如 MUSIC_U=...; __csrf=...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("信息") {
                    TextField("昵称", text: $editor.nickname)
                    Picker("状态", selection: $editor.status) {
                        Text("启用").tag(1)
                        Text("禁用").tag(0)
                    }
                }
            }
            .navigationTitle(editor.id == nil ? "添加 Token" : "编辑 Token")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(editor)
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}

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
