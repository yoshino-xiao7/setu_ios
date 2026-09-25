import SetuIOSCore
import SwiftUI

struct NeteaseAccountCard: View {
    @Bindable var environment: AppEnvironment
    @State private var showingLoginSheet = false
    @State private var showingLogoutConfirmation = false
    @State private var showingContributeConfirmation = false
    @State private var isContributing = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        VStack(spacing: SetuSpacing.xs) {
            if let feedback {
                SetuFeedbackBanner(feedback: feedback)
                    .transition(.opacity)
            }

            SetuCard {
                if environment.neteaseMusicSession.isLoggedIn, let profile = environment.neteaseMusicSession.profile {
                    loggedInContent(profile: profile)
                } else {
                    loggedOutContent
                }
            }
        }
        .sheet(isPresented: $showingLoginSheet) {
            NeteaseLoginSheet(environment: environment)
        }
        .confirmationDialog("退出网易云音乐登录？", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                environment.neteaseMusicSession.logout()
                feedback = .info("已退出网易云账号")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后将无法继续同步个人网易云歌单及解析 VIP 音质。")
        }
        .confirmationDialog("自愿贡献 Token 助力全站曲库？", isPresented: $showingContributeConfirmation, titleVisibility: .visible) {
            Button("确认贡献") {
                Task { await contributeToken() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向亦可全站公共音源号池提交您的网易云凭证，由管理员审核后加入，帮助更多小伙伴解析高品质音乐。感谢您的无私奉献！")
        }
    }

    // MARK: - Logged In View

    private func loggedInContent(profile: NeteaseUserProfile) -> some View {
        HStack(spacing: SetuSpacing.md) {
            if let avatarUrl = profile.avatarUrl {
                MusicArtworkView(urlString: avatarUrl)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(SetuColor.separator, lineWidth: 1))
            } else {
                Circle()
                    .fill(SetuColor.brandPink.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(SetuColor.brandPink)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: SetuSpacing.xs) {
                    Text(profile.nickname)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(1)

                    if profile.isVIP {
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("VIP")
                                .font(.system(size: 10, weight: .black))
                        }
                        .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.2))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                                .overlay(
                                    Capsule().strokeBorder(Color(red: 0.95, green: 0.75, blue: 0.2).opacity(0.4), lineWidth: 0.8)
                                )
                        )
                    }
                }

                HStack(spacing: SetuSpacing.sm) {
                    Text("UID: \(profile.userId)")
                        .font(.caption2)
                        .foregroundStyle(SetuColor.textTertiary)

                    Text("·")
                        .foregroundStyle(SetuColor.textTertiary)

                    Text("\(environment.neteaseMusicSession.playlists.count) 个歌单")
                        .font(.caption2)
                        .foregroundStyle(SetuColor.textSecondary)
                }
            }

            Spacer()

            Menu {
                Button {
                    Task {
                        await environment.neteaseMusicSession.refreshProfileAndPlaylists()
                        feedback = .success("歌单已刷新")
                    }
                } label: {
                    Label("刷新歌单", systemImage: "arrow.clockwise")
                }

                Button {
                    showingContributeConfirmation = true
                } label: {
                    Label("贡献 Token 助力曲库", systemImage: "heart.circle")
                }

                Divider()

                Button(role: .destructive) {
                    showingLogoutConfirmation = true
                } label: {
                    Label("退出网易云", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Logged Out View

    private var loggedOutContent: some View {
        HStack(spacing: SetuSpacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.95, green: 0.25, blue: 0.35), Color(red: 0.85, green: 0.15, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("网易云音乐授权")
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)

                Text("绑定网易云账号，同步歌单与 VIP 音质")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showingLoginSheet = true
            } label: {
                Text("立即绑定")
                    .font(SetuTypography.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, SetuSpacing.sm)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(SetuColor.brandPink)
        }
    }

    // MARK: - Actions

    private func contributeToken() async {
        isContributing = true
        defer { isContributing = false }
        do {
            let message = try await environment.neteaseMusicSession.contributeToken(using: environment.musicClient)
            feedback = .success(message)
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
