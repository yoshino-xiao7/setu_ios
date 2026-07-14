import XCTest
@testable import SetuIOSApp

@MainActor
final class AppNavigationCoordinatorTests: XCTestCase {
    func testCrossTabNavigationSelectsTargetWithoutPollutingSourceStack() {
        let coordinator = AppNavigationCoordinator()
        coordinator.router(for: .home).navigate(to: .notifications)

        coordinator.navigate(to: .music, route: .musicHistory)

        XCTAssertEqual(coordinator.selectedTab, .music)
        XCTAssertEqual(coordinator.router(for: .music).path, [.musicHistory])
        XCTAssertEqual(coordinator.router(for: .home).path, [.notifications])
    }

    func testResetClearsOnlyTargetStackBeforePushingDestination() {
        let coordinator = AppNavigationCoordinator()
        coordinator.router(for: .home).navigate(to: .account)
        coordinator.router(for: .ai).navigate(to: .aiHistory)

        coordinator.navigate(to: .ai, route: .aiDraw, reset: true)

        XCTAssertEqual(coordinator.selectedTab, .ai)
        XCTAssertEqual(coordinator.router(for: .ai).path, [.aiDraw])
        XCTAssertEqual(coordinator.router(for: .home).path, [.account])
    }
}
