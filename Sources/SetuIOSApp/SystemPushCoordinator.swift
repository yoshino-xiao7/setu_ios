import SetuIOSCore
import Foundation
import Observation
#if os(iOS)
import UserNotifications
import UIKit
#endif

struct SystemPushDestination: Equatable {
    let type: String?
    let targetType: String?
    let targetID: Int?

    init(userInfo: [AnyHashable: Any]) {
        let nested = userInfo["data"] as? [String: Any]
        func value(_ key: String) -> Any? { nested?[key] ?? userInfo[key] }
        type = value("type") as? String
        targetType = value("targetType") as? String
        targetID = Self.integer(value("targetId"))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

#if os(iOS)
@MainActor
@Observable
final class SystemPushCoordinator: NSObject {
    private let environment: AppEnvironment
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var pendingDestination: SystemPushDestination?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        SetuAppDelegate.deviceTokenHandler = { [weak self] token in
            await self?.register(token: token)
        }
    }

    func enableForSignedInUser() async {
        guard environment.authSession.isSignedIn else { return }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                settings = await center.notificationSettings()
                authorizationStatus = settings.authorizationStatus
            } catch {
                return
            }
        }
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func consumePendingDestination() -> SystemPushDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    private func register(token: Data) async {
        guard environment.authSession.isSignedIn else { return }
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        guard !tokenString.isEmpty else { return }
        do {
            try environment.keychain.setString(tokenString, for: "apnsToken")
            let deviceID = try deviceIdentifier()
            _ = try await environment.mobileAppClient.registerApnsDevice(
                MobileDeviceRegistrationRequest(
                    deviceId: deviceID,
                    apnsToken: tokenString,
                    apnsEnvironment: Self.apnsEnvironment,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    osVersion: UIDevice.current.systemVersion,
                    model: UIDevice.current.model
                )
            )
        } catch {
            // Token 会在下次登录、启动或系统刷新时再次同步。
        }
    }

    private func deviceIdentifier() throws -> String {
        if let existing = try environment.keychain.string(for: "pushDeviceId"), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        try environment.keychain.setString(created, for: "pushDeviceId")
        return created
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        "SANDBOX"
        #else
        "PRODUCTION"
        #endif
    }
}

extension SystemPushCoordinator: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = SystemPushDestination(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { pendingDestination = destination }
    }
}

final class SetuAppDelegate: NSObject, UIApplicationDelegate {
    nonisolated(unsafe) static var deviceTokenHandler: (@MainActor @Sendable (Data) async -> Void)?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await Self.deviceTokenHandler?(deviceToken) }
    }
}
#else
@MainActor
@Observable
final class SystemPushCoordinator {
    var pendingDestination: SystemPushDestination?

    init(environment: AppEnvironment) {}
    func configure() {}
    func enableForSignedInUser() async {}
    func consumePendingDestination() -> SystemPushDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}
#endif
