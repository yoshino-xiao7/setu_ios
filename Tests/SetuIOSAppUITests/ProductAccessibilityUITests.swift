import XCTest

final class ProductAccessibilityUITests: XCTestCase {
    private enum ForwardScrollMode {
        case incremental
        case semantic
    }

    private struct Landmark {
        let identifier: String?
        let labelContains: String?

        init(identifier: String) {
            self.identifier = identifier
            labelContains = nil
        }

        init(labelContains: String) {
            identifier = nil
            self.labelContains = labelContains
        }

        var description: String {
            identifier ?? "label contains \(labelContains ?? "")"
        }
    }

    private struct LoggedInRoute {
        let title: String
        let launchArgument: String
        let rootIdentifier: String
        let readyIdentifier: String
        let landmarks: [Landmark]
        let forwardScrollMode: ForwardScrollMode
    }

    private let loggedInRoutes = [
        LoggedInRoute(
            title: "图片 Tab", launchArgument: "-ui-testing-root-images",
            rootIdentifier: "image.swipe.page", readyIdentifier: "image.unlock",
            landmarks: [], forwardScrollMode: .incremental
        ),
        LoggedInRoute(
            title: "AI 绘画 Tab", launchArgument: "-ui-testing-root-ai",
            rootIdentifier: "ai.draw.page", readyIdentifier: "ai.draw.prompt",
            landmarks: [], forwardScrollMode: .incremental
        ),
        LoggedInRoute(
            title: "首页",
            launchArgument: "-ui-testing-dashboard",
            rootIdentifier: "dashboard.page",
            readyIdentifier: "dashboard.favorite.901",
            landmarks: [Landmark(labelContains: "未读通知")],
            forwardScrollMode: .semantic
        ),
        LoggedInRoute(
            title: "音乐首页",
            launchArgument: "-ui-testing-music-home",
            rootIdentifier: "music.home.page",
            readyIdentifier: "music.history.7301",
            landmarks: [
                Landmark(identifier: "music.playlist.7402"),
                Landmark(identifier: "music.hot.0"),
            ],
            forwardScrollMode: .incremental
        ),
        LoggedInRoute(
            title: "收藏夹广场",
            launchArgument: "-ui-testing-collection-square",
            rootIdentifier: "collections.square.page",
            readyIdentifier: "collections.square.tile.801.open",
            landmarks: [Landmark(identifier: "collections.square.tile.804.open")],
            forwardScrollMode: .incremental
        ),
    ]

