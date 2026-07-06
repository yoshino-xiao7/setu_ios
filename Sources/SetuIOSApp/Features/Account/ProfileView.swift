import SetuIOSCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<UserProfile> = .idle
    @State private var nickname = ""
    @State private var message: String?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false

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
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        if isUploadingAvatar {
                            ProgressView()
                        } else {
                            Label("更换头像", systemImage: "photo.badge.plus")
                        }
                    }
                    .disabled(isUploadingAvatar)
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
        .onChange(of: selectedAvatarItem) {
            Task { await uploadSelectedAvatar() }
        }
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

    private func uploadSelectedAvatar() async {
        guard let selectedAvatarItem else { return }
        isUploadingAvatar = true
        message = nil
        defer {
            isUploadingAvatar = false
            self.selectedAvatarItem = nil
        }

        do {
            guard let data = try await selectedAvatarItem.loadTransferable(type: Data.self) else {
                message = "无法读取所选图片"
                return
            }
            let contentType = selectedAvatarItem.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let fileExtension = contentType.preferredFilenameExtension ?? "jpg"
            let mimeType = contentType.preferredMIMEType ?? "image/jpeg"
            _ = try await environment.userProfileClient.uploadAvatarFile(
                data: data,
                fileName: "ios-avatar.\(fileExtension)",
                mimeType: mimeType
            )
            message = "头像已更新"
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
