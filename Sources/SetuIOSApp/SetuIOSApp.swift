import SetuIOSCore
import SwiftUI

@main
struct SetuIOSApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(SetuAppDelegate.self) private var appDelegate
    #endif
    @State private var environment: AppEnvironment
    @State private var pushNotifications: SystemPushCoordinator

    init() {
        let environment = AppEnvironment.live()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-session") {
            environment.authSession.resetLocalSession()
        }
        #endif
        _environment = State(initialValue: environment)
        _pushNotifications = State(initialValue: SystemPushCoordinator(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            appContent
                #if DEBUG
                .modifier(SetuUITestAppearance())
                #endif
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-p13-word-scroll") {
            SetuP13WordScrollScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-pixiv-image-speed-probe") {
            SetuPixivImageSpeedProbe()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-pixiv-api-probe") {
            SetuPixivAPIProbe()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-pixiv-token-probe") {
            SetuPixivTokenProbe()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-pixiv-login-probe") {
            SetuPixivLoginProbe(url: URL(string: "https://app-api.pixiv.net/web/v1/login?code_challenge=0123456789012345678901234567890123456789012AA&code_challenge_method=S256&client=pixiv-android")!, failed: { _ in }, codeReceived: { _ in })
        } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-testing-root") })
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-welcome-fixture") {
            SetuRootUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-public-ai-work")
            || ProcessInfo.processInfo.arguments.contains("-ui-testing-public-ai-work-detail-404") {
            SetuPublicAiWorkUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-random-image")
                    || ProcessInfo.processInfo.arguments.contains("-ui-testing-random-image-favorite-failure") {
            SetuRandomImageUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-draft") {
            SetuAiDraftUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-favorites") {
            SetuFavoriteListUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-notification-permission") {
            SetuNotificationPermissionUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-read-all-failure") {
            SetuNotificationsReadAllFailureUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-count-failure")
                    || ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-read-all-stale")
                    || ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-read-all-empty-page-stale") {
            SetuNotificationsReadAllFailureUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-daily-favorite-failure") {
            SetuDailyFavoriteFailureUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-points-favorite-failure") {
            SetuPointsFavoriteFailureUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-dashboard")
                    || ProcessInfo.processInfo.arguments.contains("-ui-testing-dashboard-failures") {
            SetuDashboardUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-security-failure") {
            SetuSecurityFailureUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-home") {
            SetuMusicHomeUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-collection-square") {
            SetuCollectionSquareUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-square-hub") {
            SetuSquareHubUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-ai-hub") {
            SetuAiHubUITestScenario()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-image-hub") {
            SetuImageHubUITestScenario()
        } else {
            liveContent
        }
        #else
        liveContent
        #endif
    }

    private var liveContent: some View {
        #if DEBUG
        let navigation = AppNavigationCoordinator()
        if ProcessInfo.processInfo.arguments.contains("-development-playback3-radio"),
           environment.config.apiBaseURL.absoluteString == "https://api.yukiryou.icu",
           environment.config.musicFeatureFlags.radioFMEnabled {
            navigation.navigate(to: .music, route: .radioFM)
        }
        return RootAppView(environment: environment, pushNotifications: pushNotifications, navigationCoordinator: navigation)
            .task { pushNotifications.configure() }
        #else
        return RootAppView(environment: environment, pushNotifications: pushNotifications)
            .task { pushNotifications.configure() }
        #endif
    }
}

#if DEBUG
/// Keep UI scenarios independent of the simulator's cached launch-time text settings.
private struct SetuUITestAppearance: ViewModifier {
    func body(content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("-ui-testing-") }) {
            let usesAX5 = arguments.contains("UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
                || arguments.contains("UICTContentSizeCategoryAccessibilityXXXL")
            content
                .dynamicTypeSize(usesAX5 ? .accessibility5 : .large)
                .preferredColorScheme(arguments.contains("-ui-testing-system-appearance") ? nil : (arguments.contains("Dark") ? .dark : .light))
        } else {
            content
        }
    }
}
#endif

#if DEBUG
private struct SetuPixivLoginProbe: View {
    let url: URL
    let failed: (String) -> Void
    let codeReceived: (String) -> Void
    var body: some View {
        #if os(iOS)
        PixivLoginWebView(url: url, failed: failed, codeReceived: codeReceived)
        #else
        Text("Requires iOS WebKit")
        #endif
    }
}
#endif

