import Foundation
import SetuIOSCore

/// Lightweight local follow-up chips shown after an assistant turn finishes.
enum AiChatDrawFollowUps {
    static func suggestions(from messages: [AiChatDrawMessage]) -> [String] {
        guard let lastAssistant = messages.last(where: { !$0.isUser }) else { return [] }
        return lastAssistant.followUps
    }
}
