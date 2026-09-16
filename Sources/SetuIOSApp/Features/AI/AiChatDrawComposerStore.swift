import Foundation

/// Holds a one-shot prompt to prefill the AI chat composer (history / square reuse).
enum AiChatDrawComposerStore {
    private static let key = "setu.aiChatDraw.pendingPrompt"
    private static var previewPrompt: String?
    private static var usesPreviewStorage = false

    static var isUsingPreviewStorage: Bool { usesPreviewStorage }

    static func activatePreviewStorage(with prompt: String? = nil) {
        usesPreviewStorage = true
        previewPrompt = prompt
    }

    static func deactivatePreviewStorage() {
        usesPreviewStorage = false
        previewPrompt = nil
    }

    static func setPendingPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if usesPreviewStorage {
            previewPrompt = trimmed
            return
        }
        UserDefaults.standard.set(trimmed, forKey: key)
    }

    static func consumePendingPrompt() -> String? {
        if usesPreviewStorage {
            let value = previewPrompt
            previewPrompt = nil
            return value
        }
        let value = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
