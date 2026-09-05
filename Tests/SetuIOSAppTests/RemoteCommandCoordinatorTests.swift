import XCTest
@testable import SetuIOSApp

@MainActor
final class RemoteCommandCoordinatorTests: XCTestCase {
    func testInstallIsIdempotentAndPreviousCapabilityIsExplicit() {
        let coordinator = RemoteCommandCoordinator()
        let handlers = RemoteCommandCoordinator.Handlers(
            play: {}, pause: {}, toggle: {}, stop: {}, next: {}, previous: {}, seek: { _ in }
        )
        coordinator.install(handlers)
        coordinator.install(handlers)
        XCTAssertTrue(coordinator.isInstalled)
        coordinator.setPreviousEnabled(false)
        XCTAssertFalse(coordinator.previousEnabled)
        coordinator.uninstall()
        XCTAssertFalse(coordinator.isInstalled)
    }
}
