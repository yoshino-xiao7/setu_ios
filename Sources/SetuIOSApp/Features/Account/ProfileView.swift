import SetuIOSCore
import SwiftUI

struct ProfileView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<UserProfile> = .idle
    @State private var nickname = ""
    @State private var message: String?

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("资料加载失败", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(message))
            case .loaded(let profile):
                Section {
                    HStack(spacing: 14) {
                        AvatarView(urlString: profile.avatarUrl, name: profile.displayName)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(.headline)
                            Text(profile.email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("账号") {
                    LabeledContent("用户 ID", value: "\(profile.id)")
                    LabeledContent("角色", value: profile.role == .admin ? "管理员" : "用户")
                    LabeledContent("注册时间", value: profile.createdAt)
                    if let lastLoginIp = profile.lastLoginIp, !lastLoginIp.isEmpty {
                        LabeledContent("最近登录 IP", value: lastLoginIp)
                    }
                }

                Section("昵称") {
                    TextField("昵称", text: $nickname)
                    Button("保存昵称") {
                        Task { await saveNickname() }
                    }
                    .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("个人中心")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            let profile = try await environment.userProfileClient.getUserInfo()
            nickname = profile.nickname ?? ""
            state = .loaded(profile)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func saveNickname() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await environment.userProfileClient.updateNickname(trimmed)
            message = "昵称已更新"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct AvatarView: View {
    let urlString: String?
    let name: String

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(.pink.opacity(0.14))
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.pink)
            }
    }
}
