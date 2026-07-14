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
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-public-ai-work")
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
        RootAppView(environment: environment, pushNotifications: pushNotifications)
            .task { pushNotifications.configure() }
    }
}
