import XCTest
@testable import SetuIOSApp

final class AiDrawDraftStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AiDrawDraftStore.clear()
        AiAssetBrowserCacheStore.clearSelectedStyles()
    }

    override func tearDown() {
        AiDrawDraftStore.clear()
        AiAssetBrowserCacheStore.clearSelectedStyles()
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

    func testSubmitResetClearsStyleStateBeforeDisappearCanResaveDraft() {
        AiDrawDraftStore.updateFromForm(
            promptCn: "雨夜街角的银发少女",
            promptPositive: "cinematic lighting, masterpiece",
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

        var styleTags = "电影感"
        var positivePrompt = "cinematic lighting, masterpiece"
        var styleNotes = "霓虹灯"
        AiDrawEditorDraftSync.resetGeneratedStyleState(
            styleTags: &styleTags,
            positivePrompt: &positivePrompt,
            styleNotes: &styleNotes
        )
        AiDrawDraftStore.clear()
        AiAssetBrowserCacheStore.clearSelectedStyles()
        AiDrawDraftStore.updateFromForm(
            promptCn: "雨夜街角的银发少女",
            promptPositive: positivePrompt,
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
            styleTags: styleTags,
            negativePrompt: "low quality",
            styleNotes: styleNotes
        )

        let restored = AiDrawDraftStore.loadIfPresent()
        XCTAssertEqual(restored?.promptCn, "雨夜街角的银发少女")
        XCTAssertEqual(restored?.promptPositive, "")
        XCTAssertEqual(restored?.styleTags, "")
        XCTAssertEqual(restored?.styleNotes, "")
        XCTAssertEqual(AiAssetBrowserCacheStore.enabledStyleDisplayNames(), [])
    }

    func testUncheckingStylesRemovesTheirTagsFromThePositivePrompt() {
        AiDrawDraftStore.updateFromForm(
            promptCn: "银发少女",
            promptPositive: "silver hair, cinematic lighting, masterpiece",
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
            styleTags: "cinematic lighting",
            negativePrompt: "low quality, flat color",
            styleNotes: ""
        )

        AiDrawDraftStore.updateSelectedStyles(
            styleTags: "",
            negativePrompt: "",
            recommendedCheckpoint: nil
        )

        let restored = AiDrawDraftStore.load()
        XCTAssertEqual(restored.styleTags, "")
        XCTAssertEqual(restored.promptPositive, "silver hair, masterpiece")
        XCTAssertFalse(restored.promptPositive.contains("cinematic lighting"))
    }
}