    func testTabRootsAndKeyboardAreDirectlyReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["image.unlock"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["image.unlock"].isHittable)
        app.tabBars.buttons["AI 绘画"].tap()
        let prompt = app.textFields["ai.draw.prompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        XCTAssertTrue(prompt.isHittable)
        XCTAssertTrue(app.buttons["ai.draw.generate"].isHittable)
        prompt.tap()
        let done = app.buttons["ai.draw.keyboard.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["ai.draw.generate"].isHittable)
        app.tabBars.buttons["首页"].tap()
        let bell = app.buttons["dashboard.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 8))
        bell.tap()
        XCTAssertTrue(anyElement(withIdentifier: "notifications.page", in: app).waitForExistence(timeout: 8))
    }

    func testLoggedInRoutesPassLightDefaultAccessibilityAudit() throws {
        try assertLoggedInRouteMatrix(extraLaunchArguments: [
            "-AppleInterfaceStyle",
            "Light",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryLarge",
        ])
    }

    func testLoggedInRoutesPassDarkAX5AccessibilityAudit() throws {
        try assertLoggedInRouteMatrix(extraLaunchArguments: [
            "-AppleInterfaceStyle",
            "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
    }

    func testDashboardFailuresRemainExplicitAndRetryable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-dashboard-failures",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        defer { app.terminate() }

        let root = anyElement(withIdentifier: "dashboard.page", in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 8), "未显示首页失败场景")

        let checks: [(retryIdentifier: String, falseHealthyText: String)] = [
            ("dashboard.retry.generation", "暂无进行中的内容"),
            ("dashboard.retry.favorites", "还没有收藏图片"),
            ("dashboard.retry.recommendation", "今天暂时没有推荐"),
            ("dashboard.retry.notifications", "暂时没有需要处理的事项"),
            ("dashboard.retry.points", "暂时没有需要处理的事项"),
        ]

        for check in checks {
            scrollUntilVisible(
                landmark: Landmark(identifier: check.retryIdentifier),
                in: app,
                pageRoot: root,
                forwardScrollMode: .semantic,
                maximumSwipes: 3
            )
            XCTAssertFalse(
                app.staticTexts[check.falseHealthyText].exists,
                "接口失败时不应显示健康/空状态：\(check.falseHealthyText)"
            )
        }

        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testSecuritySettingsDoesNotTreatUnknownAppleBindingAsUnbound() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-security-failure",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        defer { app.terminate() }

        let root = anyElement(withIdentifier: "security.page", in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 8), "未显示账号安全页")
        scrollUntilVisible(
            landmark: Landmark(identifier: "security.apple.binding.failed"),
            in: app,
            pageRoot: root,
            forwardScrollMode: .semantic,
            maximumSwipes: 12
        )

        XCTAssertFalse(app.buttons["绑定 Apple 账号"].exists, "状态未知时不应允许绑定")
        XCTAssertFalse(app.buttons["解除 Apple 绑定"].exists, "状态未知时不应允许解绑")
        XCTAssertTrue(app.buttons["重试"].isHittable, "失败态应提供可点击的原位重试")
        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testMarkAllReadFailurePreservesUnreadState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-notifications-read-all-failure"]
        app.launch()
        defer { app.terminate() }

        let root = anyElement(withIdentifier: "notifications.page", in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 8), "未显示通知中心")
        let markAllRead = app.buttons["notifications.mark-all-read"]
        XCTAssertTrue(markAllRead.waitForExistence(timeout: 8), "未显示全部已读操作")
        XCTAssertTrue(app.staticTexts["2 条未读"].waitForExistence(timeout: 8), "离线夹具未加载未读通知")

        markAllRead.tap()

        let feedback = anyElement(withIdentifier: "notifications.feedback", in: app)
        XCTAssertTrue(feedback.waitForExistence(timeout: 8), "批量已读失败后未显示错误反馈")
        XCTAssertTrue(app.staticTexts["2 条未读"].exists, "请求失败后不应清零未读数")
        XCTAssertTrue(app.navigationBars["通知中心 (2)"].exists, "请求失败后标题应保留未读数")
        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testUnreadCountFailureStaysUnknownWhileRowsRemainUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-notifications-count-failure"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["notifications.item.41"].waitForExistence(timeout: 8), "未加载通知列表")
        XCTAssertTrue(
            app.staticTexts["有未读通知 · 数量待同步"].waitForExistence(timeout: 8),
            "未读数量失败时不应伪装成 0"
        )
        XCTAssertTrue(app.buttons["notifications.mark-all-read"].isEnabled, "已有未读行时仍应允许全部已读")
        XCTAssertTrue(app.navigationBars["通知中心"].exists)
        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testMarkAllReadSuccessSurvivesStaleReload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-notifications-read-all-stale"]
        app.launch()
        defer { app.terminate() }

        let first = app.buttons["notifications.item.41"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "未加载通知列表")
        let markAllRead = app.buttons["notifications.mark-all-read"]
        XCTAssertTrue(markAllRead.isEnabled)
        markAllRead.tap()

        let readValue = expectation(
            for: NSPredicate(format: "value == %@", "已读"),
            evaluatedWith: first
        )
        XCTAssertEqual(XCTWaiter.wait(for: [readValue], timeout: 8), .completed)
        XCTAssertFalse(markAllRead.isEnabled, "成功后等待服务端同步期间不得重复提交")
        XCTAssertFalse(app.staticTexts["2 条未读"].exists, "旧计数响应不应覆盖成功 mutation")
        XCTAssertTrue(
            app.buttons["notifications.retry.unread-count"].waitForExistence(timeout: 8),
            "服务端仍返回旧状态时应提供明确的重新同步入口"
        )
        XCTAssertEqual(first.value as? String, "已读", "完成旧响应对账后仍不得回滚行状态")
        XCTAssertFalse(markAllRead.isEnabled, "待同步状态出现后仍不得重复提交")
        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testMarkAllReadPendingDoesNotDependOnVisibleRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-notifications-read-all-empty-page-stale"]
        app.launch()
        defer { app.terminate() }

        let first = app.buttons["notifications.item.41"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "未加载已读通知夹具")
        XCTAssertEqual(first.value as? String, "已读")
        let markAllRead = app.buttons["notifications.mark-all-read"]
        XCTAssertTrue(markAllRead.isEnabled, "精确计数仍有未读时应允许全局标记")

        markAllRead.tap()

        XCTAssertTrue(
            app.buttons["notifications.retry.unread-count"].waitForExistence(timeout: 8),
            "当前页没有未读行时，旧计数也必须进入可恢复的待同步状态"
        )
        XCTAssertFalse(markAllRead.isEnabled, "全局 mutation pending 不能依赖当前页未读 ID")
        XCTAssertFalse(app.staticTexts["2 条未读"].exists, "旧计数不得覆盖批量写入成功状态")
        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testDailyImageFavoriteFailureDoesNotPretendToBeUnfavorited() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-daily-favorite-failure"]
        app.launch()
        defer { app.terminate() }

        let root = anyElement(withIdentifier: "static.info.page", in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 8), "未显示使用帮助页")
        scrollUntilVisible(
            landmark: Landmark(identifier: "daily.favorite.retry"),
            in: app,
            pageRoot: root,
            forwardScrollMode: .semantic,
            maximumSwipes: 20
        )

