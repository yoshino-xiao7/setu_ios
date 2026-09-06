import XCTest

/// A separate diagnostic calibration, not a waiver for production-page audits.
final class SakuraContrastCalibrationUITests: XCTestCase {
    private let cases = ["A-black-white", "B-solid-plum", "C-identical-gradient",
                         "D-hero-gradient", "E-primary-button", "F-primary-in-dock", "N-negative-control"]

    func testContrastCalibrationInLightAX1() { run(mode: "Light") }
    func testContrastCalibrationInDarkAX1() { run(mode: "Dark") }

    private func run(mode: String) {
        continueAfterFailure = true // Preserve every independent calibration result.
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-sakura-contrast", mode,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        defer { app.terminate() }

        for name in cases {
            XCTContext.runActivity(named: "\(mode)-AX1-\(name)") { _ in
                let current = app.staticTexts["sakura.contrast.current"]
                let selection = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == true AND label == %@", name), object: current)
                guard XCTWaiter.wait(for: [selection], timeout: 10) == .completed else {
                    XCTFail("Calibration case did not become current: \(name)")
                    return
                }
                let probe = app.descendants(matching: .any)["sakura.contrast.probe"].firstMatch
                guard probe.waitForExistence(timeout: 10) else {
                    XCTFail("Calibration probe missing: \(name)")
                    return
                }
                let prefix = "\(mode)-AX1-\(name)"
                attach(app.screenshot(), name: "\(prefix)-window")
                attach(probe.screenshot(), name: "\(prefix)-probe")
                let context = XCTAttachment(string: """
                Case: \(name)
                Appearance: \(mode), Dynamic Type: accessibility1
                Probe frame: \(probe.frame)
                Window frame: \(app.windows.firstMatch.frame)
                Probe hittable: \(probe.isHittable)
                Expected: \(name == "N-negative-control" ? "contrast failure, white on #DDDDDD" : "contrast pass")
                """)
                keep(context, name: "\(prefix)-context")

                if name == "N-negative-control" {
                    var negativeProbeIssues = 0
                    var negativeAuditIssues = 0
                    let options = XCTExpectedFailure.Options()
                    options.isStrict = true
                    // An unrelated exception or assertion must remain a failure.
                    options.issueMatcher = { issue in
                        issue.compactDescription == "Contrast failed"
                            || issue.compactDescription == "Contrast nearly passed"
                    }
                    XCTExpectFailure("Known negative control: white on #DDDDDD, approximately 1.36:1",
                                     options: options) {
                        negativeAuditIssues = self.audit(app, probe: probe, name: prefix) { negativeProbeIssues += 1 }
                    }
                    // Outside the expected-failure scope: a different element's
                    // failure cannot masquerade as successful negative calibration.
                    XCTAssertGreaterThan(negativeProbeIssues, 0, "The audit must detect the negative probe itself")
                    XCTAssertEqual(negativeAuditIssues, negativeProbeIssues,
                                   "Other elements or unidentified issues must not be accepted as expected failures")
                } else {
                    audit(app, probe: probe, name: prefix)
                }
                app.buttons["sakura.contrast.next"].tap()
            }
        }
    }

    @discardableResult
    private func audit(_ app: XCUIApplication, probe: XCUIElement, name: String,
                       onProbeContrastIssue: (() -> Void)? = nil) -> Int {
        var issueCount = 0
        do {
            try app.performAccessibilityAudit(for: .contrast) { issue in
                issueCount += 1
                let element = issue.element
                let detail = XCTAttachment(string: """
                \(issue.detailedDescription)
                Audit type: \(issue.auditType)
                Element identifier: \(element?.identifier ?? "<none>")
                Element label: \(element?.label ?? "<none>")
                Element frame: \(element.map { String(describing: $0.frame) } ?? "<none>")
                Probe frame: \(probe.frame)
                Window frame: \(app.windows.firstMatch.frame)
                """)
                self.keep(detail, name: "\(name)-issue-\(issueCount)-context")
                self.attach(app.screenshot(), name: "\(name)-issue-\(issueCount)-window")
                if let element, element.exists {
                    self.attach(element.screenshot(), name: "\(name)-issue-\(issueCount)-element")
                    if issue.auditType.contains(.contrast),
                       element.identifier == "sakura.contrast.probe"
                        || (element.label == "对比度 Aa 123" && element.frame.intersects(probe.frame)) {
                        onProbeContrastIssue?()
                    }
                }
                return false // Never suppress an issue, including missing-element issues.
            }
        } catch {
            XCTFail("Unexpected calibration audit exception: \(error)")
        }
        keep(XCTAttachment(string: "\(issueCount) audit issues recorded"), name: "\(name)-issue-count")
        return issueCount
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        keep(XCTAttachment(screenshot: screenshot), name: name)
    }

    private func keep(_ attachment: XCTAttachment, name: String) {
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
