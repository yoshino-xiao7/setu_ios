import XCTest

final class AdminInteractionUITests: XCTestCase {
    private func launch(audit: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [audit ? "-ui-testing-root-admin-audit" : "-ui-testing-root-admin",
                               "-ui-testing-artwork-admin", "-ui-testing-admin-interactions"]
        app.launch()
        // The destination exists behind the welcome overlay before it accepts touches.
        XCTAssertTrue(app.tabBars.buttons["首页"].wait(for: \.isHittable, toEqual: true, timeout: 20))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            let bottom = app.keyboards.firstMatch.exists
                ? app.keyboards.firstMatch.frame.minY - 8
                : app.tabBars.firstMatch.frame.minY - 8
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
                // isHittable can be true for a sliver of a button underneath a navigation/tab bar.
                let middle = (top + bottom) / 2
                let maxDistance = (bottom - top) * 0.4
                let distance = max(-maxDistance, min(maxDistance, frame.midY - middle))
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: app.frame.midX, dy: middle))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: middle - distance)))
            } else if up {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
    }

    func testOverviewReturnKeepsStatisticsUntilExplicitRefresh() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["后台概览"].waitForExistence(timeout: 15))
        let initial = app.descendants(matching: .any)["admin-overview-updated-at"].firstMatch
        reveal(initial, in: app)
        XCTAssertEqual(initial.value as? String, "统计请求 1")
        let entry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "图片审核与详情")).firstMatch
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["图片库管理"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(initial, in: app, up: false)
        XCTAssertEqual(initial.value as? String, "统计请求 1", "Returning must not request statistics again")
        let sync = app.buttons["同步图库统计"]
        reveal(sync, in: app)
        sync.tap()
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "统计请求 2"), object: initial)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed)
    }

    func testQueryDoesNotTriggerReset() {
        let app = launch(audit: true)
        let field = app.textFields["PID"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        // Use a physical tap: Xcode 27 sometimes reports a (-1, -1) accessibility hit point.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        field.typeText("1001")
        // Scroll to the query action while preserving the entered PID.
        app.swipeUp()
        let query = app.buttons["查询"]
        reveal(query, in: app, up: false)
        query.tap()
        XCTAssertFalse(app.buttons["疑似失效"].isHittable, "Query must not open the availability picker in the same List row")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "admin-audit-query-hit-target"; shot.lifetime = .keepAlways; add(shot)
        reveal(field, in: app, up: false)
        XCTAssertEqual(field.value as? String, "1001", "Query must not also invoke the reset button in its List row")
    }

    func testSelectPageDoesNotClearSelectionOrOpenProblemSheet() {
        let app = launch(audit: true)
        let select = app.buttons["选择当前页"]
        XCTAssertTrue(select.waitForExistence(timeout: 15))
        reveal(select, in: app)
        select.tap()
        XCTAssertTrue(app.buttons["取消全选"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["2 / 2"].exists)
        XCTAssertFalse(app.navigationBars["批量标记为有问题"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "admin-audit-bulk"; shot.lifetime = .keepAlways; add(shot)
    }

    func testImageActionsHaveIndependent44PointTargets() {
        checkImageActions(dark: false)
    }

    func testDarkImageActionsHaveIndependent44PointTargets() {
        checkImageActions(dark: true)
    }

    private func checkImageActions(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-admin-audit", "-ui-testing-artwork-admin", "-ui-testing-admin-interactions"]
        if dark { app.launchArguments.append("Dark") }
        app.launch()
        // The destination exists behind the welcome overlay before it accepts touches.
        XCTAssertTrue(app.tabBars.buttons["首页"].wait(for: \.isHittable, toEqual: true, timeout: 20))
        XCTAssertTrue(app.navigationBars["图片库管理"].waitForExistence(timeout: 15))
        let problem = app.buttons["admin-audit-problem-1"]
        reveal(problem, in: app)
        XCTAssertGreaterThanOrEqual(problem.frame.height, 44)
        XCTAssertGreaterThanOrEqual(problem.frame.width, 44)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = dark ? "admin-audit-actions-dark" : "admin-audit-actions-light"
        shot.lifetime = .keepAlways; add(shot)
        // Hit the padded edge, where a neighboring row or clipped image must not intercept.
        problem.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["标记为有问题"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1001_p0"].exists)
        XCTAssertFalse(app.staticTexts["1002_p0"].isHittable)
        app.buttons["取消"].tap()
        let check = app.buttons["admin-audit-check-1"]
        reveal(check, in: app)
        check.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let result = app.descendants(matching: .any)["admin-audit-message"].firstMatch
        reveal(result, in: app, up: false)
        XCTAssertTrue(result.exists, app.debugDescription)
        XCTAssertTrue(result.label.contains("可用性检测完成：成功 1，失败 0"), result.label)
        XCTAssertFalse(app.navigationBars["标记为有问题"].exists)
        let detail = app.buttons["admin-audit-detail-2"]
        reveal(detail, in: app)
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["图片详情"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["PID"].value as? String, "1002")
    }

}
