import XCTest
@testable import SetuIOSApp

final class AiDrawDraftStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AiDrawDraftStore.clear()
    }

    override func tearDown() {
        AiDrawDraftStore.clear()
        super.tearDown()
    }

    func testFormDraftCanBeRestoredAfterViewRecreation() throws {
        AiDrawDraftStore.updateFromForm(
            promptCn: "雨夜街角的银发少女",
            promptPositive: "cinematic lighting",
            width: 768,
            height: 1024,
            steps: 28,
            cfg: 7,
            nsfwMode: false,
            nsfwVisibilityLevel: "STANDARD",
            generationMode: "SINGLE",
            checkpoint: "",
            loraName: "",
            loraStrength: 0.8,
            characterId: "",
            secondLoraName: "",
            secondLoraStrength: 0.65,
            secondCharacterId: "",
            styleTags: "电影感",
            negativePrompt: "low quality",
            styleNotes: "霓虹灯"
        )

        let restored = try XCTUnwrap(AiDrawDraftStore.loadIfPresent())

        XCTAssertEqual(restored.source, "form")
        XCTAssertEqual(restored.promptCn, "雨夜街角的银发少女")
        XCTAssertEqual(restored.promptPositive, "cinematic lighting")
        XCTAssertEqual(restored.styleTags, "电影感")
        XCTAssertEqual(restored.styleNotes, "霓虹灯")
    }
}
