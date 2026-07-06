import Foundation

struct AiDrawDraft: Codable {
    var generationMode: String = "SINGLE"
    var checkpoint: String = ""
    var loraName: String = ""
    var loraStrength: Double = 0.8
    var characterId: String = ""
    var secondLoraName: String = ""
    var secondLoraStrength: Double = 0.65
    var secondCharacterId: String = ""
    var styleTags: String = ""
    var negativePrompt: String = ""
    var styleNotes: String = ""
    var updatedAt: Date = Date()
}

enum AiDrawDraftStore {
    private static let key = "icu.yukiryou.setu.aiDrawDraft"

    static func load() -> AiDrawDraft {
        guard let data = UserDefaults.standard.data(forKey: key),
              let draft = try? JSONDecoder().decode(AiDrawDraft.self, from: data) else {
            return AiDrawDraft()
        }
        return draft
    }

    static func save(_ draft: AiDrawDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func applyAsset(
        kind: AiDraftAssetKind,
        target: AiDraftAssetTarget,
        name: String,
        triggerWords: String,
        negativeTags: String,
        recommendedStrength: Double?,
        recommendedCheckpoint: String,
        linkedLoraName: String,
        notes: String
    ) {
        var draft = load()
        if !recommendedCheckpoint.isEmpty {
            draft.checkpoint = recommendedCheckpoint
        }
        switch kind {
        case .lora:
            if target == .secondary {
                draft.generationMode = "DUAL"
                draft.secondLoraName = name
                if let recommendedStrength {
                    draft.secondLoraStrength = recommendedStrength
                }
            } else {
                draft.loraName = name
                if let recommendedStrength {
                    draft.loraStrength = recommendedStrength
                }
            }
            draft.styleTags = mergeTags(draft.styleTags, triggerWords)
        case .character:
            if target == .secondary {
                draft.generationMode = "DUAL"
                draft.secondCharacterId = name
                if !linkedLoraName.isEmpty {
                    draft.secondLoraName = linkedLoraName
                    if let recommendedStrength {
                        draft.secondLoraStrength = recommendedStrength
                    }
                }
            } else {
                draft.characterId = name
                if !linkedLoraName.isEmpty {
                    draft.loraName = linkedLoraName
                    if let recommendedStrength {
                        draft.loraStrength = recommendedStrength
                    }
                }
            }
            draft.styleTags = mergeTags(draft.styleTags, triggerWords)
            if !notes.isEmpty {
                draft.styleNotes = notes
            }
        case .style:
            draft.styleTags = mergeTags(draft.styleTags, triggerWords)
            draft.negativePrompt = mergeTags(draft.negativePrompt, negativeTags)
            if !notes.isEmpty {
                draft.styleNotes = notes
            }
        }
        draft.updatedAt = Date()
        save(draft)
    }

    static func updateFromForm(
        generationMode: String,
        checkpoint: String,
        loraName: String,
        loraStrength: Double,
        characterId: String,
        secondLoraName: String,
        secondLoraStrength: Double,
        secondCharacterId: String,
        styleTags: String,
        negativePrompt: String,
        styleNotes: String
    ) {
        save(AiDrawDraft(
            generationMode: generationMode,
            checkpoint: checkpoint,
            loraName: loraName,
            loraStrength: loraStrength,
            characterId: characterId,
            secondLoraName: secondLoraName,
            secondLoraStrength: secondLoraStrength,
            secondCharacterId: secondCharacterId,
            styleTags: styleTags,
            negativePrompt: negativePrompt,
            styleNotes: styleNotes,
            updatedAt: Date()
        ))
    }

    private static func mergeTags(_ current: String, _ next: String) -> String {
        var seen = Set<String>()
        var tags: [String] = []
        for part in [current, next] {
            for rawTag in part.split(separator: ",") {
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = tag.lowercased().replacingOccurrences(of: "_", with: " ")
                guard !tag.isEmpty, !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                tags.append(tag)
            }
        }
        return tags.joined(separator: ", ")
    }
}

enum AiDraftAssetKind: String, Codable {
    case lora
    case character
    case style
}

enum AiDraftAssetTarget: String, Codable {
    case primary
    case secondary
}
