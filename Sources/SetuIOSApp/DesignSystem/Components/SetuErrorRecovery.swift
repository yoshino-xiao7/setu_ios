import SetuIOSCore
import SwiftUI

struct SetuRecoveryActions {
    var signIn: (() -> Void)?
    var goBack: (() -> Void)?
    var viewPoints: (() -> Void)?
    var retry: (() -> Void)?

    func action(for action: UserFacingErrorAction?) -> (() -> Void)? {
        switch action {
        case .signIn: signIn
        case .goBack: goBack
        case .viewPoints: viewPoints
        case .retry, .refresh, .wait: retry
        case .reviewInput, nil: nil
        }
    }
}

private struct SetuRecoveryActionsKey: EnvironmentKey {
    static let defaultValue = SetuRecoveryActions()
}

extension EnvironmentValues {
    var setuRecoveryActions: SetuRecoveryActions {
        get { self[SetuRecoveryActionsKey.self] }
        set { self[SetuRecoveryActionsKey.self] = newValue }
    }
}

extension View {
    func setuRefreshAfterLogin(_ session: AuthSession, action: @escaping () -> Void) -> some View {
        onChange(of: session.requiresReauthentication) { wasRequired, required in
            if wasRequired && !required && session.isSignedIn { action() }
        }
    }

    /// Only supply a safe reload here. Mutations require their own explicit confirmation.
    func setuRetry(_ action: @escaping () -> Void) -> some View {
        transformEnvironment(\.setuRecoveryActions) { $0.retry = action }
    }
}

struct SetuErrorRecoveryButton: View {
    @Environment(\.setuRecoveryActions) private var recovery
    let error: UserFacingError
    var retry: (() -> Void)?

    var body: some View {
        let localRetry = [UserFacingErrorAction.retry, .refresh, .wait].contains(error.action ?? .reviewInput) ? retry : nil
        if let action = localRetry ?? recovery.action(for: error.action), let kind = error.action {
            Button(kind.buttonTitle, action: action)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
    }
}
