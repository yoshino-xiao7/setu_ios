import XCTest

final class UXFlowUITests: XCTestCase {
    func testMusicQualityOptionsAndPlayerFailurePreserveSelection() {
        let app = launch(["-ui-testing-root-music"])
        let quality = app.buttons["music.quality"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        quality.tap()
        for title in ["标准", "较高", "极高", "无损", "Hi-Res"] {
            XCTAssertTrue(app.buttons[title].exists, title)
        }
        app.buttons["无损"].tap()
        XCTAssertEqual(quality.label, "优先音质：无损")
        app.tabBars.buttons["图片"].tap()
        app.tabBars.buttons["音乐"].tap()
        XCTAssertEqual(quality.label, "优先音质：无损")
        app.terminate()

        app.launchArguments = ["-ui-testing-root-player", "-ui-testing-quality-unavailable", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate() }
        let openPlayer = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(openPlayer.waitForExistence(timeout: 8))
        openPlayer.tap()
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        quality.tap()
        app.buttons["Hi-Res"].tap()
        XCTAssertTrue(app.alerts["音质提示"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS '服务暂时开小差'")).firstMatch.exists)
        app.alerts.buttons["好"].tap()
        XCTAssertEqual(quality.label, "优先音质：极高")
        XCTAssertTrue(app.buttons["播放"].exists, "切换失败不能自动开始暂停的歌曲")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "music-quality-player"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testMusicQualityMenuIsReachableAtAX5() {
        let app = launch(["-ui-testing-root-music", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"])
        defer { app.terminate() }
        let quality = app.buttons["music.quality"]
        XCTAssertTrue(quality.waitForExistence(timeout: 8))
        XCTAssertTrue(quality.isHittable)
        quality.tap()
        XCTAssertTrue(app.buttons["Hi-Res"].waitForExistence(timeout: 3))
        app.buttons["Hi-Res"].tap()
        XCTAssertEqual(quality.label, "优先音质：Hi-Res")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "music-quality-AX5"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["-ui-testing-root-player", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch()
        let openPlayer = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(openPlayer.waitForExistence(timeout: 8))
        openPlayer.tap()
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        XCTAssertTrue(quality.isHittable)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "music-quality-player-AX5"
        expanded.lifetime = .keepAlways
        add(expanded)
    }

    func testLiveWelcomeExampleLoadsAndPreviews() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SETU_RUN_LIVE_PUBLIC_UI_TESTS"] == "1", "Live public API acceptance is opt-in")
        let app = launch(["-ui-testing-welcome-fixture", "-ui-testing-public-example-live"])
        defer { app.terminate() }
        let preview = app.buttons["daily.example.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        XCTAssertTrue(preview.isHittable)
        let welcome = XCTAttachment(screenshot: app.screenshot())
        welcome.name = "live-welcome-example"
        welcome.lifetime = .keepAlways
        add(welcome)
        preview.tap()
        XCTAssertTrue(app.buttons["image.preview.close"].waitForExistence(timeout: 8))
        let loadedImage = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS '，作者 ' AND NOT label CONTAINS '正在加载' AND NOT label CONTAINS '加载失败'"
        )).firstMatch
        XCTAssertTrue(loadedImage.waitForExistence(timeout: 30))
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "live-welcome-preview"
        expanded.lifetime = .keepAlways
        add(expanded)
        app.buttons["image.preview.close"].tap()
        let loadedWelcome = XCTAttachment(screenshot: app.screenshot())
        loadedWelcome.name = "live-welcome-loaded"
        loadedWelcome.lifetime = .keepAlways
        add(loadedWelcome)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments.contains("-UIPreferredContentSizeCategoryName")
            ? arguments
            : arguments + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollTo(_ target: XCUIElement, in app: XCUIApplication, limit: Int = 8) {
        for _ in 0..<limit {
            if target.exists && target.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable)
    }

    func testFavoriteToggleAndLongPressPicker() {
        let app = launch(["-ui-testing-root-images"])
        defer { app.terminate() }
        let favorite = app.buttons["image.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 8))
        let ready = expectation(for: NSPredicate(format: "enabled == true AND label == '收藏'"), evaluatedWith: favorite)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        favorite.tap()
        XCTAssertTrue(app.buttons["改到其他收藏夹"].waitForExistence(timeout: 3))
        XCTAssertEqual(favorite.label, "已收藏")
        favorite.tap()
        let removed = expectation(for: NSPredicate(format: "label == '收藏'"), evaluatedWith: favorite)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        favorite.press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["选择收藏夹"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertEqual(favorite.label, "收藏", "长按只打开选择器，不应同时收藏")
    }

    func testFiveImageChangesLeaveNoInfoBanner() {
        let app = launch(["-ui-testing-root-images"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["image.unlock"].waitForExistence(timeout: 8))
        for _ in 0..<5 {
            app.buttons["image.more"].tap()
            app.buttons["下一张"].tap()
        }
        XCTAssertFalse(element("image.feedback", in: app).exists)
    }

    func testNetworkFailureKeepsRecoveryAvailable() {
        let app = launch(["-ui-testing-root-images", "-ui-testing-feed-failure"])
        defer { app.terminate() }
        let retry = app.buttons["重试"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertFalse(retry.waitForNonExistence(timeout: 3))
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
    }

    func testWelcomeExampleOpensPreviewAndAPIFailureHidesCard() {
        let app = launch(["-ui-testing-welcome-fixture"])
        let example = app.buttons["daily.example.preview"]
        XCTAssertTrue(example.waitForExistence(timeout: 8))
        XCTAssertTrue(example.isHittable)
        example.tap()
        XCTAssertTrue(app.buttons["image.preview.close"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-ui-testing-welcome-fixture", "-ui-testing-welcome-failure"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.welcome.email"].waitForExistence(timeout: 8))
        XCTAssertFalse(example.exists)
        XCTAssertFalse(app.staticTexts["服务暂时开小差"].exists)
        app.terminate()
    }

    func testExpiredConsumeReloadsFreePreviewAndKeepsUnlockExplicit() {
        let app = launch(["-ui-testing-root-images", "-ui-testing-root-feed-expiry"])
        defer { app.terminate() }
        let unlock = app.buttons["image.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 8))
        unlock.tap()
        let confirm = app.alerts.buttons["image.unlock.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["预览已过期，已重新加载。请确认新图片后查看高清图。"].waitForExistence(timeout: 5))
        XCTAssertTrue(unlock.isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testGenerationReturnsToOriginalEditor() {
        let app = launch(["-ui-testing-root-ai"])
        defer { app.terminate() }
        let generate = app.buttons["ai.draw.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 8))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: generate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        generate.tap()
        let later = app.buttons["暂不"]
        if later.waitForExistence(timeout: 3) { later.tap() }
        let again = app.buttons["ai.detail.create-again"]
        XCTAssertTrue(again.waitForExistence(timeout: 10))
        again.tap()
        let prompt = element("ai.draw.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: prompt.value).contains("银发少女站在雨夜街角"))
        XCTAssertFalse(again.exists)
        XCTAssertTrue(generate.isHittable)
    }

    func testTwoAssetsApplyAndReturnWithNames() {
        let app = launch(["-ui-testing-root-ai"])
        defer { app.terminate() }
        let dual = app.buttons["双人物"]
        scrollTo(dual, in: app)
        dual.tap()
        let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '选择风格与角色'")).firstMatch
        scrollTo(choose, in: app)
        choose.tap()
        let lora = app.buttons["使用 电影感光影"]
        scrollTo(lora, in: app)
        lora.tap()
        app.swipeDown()
        app.buttons["副角色"].tap()
        app.buttons["内容类型、附加画风"].tap()
        app.buttons["角色"].tap()
        let character = app.buttons["使用 银发少女"]
        scrollTo(character, in: app)
        character.tap()
        let apply = app.buttons["ai.assets.apply"]
        XCTAssertEqual(apply.label, "应用并返回（已选 2 项）")
        apply.tap()
        let summary = app.buttons.matching(NSPredicate(format: "label CONTAINS '电影感光影' AND label CONTAINS '银发少女'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
    }

    func testMiniPlayerLeavesTabsAndBottomActionsVisible() {
        for largeText in [false, true] {
            var arguments = ["-ui-testing-root-player"]
            if largeText { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"] }
            let app = launch(arguments)
            defer { app.terminate() }
            for tab in ["首页", "AI 绘画", "图片", "音乐", "广场"] {
                let tabButton = app.tabBars.buttons[tab]
                XCTAssertTrue(tabButton.waitForExistence(timeout: 8))
                tabButton.tap()
                let bar = element("music.mini-player", in: app)
                XCTAssertTrue(bar.waitForExistence(timeout: 5))
                XCTAssertLessThanOrEqual(bar.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
                XCTAssertTrue(tabButton.isHittable)
                let actionID = tab == "AI 绘画" ? "ai.draw.generate" : "image.unlock"
                if tab == "AI 绘画" || tab == "图片" {
                    let action = app.buttons[actionID]
                    XCTAssertTrue(action.isHittable)
                    XCTAssertLessThanOrEqual(action.frame.maxY, bar.frame.minY + 1)
                }
                if tab == "图片" {
                    XCTAssertTrue(app.buttons["image.balance"].staticTexts["86"].exists)
                    for (id, title) in [("image.favorite", "收藏"), ("image.share", "分享"), ("下一张", "下一张")] {
                        let button = app.buttons[id]
                        let text = button.staticTexts[title]
                        XCTAssertTrue(text.exists)
                        XCTAssertGreaterThanOrEqual(text.frame.minY, button.frame.minY - 1)
                        XCTAssertLessThanOrEqual(text.frame.maxY, button.frame.maxY + 1)
                        XCTAssertLessThanOrEqual(button.frame.maxY, bar.frame.minY + 1)
                    }
                }
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "player-\(tab)-\(largeText ? "AX5" : "default")"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                if tab == "AI 绘画" {
                    app.buttons["AI 绘画历史"].tap()
                    XCTAssertTrue(bar.waitForExistence(timeout: 5))
                    XCTAssertLessThanOrEqual(bar.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
                    let history = XCTAttachment(screenshot: app.screenshot())
                    history.name = "player-history-\(largeText ? "AX5" : "default")"
                    history.lifetime = .keepAlways
                    add(history)
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
            }
            app.terminate()
        }
    }

    func testUnauthorizedMainRoutesReturnAfterLogin() {
        for route in ["ai", "images", "music", "favorites"] {
            let app = launch(["-ui-testing-root-\(route)", "-ui-testing-root-401"])
            let signIn = app.buttons["重新登录"].firstMatch
            XCTAssertTrue(signIn.waitForExistence(timeout: 10), route)
            scrollTo(signIn, in: app)
            signIn.tap()
            let email = app.textFields["auth.login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 5))
            email.tap()
            email.typeText("preview@xueliang.local")
            let password = app.secureTextFields["auth.login.password"]
            scrollTo(password, in: app)
            password.tap()
            password.typeText("fixture-password")
            let keyboardDone = app.buttons["完成"].firstMatch
            if keyboardDone.exists { keyboardDone.tap() }
            let captcha = app.textFields["auth.login.captcha"]
            scrollTo(captcha, in: app)
            captcha.tap()
            captcha.typeText("ABCD")
            let done = app.buttons["完成"].firstMatch
            if done.exists { done.tap() }
            let login = app.buttons["登录"].firstMatch
            scrollTo(login, in: app)
            login.tap()
            let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: email)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, route)
            let titles = ["ai": "AI 绘画", "images": "随机图片", "music": "音乐", "favorites": "默认收藏"]
            XCTAssertTrue(app.navigationBars[titles[route]!].exists, route)
            if route == "ai" {
                XCTAssertTrue(String(describing: element("ai.draw.prompt", in: app).value).contains("银发少女"))
            }
            app.terminate()
        }
    }

    func testPromptPreparation401OffersLogin() {
        let app = launch(["-ui-testing-root-ai", "-ui-testing-root-translate-401"])
        defer { app.terminate() }
        let generate = app.buttons["ai.draw.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 8))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: generate)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        generate.tap()
        let signIn = app.buttons["重新登录"].firstMatch
        scrollTo(signIn, in: app)
        signIn.tap()
        XCTAssertTrue(app.textFields["auth.login.email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ai.detail.create-again"].exists)
    }
}