#if DEBUG
/// Public, unauthenticated API differential. Never opens the account Keychain.
private struct SetuPixivImageSpeedProbe: View {
    @State private var status = "正在检查公开图片下载"
    var body: some View {
        Text(status).task {
            let transport = PixivNativeHTTPTransport()
            var results: [String] = []
            for round in 1...2 {
                for variant: UInt8 in [0, 9] {
                    var request = PixivHTTPRequest(url: "https://i.pixiv.re/img-original/img/2025/05/15/00/08/58/130412285_p0.jpg")
                    request.headers = ["Referer": "https://www.pixiv.net/", "User-Agent": "PixivIOSApp/5.8.0"]
                    request.max_bytes = 2 * 1024 * 1024
                    request.public_image_probe = 0
                    if variant == 9 { request.image_mirror_host = "i.pixiv.re" }
                    let started = Date()
                    do {
                        let response = try await transport.send(request)
                        results.append("round=\(round) variant=\(variant) HTTP=\(response.status) bytes=\(response.data.count) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    } catch { results.append("round=\(round) variant=\(variant) failed ms=\(Int(Date().timeIntervalSince(started) * 1000))") }
                    status = results.joined(separator: "\n")
                    if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        try? status.write(to: directory.appendingPathComponent("pixiv-image-speed-probe.txt"), atomically: true, encoding: .utf8)
                    }
                }
            }
        }
    }
}

/// Credential-free public API comparison, independent of image diagnostics.
private struct SetuPixivAPIProbe: View {
    @State private var status = "正在检查公开作品接口"
    var body: some View {
        Text(status).task {
            var request = PixivHTTPRequest(url: "https://app-api.pixiv.net/v1/illust/recommended?filter=for_ios&include_ranking_label=true")
            request.headers = ["User-Agent": "PixivAndroidApp/5.0.155 (Android 10.0; Pixel C)",
                "App-OS": "Android", "App-OS-Version": "Android 10.0", "App-Version": "5.0.166"]
            var results: [String] = []
            let paths: [(String, any PixivHTTPTransport)] = [
                ("enhanced", PixivNativeHTTPTransport()), ("selected", PixivDirectHTTPTransport())]
            for (name, transport) in paths {
                do {
                    let response = try await transport.send(request)
                    results.append("\(name) public API HTTP \(response.status), JSON \(response.contentType.contains("application/json"))")
                } catch { results.append("\(name) public API connection failed") }
            }
            status = results.joined(separator: "\n")
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? status.write(to: directory.appendingPathComponent("pixiv-api-probe.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
}

/// One deliberately invalid, synthetic authorization code. No account or Keychain access.
private struct SetuPixivTokenProbe: View {
    @State private var status = "正在检查公开令牌接口"
    var body: some View {
        Text(status).task {
            let transport = PixivPublicProbeTransport()
            let client = PixivLocalClient(owner: "public-transport-probe", keychain: PixivProbeKeychain(), transport: transport)
            do {
                let session = try await client.authorize()
                _ = try await client.complete(sessionID: session.id, code: "setu-public-invalid-code")
            } catch { }
            status = await transport.summary
        }
    }
}
private actor PixivPublicProbeTransport: PixivHTTPTransport {
    var summary = "未完成公开接口检查"
    func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse {
        do {
            let result = try await PixivDirectHTTPTransport().send(request)
            summary = describe("selected", result)
            save()
            return result
        } catch {
            summary = "selected public OAuth transport failed"
            save()
            throw error
        }
    }
    private func save() {
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? summary.write(to: directory.appendingPathComponent("pixiv-token-probe.txt"), atomically: true, encoding: .utf8)
        }
    }
    private func describe(_ name: String, _ result: PixivHTTPResponse) -> String {
        // Fixed metadata only, never OAuth bodies, headers, account values or page text.
        let json = result.contentType.lowercased().contains("application/json")
        let body = String(decoding: result.data, as: UTF8.self).lowercased()
        let challenge = body.contains("cf-chl-") || body.contains("just a moment")
        let blocked = body.contains("已被阻止") || body.contains("your access has been blocked") || body.contains("access denied")
        return "\(name) public OAuth HTTP \(result.status), JSON \(json), challenge \(challenge), blocked \(blocked)"
    }
}
private struct PixivProbeKeychain: KeychainStoring {
    func string(for key: String) throws -> String? { nil }
    func setString(_ value: String, for key: String) throws { }
    func remove(_ key: String) throws { }
}
#endif
