import XCTest

final class ModuleTransitionUITests: XCTestCase {
    func testModuleLogosAndStatusBarBackground() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["首页"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        let modules: [(String, String?)] = [("首页", nil), ("音乐", "MusicHomeLogo"), ("AI 绘画", "AiDrawLogo"), ("图片", "ImageHomeLogo"), ("更多", "SquareLogo")]
        for (tab, asset) in modules {
            app.tabBars.buttons[tab].tap()
            if let asset {
                XCTAssertTrue(app.descendants(matching: .any)["hub.logo.\(asset)"].firstMatch.waitForExistence(timeout: 3), "\(tab) must show its logo")
            }
            if tab == "AI 绘画" {
                XCTAssertGreaterThanOrEqual(app.navigationBars.staticTexts["AI 绘画"].firstMatch.frame.width, 50, "The title must have room beside the restored logo")
                app.buttons["更多创作操作"].tap()
                XCTAssertTrue(app.buttons["我的删除记录"].waitForExistence(timeout: 2))
                app.buttons["我的删除记录"].tap()
                XCTAssertTrue(app.navigationBars["AI 删除申请"].waitForExistence(timeout: 3))
                app.navigationBars.buttons.firstMatch.tap()
            }
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "regression-\(asset ?? "Home")"; attachment.lifetime = .keepAlways; add(attachment)
            // The pink page background must extend through the status-bar safe area.
            let image = screenshot.image
            let point = CGPoint(x: image.size.width * 0.30, y: 3)
            let pixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
                image.draw(at: CGPoint(x: -point.x, y: -point.y))
            }
            if let bytes = pixel.cgImage?.dataProvider?.data, let data = CFDataGetBytePtr(bytes) {
                XCTAssertLessThan(Int(data[1]), 253, "\(tab) has a white strip above its page background")
            } else { XCTFail("Cannot sample screenshot") }
        }
    }

    func testReturningHomeDoesNotRestartInitialLoading() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player"]
        app.launch()
        defer { app.terminate() }
        let home = app.tabBars.buttons["首页"]
        XCTAssertTrue(home.wait(for: \.isHittable, toEqual: true, timeout: 15))
        let greeting = app.otherElements["dashboard.greeting"]
        let baseline = greeting.value as? String
        XCTAssertTrue(baseline?.contains("loads=1") == true)
        for tab in ["AI 绘画", "图片", "音乐"] {
            app.tabBars.buttons[tab].tap()
            home.tap()
            XCTAssertEqual(greeting.value as? String, baseline, "Returning from \(tab) restarted the initial load or recreated the page")
        }
    }

    func testModuleRoundTripPreservesNavigationAndPlayer() {
        verifyRoundTrip(reduceMotion: false)
    }

    func testReducedMotionModuleRoundTrip() {
        verifyRoundTrip(reduceMotion: true)
    }

    private func verifyRoundTrip(reduceMotion: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player"]
        if reduceMotion { app.launchArguments.append("-ui-testing-reduce-motion") }
        app.launch()
        defer { app.terminate() }
        let player = app.otherElements["music.mini-player"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        let identity = player.value as? String
        XCTAssertTrue(app.tabBars.buttons["音乐"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.tabBars.buttons["音乐"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("测试\n")
        XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 5))
        for name in ["图片", "首页", "更多", "AI 绘画", "音乐"] {
            let tab = app.tabBars.buttons[name]
            tab.tap()
            XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertTrue(player.isHittable)
            XCTAssertEqual(player.value as? String, identity)
        }
        XCTAssertEqual(app.otherElements["module.content.music"].value as? String, "transition=6")
        XCTAssertTrue(app.navigationBars["搜索音乐"].exists, "Returning to a module must retain its navigation stack")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = reduceMotion ? "module-reduced-motion" : "module-slide-round-trip"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testMoreTabOpensPlazaAsmrAndJm() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-more"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["更多"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        XCTAssertTrue(element("more.hub.page", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("more.hub.plaza", in: app).exists)
        XCTAssertTrue(element("more.hub.asmr", in: app).exists)
        XCTAssertTrue(element("more.hub.jm", in: app).exists)
        XCTAssertTrue(element("more.hub.hanime", in: app).exists)
        XCTAssertTrue(element("more.hub.cloudVideo", in: app).exists)

        element("more.hub.plaza", in: app).tap()
        XCTAssertTrue(element("plaza.hub.page", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["广场"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        element("more.hub.asmr", in: app).tap()
        XCTAssertTrue(element("asmr.home.page", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["ASMR"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        element("more.hub.jm", in: app).tap()
        XCTAssertTrue(element("jm.home.page", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["JM 本子"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        element("more.hub.hanime", in: app).tap()
        XCTAssertTrue(element("hanime.home.page", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars["H 动漫"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("hanime.genre.strip", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("hanime.genre.riban", in: app).exists)
        XCTAssertTrue(element("hanime.genre.mmd", in: app).exists)
        XCTAssertTrue(element("hanime.genre.cosplay", in: app).exists)
    }

    func testAsmrSearchKeepsMiniPlayerVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player", "-ui-testing-root-more"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["更多"].wait(for: \.isHittable, toEqual: true, timeout: 15))
        XCTAssertTrue(app.otherElements["music.mini-player"].firstMatch.waitForExistence(timeout: 8))
        element("more.hub.asmr", in: app).tap()
        XCTAssertTrue(element("asmr.home.page", in: app).waitForExistence(timeout: 8))
        let search = app.textFields["asmr.search.field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("雨声")
        XCTAssertTrue(app.otherElements["music.mini-player"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["music.mini-player"].firstMatch.isHittable)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
