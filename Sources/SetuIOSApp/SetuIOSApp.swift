import SetuIOSCore
import SwiftUI

@main
struct SetuIOSApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootAppView(environment: environment)
        }
    }
}
