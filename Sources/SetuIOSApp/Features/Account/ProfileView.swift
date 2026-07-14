import SetuIOSCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<UserProfile> = .idle
    @State private var nickname = ""
    @State private var feedback: SetuFeedback?
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
                        SetuEmptyState(
                            title: "资料加载失败",
                            message: message,
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            actionTitle: "重试",
                            action: { Task { await load() } }
                        )
                    }
                }
                .setuListRow()
            case .loaded(let profile):
                Section {
                    SetuCard(padding: SetuSpacing.xl) {
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                    AvatarView(urlString: profile.avatarUrl, name: profile.displayName)
                                    profileIdentity(profile)
                                }
                            } else {
                                HStack(spacing: SetuSpacing.lg) {
                                    AvatarView(urlString: profile.avatarUrl, name: profile.displayName)
                                    profileIdentity(profile)
                                }
                            }
                        }

                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            if isUploadingAvatar {
                                HStack(spacing: SetuSpacing.sm) {
                                    ProgressView()
                                        .tint(SetuColor.brandPink)
                                    Text("正在更换头像")
                                }
                                .frame(minHeight: 44)
                            } else {
                                Label("更换头像", systemImage: "photo.badge.plus")
                                    .frame(minHeight: 44)
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
                            LabeledContent("注册时间", value: SetuDateFormatter.string(from: profile.createdAt, style: .full))
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

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
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

    private func profileIdentity(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(profile.displayName)
                .font(SetuTypography.title)
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            Text(profile.email)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            if profile.role == .admin {
                SetuPill(text: "管理员", systemImage: "person.crop.circle.fill", tone: .brand)
            }
        }
    }

    private func load() async {
        state = .loading
        feedback = nil
        do {
            let profile = try await environment.userProfileClient.getUserInfo()
            try? environment.authSession.applyUserProfile(profile)
            nickname = profile.nickname ?? ""
            state = .loaded(profile)
        } catch {
            state = .failed(UserFacingErrorMapper.map(error).message)
        }
    }

    private func saveNickname() async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await environment.userProfileClient.updateNickname(trimmed)
            await load()
            feedback = .success("昵称已更新")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func uploadSelectedAvatar() async {
        guard let selectedAvatarItem else { return }
        isUploadingAvatar = true
        feedback = nil
        defer {
            isUploadingAvatar = false
            self.selectedAvatarItem = nil
        }

        do {
            guard let data = try await selectedAvatarItem.loadTransferable(type: Data.self) else {
                feedback = .error("无法读取所选图片，请重新选择。")
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
            await load()
            feedback = .success("头像已更新")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
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
        .accessibilityHidden(true)
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
