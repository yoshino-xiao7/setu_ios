import XCTest
@testable import SetuIOSApp

final class AiDrawPromptComposerTests: XCTestCase {
    func testPositivePromptAloneIsDrawableAndBecomesTheSubmittedScene() {
        XCTAssertTrue(
            AiDrawPromptComposer.hasDrawablePrompt(
                promptCn: "  ",
                positivePrompt: "cinematic lighting, silver hair",
                styleTags: ""
            )
        )
        XCTAssertEqual(
            AiDrawPromptComposer.resolvedPromptCn(
                promptCn: "",
                positivePrompt: "cinematic lighting, silver hair"
            ),
            "cinematic lighting, silver hair"
        )
        XCTAssertFalse(
            AiDrawPromptComposer.needsTranslation(
                promptCn: "",
                positivePrompt: "cinematic lighting, silver hair"
            )
        )
    }

    func testClearingNaturalLanguageDropsDerivedPositivePrompt() {
        let nextPositive = AiDrawPromptComposer.positivePromptAfterNaturalLanguageChange(
            previousPromptCn: "雨夜街角的银发少女",
            nextPromptCn: "",
            currentPositivePrompt: "silver hair, rain, neon lights, cinematic lighting",
            presetSeed: "",
            manuallyEdited: false
        )

        XCTAssertEqual(nextPositive, "")
        XCTAssertFalse(
            AiDrawPromptComposer.hasDrawablePrompt(
                promptCn: "",
                positivePrompt: nextPositive,
                styleTags: ""
            )
        )
    }

    func testClearingNaturalLanguageKeepsManuallyEditedPositivePrompt() {
        let nextPositive = AiDrawPromptComposer.positivePromptAfterNaturalLanguageChange(
            previousPromptCn: "雨夜街角的银发少女",
            nextPromptCn: "",
            currentPositivePrompt: "masterpiece, close-up, wet street",
            presetSeed: "",
            manuallyEdited: true
        )

        XCTAssertEqual(nextPositive, "masterpiece, close-up, wet street")
        XCTAssertTrue(
            AiDrawPromptComposer.hasDrawablePrompt(
                promptCn: "",
                positivePrompt: nextPositive,
                styleTags: ""
            )
        )
    }

    func testClearingNaturalLanguageKeepsPresetSeedInsteadOfTranslatedPrompt() {
        let nextPositive = AiDrawPromptComposer.positivePromptAfterNaturalLanguageChange(
            previousPromptCn: "雨夜街角的银发少女",
            nextPromptCn: "  ",
            currentPositivePrompt: "silver hair, rain, character_trigger, cinematic lighting",
            presetSeed: "character_trigger, cinematic lighting",
            manuallyEdited: false
        )

        XCTAssertEqual(nextPositive, "character_trigger, cinematic lighting")
        XCTAssertEqual(
            AiDrawPromptComposer.resolvedPositivePrompt(
                positivePrompt: "",
                presetSeed: "character_trigger"
            ),
            "character_trigger"
        )
    }

    func testRestoredPositiveOnlyDraftIsTreatedAsManual() {
        XCTAssertTrue(
            AiDrawPromptComposer.shouldTreatRestoredPositiveAsManual(
                promptCn: "",
                positivePrompt: "cinematic lighting"
            )
        )
        XCTAssertFalse(
            AiDrawPromptComposer.shouldTreatRestoredPositiveAsManual(
                promptCn: "银发少女",
                positivePrompt: "cinematic lighting"
            )
        )
    }
}
