import Foundation
import SetuIOSCore

/// Lightweight local follow-up chips shown after an assistant turn finishes.
enum AiChatDrawFollowUps {
    static func suggestions(from messages: [AiChatDrawMessage]) -> [String] {
        guard let lastAssistant = messages.last(where: { !$0.isUser }) else { return [] }
        let lastUser = messages.last(where: \.isUser)?.displayContent ?? ""
        let hasJob = lastAssistant.generationJobId != nil || lastAssistant.generationJob != nil
        let subject = subjectHint(from: lastUser)

        if hasJob {
            return Array([
                subject.isEmpty ? "换个构图再画一版" : "保持\(subject)，换个构图再画一版",
                subject.isEmpty ? "加强光影和细节再出一张" : "\(subject)再细腻一点，光影更强"
            ].uniqued().prefix(2))
        }

        return Array([
            subject.isEmpty ? "按这个想法直接出图" : "按「\(subject)」直接出一张图",
            "改成竖构图插画风格"
        ].uniqued().prefix(2))
    }

    private static func subjectHint(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 12 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 12)
        return String(trimmed[..<end]) + "…"
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
