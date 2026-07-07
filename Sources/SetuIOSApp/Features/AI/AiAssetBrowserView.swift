import SetuIOSCore
import SwiftUI

struct AiAssetBrowserView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AiCapabilityResponse> = .idle
    @State private var activeKind: AiAssetKind = .lora
    @State private var target: AiDraftAssetTarget = .primary
    @State private var searchText = ""
    @State private var categoryFilter = "ALL"
    @State private var selectedAsset: AiAssetDisplayItem?
    @State private var message: String?

    var body: some View {
        List {
            Picker("资产", selection: $activeKind) {
                ForEach(AiAssetKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: activeKind) {
                searchText = ""
                categoryFilter = "ALL"
            }

            if activeKind != .style {
                Picker("写入目标", selection: $target) {
                    Text("主角色").tag(AiDraftAssetTarget.primary)
                    Text("副角色").tag(AiDraftAssetTarget.secondary)
                }
                .pickerStyle(.segmented)
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载资产")
            case .failed(let message):
                ContentUnavailableView("资产加载失败", systemImage: "photo.stack", description: Text(message))
            case .loaded(let capabilities):
                let items = activeKind.items(from: capabilities)
                let categories = categories(for: items)
                let filteredItems = filtered(items)

                Section {
                    TextField("搜索名称、文件名、触发词或说明", text: $searchText)
                    Picker("分类", selection: $categoryFilter) {
                        Text("全部").tag("ALL")
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }

                Section("\(activeKind.title) · \(filteredItems.count)/\(items.count)") {
                    if filteredItems.isEmpty {
                        ContentUnavailableView("暂无匹配资产", systemImage: activeKind.systemImage)
                    } else {
                        ForEach(filteredItems) { asset in
                            Button {
                                selectedAsset = asset
                            } label: {
                                AiAssetRow(asset: asset)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI 资产选择")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedAsset) { asset in
            AiAssetDetailSheet(asset: asset) {
                applyToDrawDraft(asset)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.capabilities())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func categories(for items: [AiAssetDisplayItem]) -> [String] {
        Array(Set(items.map(\.categoryPath)))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    private func filtered(_ items: [AiAssetDisplayItem]) -> [AiAssetDisplayItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { asset in
            if categoryFilter != "ALL", asset.categoryPath != categoryFilter {
                return false
            }
            guard !keyword.isEmpty else { return true }
            return [
                asset.displayName,
                asset.name,
                asset.fileName,
                asset.category,
                asset.categoryType,
                asset.triggerWords,
                asset.recommendedCheckpoint,
                asset.notes,
            ].contains { $0.lowercased().contains(keyword) }
        }
    }

    private func applyToDrawDraft(_ asset: AiAssetDisplayItem) {
        AiDrawDraftStore.applyAsset(
            kind: asset.draftKind,
            target: target,
            name: asset.name,
            triggerWords: asset.triggerWords,
            negativeTags: asset.negativeTags,
            recommendedStrength: asset.recommendedStrength,
            recommendedCheckpoint: asset.recommendedCheckpoint,
            linkedLoraName: asset.linkedLoraName,
            notes: asset.notes
        )
        let targetTitle = asset.kind == .style ? "全局风格" : (target == .secondary ? "副角色" : "主角色")
        message = "\(asset.displayName) 已写入 AI 绘画草稿：\(targetTitle)"
        selectedAsset = nil
    }
}

private enum AiAssetKind: String, CaseIterable, Identifiable {
    case lora
    case character
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lora: "LoRA"
        case .character: "角色"
        case .style: "风格"
        }
    }

    var systemImage: String {
        switch self {
        case .lora: "slider.horizontal.3"
        case .character: "person.crop.square"
        case .style: "paintpalette"
        }
    }

    func items(from capabilities: AiCapabilityResponse) -> [AiAssetDisplayItem] {
        switch self {
        case .lora:
            capabilities.loras.map { AiAssetDisplayItem(item: $0, kind: self, fallbackCategory: "未分类") }
        case .character:
            capabilities.characters.map { AiAssetDisplayItem(item: $0, kind: self, fallbackCategory: "未分类角色") }
        case .style:
            capabilities.promptPresets.map { AiAssetDisplayItem(styleItem: $0, kind: self) }
        }
    }
}

private struct AiAssetDisplayItem: Identifiable {
    let id: String
    let kind: AiAssetKind
    let name: String
    let displayName: String
    let category: String
    let categoryType: String
    let triggerWords: String
    let negativeTags: String
    let recommendedStrength: Double?
    let recommendedCheckpoint: String
    let linkedLoraName: String
    let previewImage: String
    let notes: String
    let fileName: String
    let nsfwOnly: Bool

    init(item: AiCapabilityItem, kind: AiAssetKind, fallbackCategory: String) {
        let metadata = AiAssetMetadata(json: item.metadataJson)
        self.id = "\(kind.rawValue):\(item.id)"
        self.kind = kind
        self.name = item.name
        self.displayName = metadata.firstText("display_name", "displayName", "name") ?? item.displayName ?? item.name
        self.category = metadata.firstText("category", "category_name", "categoryDisplayName", "franchise") ?? fallbackCategory
        self.categoryType = metadata.firstText("category_type", "categoryType", "type") ?? ""
        self.triggerWords = metadata.firstText("trigger_words", "triggerWords", "trigger") ?? ""
        self.negativeTags = metadata.firstText("default_negative", "defaultNegative") ?? ""
        self.recommendedStrength = metadata.firstNumber("recommended_strength", "recommendedStrength", "lora_strength", "loraStrength")
        self.recommendedCheckpoint = metadata.firstText("recommended_checkpoint", "recommendedCheckpoint") ?? ""
        self.linkedLoraName = metadata.firstText("lora_name", "loraName") ?? ""
        self.previewImage = metadata.previewImage
        self.notes = metadata.firstText("notes", "description", "summary") ?? ""
        self.fileName = metadata.firstText("file_name", "fileName", "lora_name", "loraName") ?? item.name
        self.nsfwOnly = metadata.bool("nsfw_only") || metadata.bool("nsfwOnly")
    }

    init(styleItem item: AiCapabilityItem, kind: AiAssetKind) {
        let metadata = AiAssetMetadata(json: item.metadataJson)
        self.id = "\(kind.rawValue):\(item.id)"
        self.kind = kind
        self.name = item.name
        self.displayName = metadata.firstText("name", "display_name", "displayName") ?? item.displayName ?? item.name
        self.category = metadata.firstText("category") ?? "风格预设"
        self.categoryType = metadata.firstText("category_type", "categoryType") ?? "风格"
        self.triggerWords = metadata.mergedTags("trigger_words", "triggerWords", "default_positive", "defaultPositive", "style_tags", "styleTags")
        self.negativeTags = metadata.firstText("default_negative", "defaultNegative") ?? ""
        self.recommendedStrength = nil
        self.recommendedCheckpoint = metadata.firstText("recommended_checkpoint", "recommendedCheckpoint") ?? ""
        self.linkedLoraName = ""
        self.previewImage = metadata.previewImage
        self.notes = metadata.firstText("notes", "description") ?? ""
        self.fileName = item.name
        self.nsfwOnly = metadata.bool("nsfw_only") || metadata.bool("nsfwOnly")
    }

    var categoryPath: String {
        [categoryType, category]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " / ")
    }

    var summary: String {
        if !triggerWords.isEmpty {
            return "触发词：\(triggerWords)"
        }
        if !notes.isEmpty {
            return notes
        }
        return fileName
    }

    var draftKind: AiDraftAssetKind {
        switch kind {
        case .lora: .lora
        case .character: .character
        case .style: .style
        }
    }
}

private struct AiAssetRow: View {
    let asset: AiAssetDisplayItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AiAssetPreview(asset: asset)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(asset.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if asset.nsfwOnly {
                        Text("NSFW")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)
                    }
                }
                Text(asset.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(asset.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(asset.categoryPath.isEmpty ? "未分组" : asset.categoryPath, systemImage: asset.kind.systemImage)
                    if let strength = asset.recommendedStrength {
                        Label(strength.formatted(.number.precision(.fractionLength(2))), systemImage: "dial.low")
                    }
                    if !asset.recommendedCheckpoint.isEmpty {
                        Label(asset.recommendedCheckpoint, systemImage: "cpu")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AiAssetDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let asset: AiAssetDisplayItem
    let onUse: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AiAssetPreview(asset: asset)
                            .frame(width: 86, height: 86)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(asset.displayName)
                                .font(.headline)
                            Text(asset.fileName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if asset.nsfwOnly {
                                Label("NSFW 专用", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("详情") {
                    LabeledContent("类型", value: asset.kind.title)
                    LabeledContent("目录", value: asset.categoryPath.isEmpty ? "未分组" : asset.categoryPath)
                    if !asset.triggerWords.isEmpty {
                        LabeledContent("触发词", value: asset.triggerWords)
                    }
                    if !asset.negativeTags.isEmpty {
                        LabeledContent("负向词", value: asset.negativeTags)
                    }
                    if let strength = asset.recommendedStrength {
                        LabeledContent("推荐强度", value: strength.formatted(.number.precision(.fractionLength(2))))
                    }
                    if !asset.recommendedCheckpoint.isEmpty {
                        LabeledContent("推荐模型", value: asset.recommendedCheckpoint)
                    }
                    if !asset.notes.isEmpty {
                        Text(asset.notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        onUse()
                    } label: {
                        Label("用于 AI 绘画", systemImage: "wand.and.stars")
                    }
                }
            }
            .navigationTitle("资产详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct AiAssetPreview: View {
    let asset: AiAssetDisplayItem

    var body: some View {
        Group {
            if let url = URL(string: asset.previewImage), !asset.previewImage.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.pink.opacity(0.12))
            .overlay {
                Text(String(asset.displayName.prefix(2)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
            }
    }
}

private struct AiAssetMetadata {
    private let values: [String: Any]

    init(json: String?) {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            values = [:]
            return
        }
        values = object
    }

    var previewImage: String {
        guard let value = firstText("preview_image", "previewImage", "preview_url", "previewUrl") else { return "" }
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("//") || value.hasPrefix("data:image/") || value.hasPrefix("/") {
            return value
        }
        return ""
    }

    func firstText(_ keys: String...) -> String? {
        for key in keys {
            if let text = values[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    func firstNumber(_ keys: String...) -> Double? {
        for key in keys {
            if let number = values[key] as? NSNumber {
                return number.doubleValue
            }
            if let text = values[key] as? String, let number = Double(text) {
                return number
            }
        }
        return nil
    }

    func bool(_ key: String) -> Bool {
        if let value = values[key] as? Bool {
            return value
        }
        if let value = values[key] as? NSNumber {
            return value.boolValue
        }
        return false
    }

    func mergedTags(_ keys: String...) -> String {
        var seen = Set<String>()
        var tags: [String] = []
        for key in keys {
            guard let text = firstText(key) else { continue }
            for rawTag in text.split(separator: ",") {
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
