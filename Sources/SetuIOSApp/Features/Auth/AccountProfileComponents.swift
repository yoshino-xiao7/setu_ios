import SetuIOSCore
import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


struct AccountProfileCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let user: CurrentUser
    let onEditProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        AccountAvatarView(urlString: user.avatarUrl, name: displayName)
                        profileText
                    }
                } else {
                    HStack(spacing: 14) {
                        AccountAvatarView(urlString: user.avatarUrl, name: displayName)
                        profileText
                    }
                }
            }

            Button(action: onEditProfile) {
                Label("完善个人资料", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var profileText: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if user.role == .admin {
                    Text("管理员")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SetuColor.warning.opacity(0.14), in: Capsule())
                        .foregroundStyle(SetuColor.warningForeground)
                }
            }
            Text(user.email)
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if user.lastLoginIp?.isEmpty == false {
                Text("最近登录已记录")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textTertiary)
            }
        }
    }

    private var displayName: String {
        let trimmed = user.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? user.email : trimmed
    }

}

struct AccountAvatarView: View {
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
        .frame(width: 62, height: 62)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Circle()
            .fill(SetuColor.brandSoft.opacity(0.18))
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
            }
    }
}

struct EmailInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        content
        #endif
    }
}

struct AuthButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String?

    init(_ title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}

struct AuthLinkButtonLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

enum AuthCaptchaKind {
    case login
    case register
    case recovery
}