        let favoriteAction = app.buttons["daily.favorite.action"]
        XCTAssertTrue(favoriteAction.exists, "未显示每日图片收藏状态操作")
        XCTAssertFalse(favoriteAction.isEnabled, "收藏状态未知时不应开放收藏或取消收藏")
        XCTAssertEqual(favoriteAction.label, "暂不可收藏")
        XCTAssertTrue(app.buttons["daily.favorite.retry"].isHittable, "收藏状态失败后应可原位重试")
        try performVisibleViewportAccessibilityAudit(in: app)
    }

    func testPointsResultsKeepFailedFavoriteStatusUnknown() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-points-favorite-failure"]
        app.launch()
        defer { app.terminate() }

        let root = anyElement(withIdentifier: "points.page", in: app)
        XCTAssertTrue(root.waitForExistence(timeout: 8), "未显示按条件找图页")
        scrollUntilVisible(
            landmark: Landmark(identifier: "points.call"),
            in: app,
            pageRoot: root,
            forwardScrollMode: .semantic,
            maximumSwipes: 12
        )
        app.buttons["points.call"].tap()

        scrollUntilVisible(
            landmark: Landmark(identifier: "points.favorite.retry.5101-0"),
            in: app,
            pageRoot: root,
            forwardScrollMode: .semantic,
            maximumSwipes: 16
        )
        XCTAssertTrue(app.staticTexts["收藏状态未知"].exists, "查询失败不应被解释为未收藏")
        XCTAssertTrue(app.buttons["points.favorite.retry.5101-0"].isHittable, "单张图片应可独立重试收藏状态")

        let menu = app.buttons["更多图片操作"]
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        let unavailableAction = app.buttons["收藏状态未知"]
        XCTAssertTrue(unavailableAction.waitForExistence(timeout: 4))
        XCTAssertFalse(unavailableAction.isEnabled, "状态未知时不得开放收藏操作")
    }

    func testRandomImagePrimaryActionsRemainReachableAtAX5() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-random-image",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        defer { app.terminate() }

        let unlockButton = app.buttons["image.unlock"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 8))
        let enabled = expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: unlockButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        XCTAssertTrue(unlockButton.isHittable)
        let favorite = app.buttons["image.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 8))
        let favoriteReady = expectation(
            for: NSPredicate(format: "label == %@ AND isEnabled == true", "收藏"),
            evaluatedWith: favorite
        )
        XCTAssertEqual(XCTWaiter.wait(for: [favoriteReady], timeout: 8), .completed)
        XCTAssertTrue(favorite.isHittable)
        XCTAssertTrue(app.buttons["image.share"].isHittable)
        XCTAssertTrue(app.buttons["下一张"].isHittable)

        let parameters = app.buttons["调整找图设置"]
        XCTAssertTrue(parameters.isHittable)
        parameters.tap()
        let keyword = app.textFields["image.filter.keyword"]
        XCTAssertTrue(keyword.waitForExistence(timeout: 4))
        keyword.tap()
        keyword.typeText("cancelled-filter")
        app.buttons["取消"].tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: keyword)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)

        parameters.tap()
        let reopenedKeyword = app.textFields["image.filter.keyword"]
        XCTAssertTrue(reopenedKeyword.waitForExistence(timeout: 4))
        XCTAssertFalse(
            String(describing: reopenedKeyword.value).contains("cancelled-filter"),
            "取消筛选 Sheet 后不得污染正式参数"
        )
        let apply = app.buttons["应用"]
        XCTAssertTrue(apply.waitForExistence(timeout: 4))
        apply.tap()
        XCTAssertTrue(
            app.staticTexts["已应用参数"].waitForExistence(timeout: 8),
            "应用参数后应展示新一批图片，不能停留在加载态"
        )
    }

    func testRandomImageFavoriteFailureDoesNotPretendToBeUnliked() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-random-image-favorite-failure",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["image.unlock"].waitForExistence(timeout: 8), "随机图片未加载完成")
        let favorite = app.buttons["image.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 8), "未显示喜欢状态操作")
        let failed = expectation(
            for: NSPredicate(format: "label == %@ AND isEnabled == true", "重试状态"),
            evaluatedWith: favorite
        )
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 8), .completed)
        XCTAssertTrue(favorite.isHittable)
        XCTAssertFalse(app.buttons["喜欢"].exists, "状态查询失败时不得显示为未喜欢")
        XCTAssertTrue(
            anyElement(withIdentifier: "image.card.placeholder", in: app).waitForExistence(timeout: 4),
            "无图片地址时应显示独立占位态"
        )
        XCTAssertFalse(
            anyElement(withIdentifier: "image.metadata.overlay", in: app).exists,
            "无图片地址时不应让底部元数据遮挡占位态"
        )
        try performProductAccessibilityAudit(in: app)
    }

    func testPublicAiWorkPassesSystemAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-public-ai-work",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        let likeButton = app.buttons["ai.public.like"]
        XCTAssertTrue(app.navigationBars["公开作品"].waitForExistence(timeout: 8))
        scrollUntilHittable(likeButton, in: app)

        let favoriteButton = app.buttons["ai.public.favorite"]
        scrollUntilHittable(favoriteButton, in: app)
        try performProductAccessibilityAudit(in: app)

        let creatorTitle = app.staticTexts["查看创作者主页"]
        let creatorSubtitle = app.staticTexts["查看对方公开分享的作品与收藏夹"]
        scrollUntilHittable(creatorTitle, in: app)
        scrollUntilHittable(creatorSubtitle, in: app)
        try performProductAccessibilityAudit(in: app)

        let detailsTitle = app.staticTexts["作品信息"]
        let dimensionsLabel = app.descendants(matching: .any)["ai.public.dimensions"]
        scrollUntilHittable(detailsTitle, in: app)
        scrollUntilHittable(dimensionsLabel, in: app)
        try performProductAccessibilityAudit(in: app)
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maximumSwipes {
            if element.exists, element.isHittable {
                break
            }
            app.swipeUp()
        }

        XCTAssertTrue(element.exists, "滚动后仍未找到 \(element)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "滚动后元素仍不可见或不可交互：\(element)", file: file, line: line)
    }

    private func performProductAccessibilityAudit(in app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ])
    }

    private func assertLoggedInRouteMatrix(extraLaunchArguments: [String]) throws {
        for route in loggedInRoutes {
            try XCTContext.runActivity(named: route.title) { _ in
                let app = XCUIApplication()
                app.launchArguments = [route.launchArgument] + extraLaunchArguments
                app.launch()
                defer { app.terminate() }

                let root = anyElement(withIdentifier: route.rootIdentifier, in: app)
                XCTAssertTrue(root.waitForExistence(timeout: 8), "未显示\(route.title)根页面")
                try performVisibleViewportAccessibilityAudit(in: app)

                // List may not create an offscreen row until scrolling, especially at AX5.
                // Verify loaded content by reaching the ready landmark, not by requiring it in the initial tree.
                let orderedLandmarks = [Landmark(identifier: route.readyIdentifier)] + route.landmarks
                for landmark in orderedLandmarks {
                    scrollUntilVisible(
                        landmark: landmark,
                        in: app,
                        pageRoot: root,
                        forwardScrollMode: route.forwardScrollMode,
                        maximumSwipes: 32
                    )
                    try performVisibleViewportAccessibilityAudit(in: app)
                }
            }
        }
    }

    private func anyElement(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        return app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func scrollUntilVisible(
        landmark: Landmark,
        in app: XCUIApplication,
        pageRoot: XCUIElement,
        forwardScrollMode: ForwardScrollMode,
        maximumSwipes: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lastObservation = "目标元素尚未进入可访问性树"

        for _ in 0..<maximumSwipes {
            let viewport = pageViewport(for: pageRoot, app: app)
            let element = element(for: landmark, in: app)
            if isMeaningfullyVisible(element, in: viewport) {
                return
            }

            guard element.exists else {
                lastObservation = "目标元素尚未进入可访问性树，viewport=\(viewport)"
                scrollForward(in: app, pageRoot: pageRoot, mode: forwardScrollMode)
                continue
            }

            let frame = element.frame
            let fraction = visibleFraction(of: frame, in: viewport)
            lastObservation = "elementFrame=\(frame)，viewport=\(viewport)，visibleFraction=\(fraction)，isHittable=\(element.isHittable)"

            if frame.maxY <= viewport.minY {
                scrollDownIncrementally(in: app)
            } else if frame.minY >= viewport.maxY {
                scrollForward(in: app, pageRoot: pageRoot, mode: forwardScrollMode)
            } else if frame.minY < viewport.minY {
                scrollDownFinely(in: app)
            } else {
                scrollUpFinely(in: app)
            }
        }

        let viewport = pageViewport(for: pageRoot, app: app)
        let element = element(for: landmark, in: app)
        guard isMeaningfullyVisible(element, in: viewport) else {
            XCTFail(
                "滚动后 landmark 仍未达到 90% 可见：\(landmark.description)，\(lastObservation)",
                file: file,
                line: line
            )
            return
        }
    }

    private func element(for landmark: Landmark, in app: XCUIApplication) -> XCUIElement {
        if let identifier = landmark.identifier {
            let button = app.buttons.matching(identifier: identifier).firstMatch
            if button.exists {
                return button
            }
            return anyElement(withIdentifier: identifier, in: app)
        }

        let predicate = NSPredicate(format: "label CONTAINS %@", landmark.labelContains ?? "")
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists {
            return button
        }
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func scrollUpIncrementally(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            )
    }

    private func scrollForward(
        in app: XCUIApplication,
        pageRoot: XCUIElement,
        mode: ForwardScrollMode
    ) {
        switch mode {
        case .incremental:
            scrollUpIncrementally(in: app)
        case .semantic:
            pageRoot.swipeUp()
        }
    }

    private func scrollDownIncrementally(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            )
    }

    private func scrollUpFinely(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            )
    }

    private func scrollDownFinely(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.50))
            .press(
                forDuration: 0.01,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
            )
    }

    private func pageViewport(for root: XCUIElement, app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch
        let screenFrame = window.exists ? window.frame : app.frame
        let rootFrame = root.frame.intersection(screenFrame)
        return rootFrame.isNull || rootFrame.isEmpty ? screenFrame : rootFrame
    }

    private func isMeaningfullyVisible(_ element: XCUIElement, in viewport: CGRect) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return false
        }

        return element.isHittable && visibleFraction(of: frame, in: viewport) >= 0.9
    }

    private func visibleFraction(of frame: CGRect, in viewport: CGRect) -> CGFloat {
        let visibleFrame = frame.intersection(viewport)
        guard !visibleFrame.isNull, !visibleFrame.isEmpty else { return 0 }
        let visibleArea = visibleFrame.width * visibleFrame.height
        let totalArea = frame.width * frame.height
        guard totalArea > 0 else { return 0 }
        return visibleArea / totalArea
    }

    private func performVisibleViewportAccessibilityAudit(in app: XCUIApplication) throws {
        let window = app.windows.firstMatch
        let viewport = window.exists ? window.frame : app.frame
        try app.performAccessibilityAudit(for: [
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ]) { issue in
            // Xcode 27 can report orphaned text-clipping issues for content
            // recycled by a List after scrolling. Keep other orphaned audit
            // types as failures because they are not part of that known bug.
            guard let element = issue.element else {
                return issue.auditType.contains(.textClipped)
            }
            let frame = element.frame
            guard frame.width.isFinite,
                  frame.height.isFinite,
                  frame.minX.isFinite,
                  frame.minY.isFinite,
                  frame.width > 0,
                  frame.height > 0 else {
                return false
            }

            let visibleFrame = frame.intersection(viewport)
            guard !visibleFrame.isNull, !visibleFrame.isEmpty else { return true }

            // Xcode 27 audits horizontally/vertically clipped scroll content that is
            // mostly outside the current viewport. Keep near-complete elements so
            // genuine edge clipping still fails this viewport-level audit.
            let visibleArea = visibleFrame.width * visibleFrame.height
            let totalArea = frame.width * frame.height
            let shouldIgnore = visibleArea / totalArea < 0.9
            return shouldIgnore
        }
    }
}
