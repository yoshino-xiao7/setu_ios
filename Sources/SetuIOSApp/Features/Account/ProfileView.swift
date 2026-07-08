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
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载资料", systemImage: "person.crop.circle", isLoading: true)
                    }
                }
                .setuListRow()
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "资料加载失败", message: message, systemImage: "person.crop.circle.badge.exclamationmark")
                    }
                }
                .setuListRow()
            case .loaded(let profile):
                Section {
                    SetuCard(padding: SetuSpacing.xl) {
                        HStack(spacing: SetuSpacing.lg) {
                            AvatarView(urlString: profile.avatarUrl, name: profile.displayName)
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text(profile.displayName)
                                    .font(SetuTypography.title)
                                    .foregroundStyle(SetuColor.textPrimary)
                                Text(profile.email)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                                SetuPill(text: profile.role == .admin ? "管理员" : "用户", systemImage: "person.crop.circle.fill", tone: .brand)
                            }
                        }

                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            if isUploadingAvatar {
                                ProgressView()
                                    .tint(SetuColor.brandPink)
                            } else {
                                Label("更换头像", systemImage: "photo.badge.plus")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(SetuColor.brandPink)
                        .disabled(isUploadingAvatar)
                        .padding(.top, SetuSpacing.md)
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "账号")
                            LabeledContent("用户 ID", value: "\(profile.id)")
                            LabeledContent("角色", value: profile.role == .admin ? "管理员" : "用户")
                            LabeledContent("注册时间", value: profile.createdAt)
                            if profile.lastLoginIp?.isEmpty == false {
                                LabeledContent("最近登录", value: "已记录")
                            }
                        }
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "昵称")
                            TextField("昵称", text: $nickname)
                                .textFieldStyle(.roundedBorder)
                            SetuPrimaryButton {
                                Task { await saveNickname() }
                            } label: {
                                Label("保存昵称", systemImage: "checkmark.circle")
                            }
                            .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .setuListRow()
            }

            if let message {
                Section {
                    SetuPill(text: message, systemImage: "checkmark.circle", tone: .brand)
                }
                .setuListRow()
            }
        }
        .listStyle(.plain)
        .setuBackground()
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
            try? environment.authSession.applyUserProfile(profile)
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
            .fill(SetuColor.brandSoft.opacity(0.22))
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
            }
    }
}
