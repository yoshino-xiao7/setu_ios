import SetuIOSCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
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
                        VStack(spacing: SetuSpacing.md) {
                            AvatarView(urlString: profile.avatarUrl, name: profile.displayName)
                            profileIdentity(profile)
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                HStack(spacing: SetuSpacing.sm) {
                                    if isUploadingAvatar { ProgressView() }
                                    Label(isUploadingAvatar ? "正在更换头像" : "更换头像", systemImage: "camera")
                                }
                                .font(SetuTypography.headline)
                                .frame(minHeight: 44)
                                .padding(.horizontal, SetuSpacing.lg)
                            }
                            .buttonStyle(.bordered)
                            .tint(SetuColor.brandPink)
                            .disabled(isUploadingAvatar)
                            .accessibilityIdentifier("profile.avatar.change")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "昵称")
                            Text("这个名字会展示在首页和你的作品中。")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                            TextField("填写昵称", text: $nickname)
                                .font(SetuTypography.body)
                                .padding(SetuSpacing.md)
                                .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.sm))
                                .accessibilityLabel("昵称")
                                .accessibilityIdentifier("profile.nickname")
                            SetuPrimaryButton {
                                Task { await saveNickname() }
                            } label: {
                                Label("保存昵称", systemImage: "checkmark")
                            }
                            .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("profile.nickname.save")
                        }
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                            SetuSectionHeader(title: "账号信息")
                            accountDetail("邮箱", value: profile.email, systemImage: "envelope")
                            Divider().overlay(SetuColor.separator)
                            accountDetail("注册时间", value: SetuDateFormatter.string(from: profile.createdAt, style: .full), systemImage: "calendar")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .setuFeedbackPresentation($feedback)
        .navigationTitle("个人资料")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedAvatarItem) {
            Task { await uploadSelectedAvatar() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func profileIdentity(_ profile: UserProfile) -> some View {
        VStack(spacing: SetuSpacing.sm) {
            Text(profile.displayName)
                .font(SetuTypography.title)
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if profile.role == .admin {
                SetuPill(text: "管理员", systemImage: "person.crop.circle.fill", tone: .brand)
            }
        }
    }

    private func accountDetail(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(SetuColor.brandPink)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(title)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Text(value)
                    .font(SetuTypography.body)
                    .foregroundStyle(SetuColor.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
            state = .failed(UserFacingErrorMapper.map(error))
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
            feedback = .error(UserFacingErrorMapper.map(error))
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
            feedback = .error(UserFacingErrorMapper.map(error))
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
        .frame(width: 88, height: 88)
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
