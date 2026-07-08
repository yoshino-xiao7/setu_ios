import Foundation
import SetuIOSCore

struct AiDrawDraft: Codable {
    var promptCn: String = ""
    var promptPositive: String = ""
    var width: Int = 768
    var height: Int = 1024
    var steps: Int = 28
    var cfg: Double = 7.0
    var nsfwMode: Bool = false
    var nsfwVisibilityLevel: String = "STANDARD"
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
    var source: String = "form"
    var updatedAt: Date = Date()

    init(
        promptCn: String = "",
        promptPositive: String = "",
        width: Int = 768,
        height: Int = 1024,
        steps: Int = 28,
        cfg: Double = 7.0,
        nsfwMode: Bool = false,
        nsfwVisibilityLevel: String = "STANDARD",
        generationMode: String = "SINGLE",
        checkpoint: String = "",
        loraName: String = "",
        loraStrength: Double = 0.8,
        characterId: String = "",
        secondLoraName: String = "",
        secondLoraStrength: Double = 0.65,
        secondCharacterId: String = "",
        styleTags: String = "",
        negativePrompt: String = "",
        styleNotes: String = "",
        source: String = "form",
        updatedAt: Date = Date()
    ) {
        self.promptCn = promptCn
        self.promptPositive = promptPositive
        self.width = width
        self.height = height
        self.steps = steps
        self.cfg = cfg
        self.nsfwMode = nsfwMode
        self.nsfwVisibilityLevel = nsfwVisibilityLevel
        self.generationMode = generationMode
        self.checkpoint = checkpoint
        self.loraName = loraName
        self.loraStrength = loraStrength
        self.characterId = characterId
        self.secondLoraName = secondLoraName
        self.secondLoraStrength = secondLoraStrength
        self.secondCharacterId = secondCharacterId
        self.styleTags = styleTags
        self.negativePrompt = negativePrompt
        self.styleNotes = styleNotes
        self.source = source
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptCn = try container.decodeIfPresent(String.self, forKey: .promptCn) ?? ""
        promptPositive = try container.decodeIfPresent(String.self, forKey: .promptPositive) ?? ""
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 768
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1024
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 28
        cfg = try container.decodeIfPresent(Double.self, forKey: .cfg) ?? 7.0
        nsfwMode = try container.decodeIfPresent(Bool.self, forKey: .nsfwMode) ?? false
        nsfwVisibilityLevel = try container.decodeIfPresent(String.self, forKey: .nsfwVisibilityLevel) ?? "STANDARD"
        generationMode = try container.decodeIfPresent(String.self, forKey: .generationMode) ?? "SINGLE"
        checkpoint = try container.decodeIfPresent(String.self, forKey: .checkpoint) ?? ""
        loraName = try container.decodeIfPresent(String.self, forKey: .loraName) ?? ""
        loraStrength = try container.decodeIfPresent(Double.self, forKey: .loraStrength) ?? 0.8
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId) ?? ""
        secondLoraName = try container.decodeIfPresent(String.self, forKey: .secondLoraName) ?? ""
        secondLoraStrength = try container.decodeIfPresent(Double.self, forKey: .secondLoraStrength) ?? 0.65
        secondCharacterId = try container.decodeIfPresent(String.self, forKey: .secondCharacterId) ?? ""
        styleTags = try container.decodeIfPresent(String.self, forKey: .styleTags) ?? ""
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        styleNotes = try container.decodeIfPresent(String.self, forKey: .styleNotes) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "form"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
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

    static func loadPendingExternalDraft() -> AiDrawDraft? {
        let draft = load()
        guard draft.source == "asset" || draft.source == "history" else { return nil }
        return draft
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func applyAsset(
        kind: AiDraftAssetKind,
        target: AiDraftAssetTarget,
        name: String,
        triggerWords: String,
        negativeTags: String,
        recommendedStrength: Double?,
        recommendedCheckpoint: String,
        linkedLoraName: String
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
        case .style:
            draft.styleTags = mergeTags(draft.styleTags, triggerWords)
            draft.negativePrompt = mergeTags(defaultNegativeBase(for: draft.negativePrompt), negativeTags)
        }
        draft.source = "asset"
        draft.updatedAt = Date()
        save(draft)
    }

    static func updateSelectedStyles(
        styleTags: String,
        negativePrompt: String,
        recommendedCheckpoint: String?
    ) {
        var draft = load()
        draft.styleTags = styleTags
        draft.negativePrompt = mergeTags(AiDrawDefaults.defaultNegativePrompt, negativePrompt)
        if let recommendedCheckpoint, !recommendedCheckpoint.isEmpty {
            draft.checkpoint = recommendedCheckpoint
        }
        draft.source = "asset"
        draft.updatedAt = Date()
        save(draft)
    }

    static func removeAsset(kind: AiDraftAssetKind, target: AiDraftAssetTarget) {
        var draft = load()
        switch kind {
        case .lora:
            if target == .secondary {
                draft.secondLoraName = ""
            } else {
                draft.loraName = ""
            }
        case .character:
            if target == .secondary {
                draft.secondCharacterId = ""
            } else {
                draft.characterId = ""
            }
        case .style:
            break
        }
        draft.source = "asset"
        draft.updatedAt = Date()
        save(draft)
    }

    static func updateFromForm(
        promptCn: String,
        promptPositive: String,
        width: Int,
        height: Int,
        steps: Int,
        cfg: Double,
        nsfwMode: Bool,
        nsfwVisibilityLevel: String,
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
            promptCn: promptCn,
            promptPositive: promptPositive,
            width: width,
            height: height,
            steps: steps,
            cfg: cfg,
            nsfwMode: nsfwMode,
            nsfwVisibilityLevel: nsfwVisibilityLevel,
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
            source: "form",
            updatedAt: Date()
        ))
    }

    static func applyHistoryJob(_ job: AiGenerationJob) {
        save(AiDrawDraft(
            promptCn: job.promptCn,
            promptPositive: job.promptPositive ?? "",
            width: job.width,
            height: job.height,
            steps: job.steps,
            cfg: job.cfg,
            nsfwMode: job.nsfwMode ?? false,
            nsfwVisibilityLevel: job.nsfwVisibilityLevel ?? "STANDARD",
            generationMode: job.generationMode ?? "SINGLE",
            checkpoint: job.checkpoint ?? "",
            loraName: job.loraName ?? "",
            loraStrength: job.loraStrength ?? 0.8,
            characterId: job.characterId ?? "",
            secondLoraName: job.secondLoraName ?? "",
            secondLoraStrength: job.secondLoraStrength ?? 0.65,
            secondCharacterId: job.secondCharacterId ?? "",
            styleTags: "",
            negativePrompt: job.promptNegative ?? AiDrawDefaults.defaultNegativePrompt,
            styleNotes: job.styleNotes ?? "",
            source: "history",
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

    private static func defaultNegativeBase(for current: String) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AiDrawDefaults.defaultNegativePrompt : trimmed
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
