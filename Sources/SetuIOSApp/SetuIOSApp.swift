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
        _environment = State(initialValue: environment)
        _pushNotifications = State(initialValue: SystemPushCoordinator(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootAppView(environment: environment, pushNotifications: pushNotifications)
                .task { pushNotifications.configure() }
        }
    }
}
