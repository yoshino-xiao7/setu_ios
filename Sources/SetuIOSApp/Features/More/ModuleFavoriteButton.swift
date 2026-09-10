import SetuIOSCore
import SwiftUI

struct ModuleFavoriteButton: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let snapshot: ModuleFavoriteSnapshot
    var onChanged: ((Bool) -> Void)?

    @State private var isFavorite: Bool?
    @State private var isBusy = false
    @State private var stateVersion = 0
    @State private var feedback: SetuFeedback?

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Label(isFavorite == true ? "已收藏" : "收藏", systemImage: isFavorite == true ? "heart.fill" : "heart")
        }
        .disabled(isBusy)
        .accessibilityIdentifier("module.favorite.\(snapshot.module.rawValue).\(snapshot.externalId)")
        .task(id: identity) { await refresh() }
        .setuFeedbackPresentation($feedback)
    }

    private func refresh() async {
        stateVersion += 1
        let version = stateVersion
        let owner = identity
        isFavorite = nil
        guard environment.authSession.isSignedIn, !environment.authSession.requiresReauthentication else { return }
        do {
            let exists = try await environment.moduleFavoriteClient.exists(module: snapshot.module, externalId: snapshot.externalId)
            guard !Task.isCancelled, owner == identity, version == stateVersion else { return }
            isFavorite = exists
        } catch {
            // Unknown is distinct from not favorited; retry before deciding whether to add or remove.
        }
    }

    private func toggle() async {
        guard !isBusy else { return }
        guard environment.authSession.isSignedIn, !environment.authSession.requiresReauthentication else {
            router.navigate(to: .account)
            return
        }
        let owner = identity
        stateVersion += 1
        isBusy = true
        defer { isBusy = false }
        do {
            if isFavorite == nil {
                let exists = try await environment.moduleFavoriteClient.exists(module: snapshot.module, externalId: snapshot.externalId)
                guard owner == identity else { return }
                isFavorite = exists
            }
            if isFavorite == true {
                try await environment.moduleFavoriteClient.remove(module: snapshot.module, externalId: snapshot.externalId)
                guard owner == identity else { return }
                isFavorite = false
                onChanged?(false)
                feedback = .success("已取消收藏")
            } else {
                _ = try await environment.moduleFavoriteClient.add(snapshot)
                guard owner == identity else { return }
                isFavorite = true
                onChanged?(true)
                feedback = .success("已收藏到当前账号")
            }
        } catch {
            guard owner == identity else { return }
            feedback = .failure(UserFacingErrorMapper.map(error))
        }
    }

    private var identity: FavoriteIdentity {
        FavoriteIdentity(userID: environment.authSession.currentUser?.id,
                         requiresReauthentication: environment.authSession.requiresReauthentication,
                         module: snapshot.module, externalID: snapshot.externalId)
    }

    private struct FavoriteIdentity: Hashable {
        let userID: Int?
        let requiresReauthentication: Bool
        let module: ModuleFavoriteModule
        let externalID: String
    }
}
