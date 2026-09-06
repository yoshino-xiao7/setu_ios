import XCTest

/// Phase 10 offline surface coverage. Run this test independently for each
/// device / text-size / color-mode combination; one run does not prove the matrix.
final class SakuraAdminSurfaceUITests: XCTestCase {
    private struct Page {
        let name: String
        let loading: String
        let empty: String
        let loaded: String
    }

    private let pages: [Page] = [
        .init(name: "Overview", loading: "正在加载后台概览", empty: "图片 API 总调用", loaded: "图片 API 总调用"),
        .init(name: "Users", loading: "正在加载用户", empty: "暂无用户", loaded: "樱潮测试用户"),
        .init(name: "Blacklist", loading: "正在加载黑名单", empty: "暂无封禁记录", loaded: "192.0.2.10"),
        .init(name: "MusicTokens", loading: "正在加载 Token", empty: "暂无 Token", loaded: "樱潮测试 Token"),
        .init(name: "OperationLogs", loading: "正在加载操作日志", empty: "暂无日志", loaded: "樱潮测试操作"),
        .init(name: "PixivCrawl", loading: "正在加载任务", empty: "暂无任务", loaded: "fixture-task"),
        .init(name: "ImageAudit", loading: "正在加载图片库", empty: "暂无图片", loaded: "樱潮测试插画"),
        .init(name: "GallerySubmissions", loading: "正在加载投稿批次", empty: "暂无投稿批次", loaded: "樱潮测试投稿"),
        .init(name: "ImageDeleteRequests", loading: "正在加载删除申请", empty: "暂无申请", loaded: "樱潮测试删除申请"),
        .init(name: "ImageInfo", loading: "正在加载图片详情", empty: "输入 PID 查询", loaded: "樱潮测试插画"),
        .init(name: "AiGenerations", loading: "正在加载 AI 生成记录", empty: "暂无 AI 生成记录", loaded: "樱潮测试作品"),
        .init(name: "AiReviews", loading: "正在加载 AI 审核队列", empty: "暂无审核任务", loaded: "樱潮测试作品"),
        .init(name: "AiDeleteRequests", loading: "正在加载 AI 删除申请", empty: "暂无 AI 删除申请", loaded: "樱潮测试删除原因"),
        .init(name: "AiWorkers", loading: "正在加载 AI Worker 状态", empty: "暂无 Worker 心跳", loaded: "樱潮测试节点")
    ]

    func testAdminLightDefault() throws { try run(colorScheme: "Light", textSize: "UICTContentSizeCategoryL") }
    func testAdminDarkDefault() throws { try run(colorScheme: "Dark", textSize: "UICTContentSizeCategoryL") }
    func testAdminLightAX1() throws { try run(colorScheme: "Light", textSize: "UICTContentSizeCategoryAccessibilityM") }
    func testAdminDarkAX1() throws { try run(colorScheme: "Dark", textSize: "UICTContentSizeCategoryAccessibilityM") }
    func testAdminLightAX5() throws { try run(colorScheme: "Light", textSize: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAdminDarkAX5() throws { try run(colorScheme: "Dark", textSize: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testAdminOverviewStates() throws { try run(colorScheme: "Light", textSize: "UICTContentSizeCategoryL", overviewOnly: true) }
    func testAdminRemainingLightDefault() throws { try run(colorScheme: "Light", textSize: "UICTContentSizeCategoryL", startingAt: 8) }

    private func run(colorScheme: String, textSize: String, overviewOnly: Bool = false, startingAt: Int = 0) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-sakura-admin", "-UIPreferredContentSizeCategoryName", textSize, colorScheme,
                               "-sakura-admin-start-page", String(startingAt)]
        app.launch()
        let manifest = app.descendants(matching: .any)["sakura.admin.dtoEvidence"].firstMatch
        XCTAssertTrue(manifest.waitForExistence(timeout: 10))
        XCTAssertEqual(manifest.label.components(separatedBy: "\n").count, 19)
        let decoded = XCTAttachment(string: manifest.label)
        decoded.name = "admin-fixture-dto-decoding"
        decoded.lifetime = .keepAlways
        add(decoded)

        for page in pages.dropFirst(startingAt).prefix(overviewOnly ? 1 : pages.count) {
            // LoadState.failed(String) creates UserFacingError(title: "加载失败").
            // SetuEmptyState's error overload displays that title instead of the
            // page-specific fallback; match the actual visible error semantics.
            let cases = [("loading", page.loading), ("empty", page.empty), ("failed", "加载失败"), ("loaded", page.loaded)]
            for (state, expected) in cases {
                let semanticState = page.name == "Overview" && state == "empty" ? "zero-statistics" :
                    page.name == "ImageInfo" && state == "empty" ? "idle-query" : state
                let name = "admin-\(page.name)-\(semanticState)"
                try XCTContext.runActivity(named: name) { _ in
                    let current = app.staticTexts["sakura.admin.current"]
                    let selection = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "label == %@", "\(page.name) / \(state)"), object: current)
                    XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 10), .completed)

                    let target = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
                    let board = app.scrollViews.firstMatch
                    // Allow the private asynchronous transport to publish the
                    // requested state before scrolling past its initial position.
                    _ = target.waitForExistence(timeout: 8)
                    var scrollCount = 0
                    for _ in 0..<18 {
                        if target.exists && target.isHittable { break }
                        board.swipeUp()
                        scrollCount += 1
                    }
                    capture(app, name: "\(name)-state")
                    if !target.exists || !target.isHittable {
                        let hierarchy = XCTAttachment(string: app.debugDescription)
                        hierarchy.name = "\(name)-hierarchy"
                        hierarchy.lifetime = .keepAlways
                        add(hierarchy)
                    }
                    XCTAssertTrue(target.exists && target.isHittable, "\(name): missing actual page state: \(expected)")
                    try SakuraSurfaceAudit.perform(in: app, test: self, name: "\(name)-state", target: target)
                    if page.name == "Overview", state == "empty" {
                        XCTAssertTrue(target.label.contains("0"), "Overview empty means real zero-valued statistics, not an empty collection")
                    }
                    // Return to the top only after the actual state was observed.
                    // The explicit test control strip consumes 44pt of vertical space.
                    for _ in 0..<scrollCount { board.swipeDown() }
                    capture(app, name: "\(name)-top")
                    try SakuraSurfaceAudit.perform(in: app, test: self, name: "\(name)-top")
                    // Capture remaining page content without triggering an action.
                    if state == "loaded" {
                        for step in 1...4 {
                            board.swipeUp()
                            capture(app, name: "\(name)-scroll-\(step)")
                            try SakuraSurfaceAudit.perform(in: app, test: self, name: "\(name)-scroll-\(step)")
                        }
                    }
                    app.buttons["sakura.admin.next"].tap()
                }
            }
        }
        app.terminate()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
