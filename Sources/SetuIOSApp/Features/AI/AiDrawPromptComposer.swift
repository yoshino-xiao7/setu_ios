import Foundation

enum AiDrawPromptComposer {
    static func hasDrawablePrompt(promptCn: String, positivePrompt: String, styleTags: String) -> Bool {
        !trimmed(promptCn).isEmpty || !trimmed(positivePrompt).isEmpty || !trimmed(styleTags).isEmpty
    }

    static func resolvedPromptCn(promptCn: String, positivePrompt: String) -> String {
        let naturalLanguage = trimmed(promptCn)
        if !naturalLanguage.isEmpty {
            return naturalLanguage
        }
        return trimmed(positivePrompt)
    }

    static func resolvedPositivePrompt(positivePrompt: String, presetSeed: String) -> String {
        let positive = trimmed(positivePrompt)
        if !positive.isEmpty {
            return positive
        }
        return trimmed(presetSeed)
    }

    static func needsTranslation(promptCn: String, positivePrompt: String) -> Bool {
        !trimmed(promptCn).isEmpty && trimmed(positivePrompt).isEmpty
    }

    /// Clearing 想画什么 should not keep a leftover translated or history
    /// 正向提示词 unless the user typed that field themselves.
    static func positivePromptAfterNaturalLanguageChange(
        previousPromptCn: String,
        nextPromptCn: String,
        currentPositivePrompt: String,
        presetSeed: String,
        manuallyEdited: Bool
    ) -> String {
        let previous = trimmed(previousPromptCn)
        let next = trimmed(nextPromptCn)
        guard !previous.isEmpty, next.isEmpty, !manuallyEdited else {
            return currentPositivePrompt
        }
        return trimmed(presetSeed)
    }

    static func shouldTreatRestoredPositiveAsManual(promptCn: String, positivePrompt: String) -> Bool {
        trimmed(promptCn).isEmpty && !trimmed(positivePrompt).isEmpty
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
