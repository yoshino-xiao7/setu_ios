import XCTest

/// Shared QA audit. Matches ProductAccessibilityUITests' existing viewport policy:
/// 90% of the full window, orphan textClipped only; no contrast waiver is added.
enum SakuraSurfaceAudit {
    static func perform(in app: XCUIApplication, test: XCTestCase, name: String, target: XCUIElement? = nil) throws {
        let window = app.windows.firstMatch
        let viewport = window.exists ? window.frame : app.frame
        func keep(_ attachment: XCTAttachment, suffix: String) {
            attachment.name = "\(name)-\(suffix)"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
        keep(XCTAttachment(string: "Window: \(viewport)\nTarget: \(target.map { String(describing: $0.frame) } ?? "<none>")"), suffix: "viewport")
        var issueCount = 0
        try app.performAccessibilityAudit(for: [.hitRegion, .textClipped, .sufficientElementDescription, .trait]) { issue in
            issueCount += 1
            let ignored: Bool
            if let element = issue.element {
                let frame = element.frame
                if frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite,
                   frame.width > 0, frame.height > 0 {
                    let visible = frame.intersection(viewport)
                    ignored = visible.isNull || visible.isEmpty || visible.width * visible.height / (frame.width * frame.height) < 0.9
                } else { ignored = false }
            } else { ignored = issue.auditType.contains(.textClipped) }
            keep(XCTAttachment(string: """
            \(issue.detailedDescription)
            Type: \(issue.auditType)
            Element: \(issue.element?.label ?? "<none>")
            Frame: \(issue.element.map { String(describing: $0.frame) } ?? "<none>")
            Window: \(viewport)
            Ignored by existing viewport policy: \(ignored)
            """), suffix: "issue-\(issueCount)")
            keep(XCTAttachment(screenshot: app.screenshot()), suffix: "issue-\(issueCount)-window")
            if let element = issue.element, element.exists {
                keep(XCTAttachment(screenshot: element.screenshot()), suffix: "issue-\(issueCount)-element")
            }
            return ignored
        }
    }
}
