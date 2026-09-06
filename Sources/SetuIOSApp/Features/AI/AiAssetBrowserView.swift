import SetuIOSCore
import SwiftUI

struct AiAssetBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AiCapabilityResponse> = .idle
    @State private var activeKind: AiAssetKind = .lora
    @State private var target: AiDraftAssetTarget = .primary
    @State private var searchText = ""
    @State private var categoryFilter = "ALL"
    @State private var audienceFilter: AiAssetAudienceFilter = .all
    @State private var recommendedCheckpointFilter = "ALL"
    @State private var selectedStyles: [AiSelectedStyleAsset] = []
    @State private var generationMode = "SINGLE"
    @State private var currentDraft = AiDrawDraftStore.load()
    @State private var didRestoreCache = false
    @State private var selectedAsset: AiAssetDisplayItem?
    @State private var feedback: SetuFeedback?

    var body: some View {
        SetuBoard {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "风格与角色", subtitle: "选择附加画风、角色或风格预设，应用到当前创作")
                        SetuFilterBar(
                            options: AiAssetKind.allCases.map { .init(value: $0, title: $0.title) },
                            selection: $activeKind, accessibilityTitle: "内容类型"
                        )
                        .onChange(of: activeKind) {
                            categoryFilter = "ALL"
                            applyDefaultRecommendedCheckpointFilter()
                            saveCache()
                        }

                        if allowsTargetSelection {
                            Picker("写入目标", selection: $target) {
                                Text("主角色").tag(AiDraftAssetTarget.primary)
                                Text("副角色").tag(AiDraftAssetTarget.secondary)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
            }

            if activeKind == .style {
                currentStylesSection
            }

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }

            }

            switch state {
            case .idle, .loading:
                Section {
                    SetuEmptyState(
                        title: "正在加载风格与角色",
                        message: "正在同步可用的画风、角色与风格预设",
                        systemImage: activeKind.systemImage,
                        isLoading: true
                    )
                }

            case .failed(let message):
                Section {
                    SetuEmptyState(
                        title: "风格与角色加载失败",
                        message: message,
                        systemImage: "photo.stack",
                        actionTitle: "重试",
                        action: { Task { await load() } }
                    )
                }

            case .loaded(let capabilities):
                let items = activeKind.items(from: capabilities)
                let categories = categories(for: items)
                let checkpoints = recommendedCheckpoints(for: items)
                let filteredItems = filtered(items)

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "筛选", subtitle: "\(activeKind.title) 共 \(items.count) 个可用选项")
                            TextField("搜索名称、分类或画面关键词", text: $searchText)
                                #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                #endif

                            Picker("内容分级", selection: $audienceFilter) {
                                ForEach(AiAssetAudienceFilter.allCases) { filter in
                                    Text(filter.title(countIn: items)).tag(filter)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("推荐基础画风", selection: $recommendedCheckpointFilter) {
                                Text("全部基础画风").tag("ALL")
                                ForEach(checkpoints) { checkpoint in
                                    Text(checkpoint.title).tag(checkpoint.value)
                                }
                            }

                            Picker("分类", selection: $categoryFilter) {
                                Text("全部").tag("ALL")
                                ForEach(categories, id: \.self) { category in
                                    Text(category).tag(category)
                                }
                            }
                        }
                    }
                }

                Section {
                    SetuSectionHeader(
                        title: activeKind.title,
                        subtitle: "\(filteredItems.count)/\(items.count) 个匹配结果"
                    )
                    .padding(.horizontal, SetuSpacing.lg)
                    .padding(.top, SetuSpacing.xs)

                    if items.isEmpty {
                        SetuEmptyState(
                            title: "暂无可用选项",
                            message: "这类风格或角色暂未开放，可以稍后刷新查看。",
                            systemImage: activeKind.systemImage,
                            actionTitle: "刷新",
                            action: { Task { await load() } }
                        )

                    } else if filteredItems.isEmpty {
                        SetuEmptyState(
                            title: "暂无匹配选项",
                            message: "清除筛选后可查看全部风格与角色。",
                            systemImage: activeKind.systemImage,
                            actionTitle: "清除筛选",
                            action: clearFilters
                        )

                    } else {
                        SetuMosaic(items: filteredItems, aspectRatio: { _ in 1 }) { asset in
                            SetuCard {
                                AiAssetActionRow(
                                    asset: asset,
                                    selectionState: selectionState(for: asset),
                                    onSelect: { applyToDrawDraft(asset) },
                                    onDetail: { selectedAsset = asset }
                                )
                            }

                        }
                    }
                }
            }
        }

        .setuBackground()
        .navigationTitle("风格与角色")
        .setuFeedbackPresentation($feedback)
        .setuActionDock {

            Button("应用并返回（已选 \(selectedAssetCount) 项）") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandOnLight)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("ai.assets.apply")

        }
        .onAppear { restoreCacheIfNeeded() }
        .onChange(of: searchText) { saveCache() }
        .onChange(of: categoryFilter) { saveCache() }
        .onChange(of: audienceFilter) { saveCache() }
        .onChange(of: recommendedCheckpointFilter) { saveCache() }
        .onChange(of: target) { saveCache() }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedAsset) { asset in
            AiAssetDetailSheet(asset: asset) {
                applyToDrawDraft(asset)
            }
        }
    }

    private var selectedAssetCount: Int {
        let primary = currentDraft.characterId.isEmpty && currentDraft.loraName.isEmpty ? 0 : 1
        let secondary = currentDraft.generationMode == "DUAL"
            && (!currentDraft.secondCharacterId.isEmpty || !currentDraft.secondLoraName.isEmpty) ? 1 : 0
        return selectedStyles.filter(\.isEnabled).count + primary + secondary
    }

    private var allowsTargetSelection: Bool {
        activeKind != .style && generationMode == "DUAL"
    }

    @ViewBuilder
    private var currentStylesSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "当前风格", subtitle: "点击风格可启用或暂停，移除后会同步草稿")
                    if selectedStyles.isEmpty {
                        SetuEmptyState(
                            title: "还没有选择风格",
                            message: "从下方选择一个风格预设",
                            systemImage: "paintpalette"
                        )
                        .padding(.vertical, -SetuSpacing.sm)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SetuSpacing.sm) {
                                ForEach(selectedStyles) { style in
                                    AiSelectedStyleChip(
                                        style: style,
                                        onToggle: { toggleStyle(style.id) },
                                        onRemove: { removeStyle(style.id) }
                                    )
                                }
                            }
                            .padding(.vertical, SetuSpacing.xs)
                        }

                        Button(role: .destructive) {
                            selectedStyles.removeAll()
                            persistSelectedStyles()
                            syncSelectedStylesToDraft()
                        } label: {
                            Label("清空风格", systemImage: "trash")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }

    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.capabilities())
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func clearFilters() {
        searchText = ""
        categoryFilter = "ALL"
        audienceFilter = .all
        recommendedCheckpointFilter = "ALL"
        saveCache()
    }

    private func categories(for items: [AiAssetDisplayItem]) -> [String] {
        Array(Set(items.map(\.categoryPath)))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    private func recommendedCheckpoints(for items: [AiAssetDisplayItem]) -> [AiCheckpointFilterOption] {
        let values = Array(Set(items.map(\.recommendedCheckpoint)))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCompare($1) == .orderedAscending }

        return values.enumerated().map { index, value in
            let resolvedTitle = items.first(where: { $0.recommendedCheckpoint == value })?
                .recommendedCheckpointTitle ?? ""
            let title = resolvedTitle.isEmpty || resolvedTitle == "推荐基础画风"
                ? "基础画风 \(index + 1)"
                : resolvedTitle
            return AiCheckpointFilterOption(value: value, title: title)
        }
    }

    private func filtered(_ items: [AiAssetDisplayItem]) -> [AiAssetDisplayItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { asset in
            if categoryFilter != "ALL", asset.categoryPath != categoryFilter {
                return false
            }
            if !audienceFilter.includes(asset) {
                return false
            }
            if recommendedCheckpointFilter != "ALL", asset.recommendedCheckpoint != recommendedCheckpointFilter {
                return false
            }
            guard !keyword.isEmpty else { return true }
            return [
                asset.displayName,
                asset.name,
                asset.category,
                asset.categoryType,
                asset.triggerWords,
                asset.recommendedCheckpoint,
                asset.notes,
            ].contains { $0.lowercased().contains(keyword) }
        }
    }

    private func applyToDrawDraft(_ asset: AiAssetDisplayItem) {
        if selectionState(for: asset) != nil {
            deselectAsset(asset)
            selectedAsset = nil
            return
        }
        if asset.kind == .style {
            addOrEnableStyle(asset)
            feedback = .success("\(asset.displayName) 已加入当前风格")
            selectedAsset = nil
            return
        }
        AiDrawDraftStore.applyAsset(
            kind: asset.draftKind,
            target: allowsTargetSelection ? target : .primary,
            name: asset.name,
            triggerWords: asset.triggerWords,
            negativeTags: asset.negativeTags,
            recommendedStrength: asset.recommendedStrength,
            recommendedCheckpoint: asset.recommendedCheckpoint,
            linkedLoraName: asset.linkedLoraName
        )
        currentDraft = AiDrawDraftStore.load()
        let targetTitle = asset.kind == .style ? "全局风格" : (target == .secondary ? "副角色" : "主角色")
        feedback = .success("\(asset.displayName) 已写入 AI 绘画草稿：\(targetTitle)")
        selectedAsset = nil
    }

    private func deselectAsset(_ asset: AiAssetDisplayItem) {
        if asset.kind == .style {
            removeStyle(asset.id)
            feedback = .info("\(asset.displayName) 已从当前风格移除")
            return
        }
        AiDrawDraftStore.removeAsset(
            kind: asset.draftKind,
            target: allowsTargetSelection ? target : .primary
        )
        currentDraft = AiDrawDraftStore.load()
        feedback = .info("\(asset.displayName) 已取消选择")
    }

    private func addOrEnableStyle(_ asset: AiAssetDisplayItem) {
        let selected = AiSelectedStyleAsset(asset: asset)
        if let index = selectedStyles.firstIndex(where: { $0.id == selected.id }) {
            selectedStyles[index].isEnabled = true
        } else {
            selectedStyles.append(selected)
        }
        persistSelectedStyles()
        syncSelectedStylesToDraft()
    }

    private func toggleStyle(_ id: String) {
        guard let index = selectedStyles.firstIndex(where: { $0.id == id }) else { return }
        selectedStyles[index].isEnabled.toggle()
        persistSelectedStyles()
        syncSelectedStylesToDraft()
    }

    private func removeStyle(_ id: String) {
        selectedStyles.removeAll { $0.id == id }
        persistSelectedStyles()
        syncSelectedStylesToDraft()
    }

    private func syncSelectedStylesToDraft() {
        let enabled = selectedStyles.filter(\.isEnabled)
        AiDrawDraftStore.updateSelectedStyles(
            styleTags: mergeTags(enabled.map(\.triggerWords)),
            negativePrompt: mergeTags(enabled.map(\.negativeTags)),
            recommendedCheckpoint: enabled.first(where: { !$0.recommendedCheckpoint.isEmpty })?.recommendedCheckpoint
        )
        currentDraft = AiDrawDraftStore.load()
    }

    private func selectionState(for asset: AiAssetDisplayItem) -> AiAssetSelectionState? {
        switch asset.kind {
        case .style:
            guard let style = selectedStyles.first(where: { $0.id == asset.id }) else { return nil }
            return style.isEnabled ? .enabledStyle : .disabledStyle
        case .lora:
            let selectedName = allowsTargetSelection && target == .secondary ? currentDraft.secondLoraName : currentDraft.loraName
            guard selectedName == asset.name else { return nil }
            return allowsTargetSelection && target == .secondary ? .secondarySelected : .primarySelected
        case .character:
            let selectedName = allowsTargetSelection && target == .secondary ? currentDraft.secondCharacterId : currentDraft.characterId
            guard selectedName == asset.name else { return nil }
            return allowsTargetSelection && target == .secondary ? .secondarySelected : .primarySelected
        }
    }

    private func mergeTags(_ values: [String]) -> String {
        var seen = Set<String>()
        var tags: [String] = []
        for value in values {
            for rawTag in value.split(separator: ",") {
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = tag.lowercased().replacingOccurrences(of: "_", with: " ")
                guard !tag.isEmpty, !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                tags.append(tag)
            }
        }
        return tags.joined(separator: ", ")
    }

    private func restoreCacheIfNeeded() {
        guard !didRestoreCache else { return }
        let cache = AiAssetBrowserCacheStore.load()
        currentDraft = AiDrawDraftStore.load()
        activeKind = cache.activeKind
        target = cache.target
        searchText = cache.searchText
        categoryFilter = cache.categoryFilter
        audienceFilter = cache.audienceFilter
        recommendedCheckpointFilter = cache.recommendedCheckpointFilter
        selectedStyles = cache.selectedStyles
        generationMode = AiDrawDraftStore.load().generationMode
        if generationMode != "DUAL" {
            target = .primary
        }
        if activeKind == .style {
            applyDefaultRecommendedCheckpointFilter()
        }
        didRestoreCache = true
    }

    private func applyDefaultRecommendedCheckpointFilter() {
        guard activeKind == .style else {
            recommendedCheckpointFilter = "ALL"
            return
        }
        let checkpoint = currentDraft.checkpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        recommendedCheckpointFilter = checkpoint.isEmpty ? "ALL" : checkpoint
    }

    private func saveCache() {
        guard didRestoreCache else { return }
        AiAssetBrowserCacheStore.save(
            AiAssetBrowserCache(
                activeKind: activeKind,
                target: target,
                searchText: searchText,
                categoryFilter: categoryFilter,
                audienceFilter: audienceFilter,
                recommendedCheckpointFilter: recommendedCheckpointFilter,
                selectedStyles: selectedStyles
            )
        )
    }

    private func persistSelectedStyles() {
        saveCache()
    }
}

private enum AiAssetKind: String, CaseIterable, Identifiable, Codable {
    case lora
    case character
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lora: "附加画风"
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

    var fallbackDisplayName: String {
        switch self {
        case .lora: "未命名附加画风"
        case .character: "未命名角色"
        case .style: "未命名风格"
        }
    }

    func items(from capabilities: AiCapabilityResponse) -> [AiAssetDisplayItem] {
        let checkpointTitles = checkpointDisplayNames(from: capabilities.checkpoints)
        switch self {
        case .lora:
            return capabilities.loras.map {
                AiAssetDisplayItem(
                    item: $0,
                    kind: self,
                    fallbackCategory: "未分类",
                    checkpointTitles: checkpointTitles
                )
            }
        case .character:
            return capabilities.characters.map {
                AiAssetDisplayItem(
                    item: $0,
                    kind: self,
                    fallbackCategory: "未分类角色",
                    checkpointTitles: checkpointTitles
                )
            }
        case .style:
            return capabilities.promptPresets.map {
                AiAssetDisplayItem(styleItem: $0, kind: self, checkpointTitles: checkpointTitles)
            }
        }
    }

    private func checkpointDisplayNames(from checkpoints: [AiCapabilityItem]) -> [String: String] {
        checkpoints.reduce(into: [:]) { result, checkpoint in
            guard result[checkpoint.name] == nil else { return }
            let displayName = AiAssetDisplayName.resolve(
                preferred: [checkpoint.displayName],
                rawName: checkpoint.name,
                fallback: ""
            )
            result[checkpoint.name] = displayName.isEmpty
                ? "基础画风 \(result.count + 1)"
                : displayName
        }
    }
}

private struct AiCheckpointFilterOption: Identifiable {
    let value: String
    let title: String

    var id: String { value }
}

private enum AiAssetDisplayName {
    static func resolve(preferred: [String?], rawName: String, fallback: String) -> String {
        for candidate in preferred {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty, !isTechnical(value, rawName: rawName) else { continue }
            return value
        }
        return fallback
    }

    private static func isTechnical(_ value: String, rawName: String) -> Bool {
        let normalized = value.lowercased()
        if normalized.contains("/")
            || normalized.contains("\\")
            || [".safetensors", ".ckpt", ".pt", ".pth", ".bin"].contains(where: normalized.hasSuffix) {
            return true
        }
        guard value.caseInsensitiveCompare(rawName) == .orderedSame else { return false }
        let hasWhitespace = value.contains(where: \.isWhitespace)
        let hasNonASCII = value.unicodeScalars.contains { $0.value > 0x7F }
        return !hasWhitespace && !hasNonASCII
    }
}

private enum AiAssetAudienceFilter: String, CaseIterable, Identifiable, Codable {
    case all
    case sfw
    case nsfw

    var id: String { rawValue }

    func title(countIn items: [AiAssetDisplayItem]) -> String {
        let count = items.filter { includes($0) }.count
        switch self {
        case .all:
            return "全部 \(count)"
        case .sfw:
            return "普通内容 \(count)"
        case .nsfw:
            return "成人内容 \(count)"
        }
    }

    func includes(_ asset: AiAssetDisplayItem) -> Bool {
        switch self {
        case .all: true
        case .sfw: !asset.nsfwOnly
        case .nsfw: asset.nsfwOnly
        }
    }
}

private enum AiAssetSelectionState {
    case primarySelected
    case secondarySelected
    case enabledStyle
    case disabledStyle

    var title: String {
        switch self {
        case .primarySelected:
            return "已选为主要搭配"
        case .secondarySelected:
            return "已选为第二搭配"
        case .enabledStyle:
            return "已启用"
        case .disabledStyle:
            return "已禁用"
        }
    }

    var systemImage: String {
        switch self {
        case .disabledStyle:
            return "pause.circle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disabledStyle:
            return SetuColor.danger
        case .enabledStyle:
            return SetuColor.success
        case .primarySelected, .secondarySelected:
            return SetuColor.brandInk
        }
    }

    var pillTone: SetuPillTone {
        switch self {
        case .disabledStyle:
            return .danger
        case .enabledStyle:
            return .success
        case .primarySelected, .secondarySelected:
            return .brand
        }
    }
}

private struct AiSelectedStyleAsset: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let triggerWords: String
    let negativeTags: String
    let recommendedCheckpoint: String
    var isEnabled: Bool

    init(
        id: String,
        displayName: String,
        triggerWords: String,
        negativeTags: String,
        recommendedCheckpoint: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.triggerWords = triggerWords
        self.negativeTags = negativeTags
        self.recommendedCheckpoint = recommendedCheckpoint
        self.isEnabled = isEnabled
    }

    init(asset: AiAssetDisplayItem) {
        self.init(
            id: asset.id,
            displayName: asset.displayName,
            triggerWords: asset.triggerWords,
            negativeTags: asset.negativeTags,
            recommendedCheckpoint: asset.recommendedCheckpoint
        )
    }
}

private struct AiAssetBrowserCache: Codable {
    var activeKind: AiAssetKind = .lora
    var target: AiDraftAssetTarget = .primary
    var searchText: String = ""
    var categoryFilter: String = "ALL"
    var audienceFilter: AiAssetAudienceFilter = .all
    var recommendedCheckpointFilter: String = "ALL"
    var selectedStyles: [AiSelectedStyleAsset] = []
}

enum AiAssetBrowserCacheStore {
    #if DEBUG
    private static var previewCache: AiAssetBrowserCache?

    static func activatePreviewStorage() { previewCache = AiAssetBrowserCache() }
    #endif

    private static let key = "icu.yukiryou.setu.aiAssetBrowserCache"

    fileprivate static func load() -> AiAssetBrowserCache {
        #if DEBUG
        if let previewCache { return previewCache }
        #endif
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(AiAssetBrowserCache.self, from: data) else {
            return AiAssetBrowserCache()
        }
        return cache
    }

    fileprivate static func save(_ cache: AiAssetBrowserCache) {
        #if DEBUG
        if previewCache != nil {
            previewCache = cache
            return
        }
        #endif
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func enabledStyleDisplayNames() -> [String] {
        load()
            .selectedStyles
            .filter(\.isEnabled)
            .map(\.displayName)
    }

    static func clearSelectedStyles() {
        var cache = load()
        cache.selectedStyles.removeAll()
        save(cache)
    }
}

private struct AiSelectedStyleChip: View {
    let style: AiSelectedStyleAsset
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let tone: SetuPillTone = style.isEnabled ? .success : .danger

        HStack(spacing: 6) {
            Button {
                onToggle()
            } label: {
                Text(style.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(style.displayName)
            .accessibilityValue(style.isEnabled ? "已启用" : "已禁用")
            .accessibilityAddTraits(style.isEnabled ? .isSelected : [])

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除 \(style.displayName)")
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.xs)
        .background(tone.fill.opacity(0.18))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(tone.foreground.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
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
    let recommendedCheckpointTitle: String
    let linkedLoraName: String
    let previewImage: String
    let notes: String
    let nsfwOnly: Bool

    init(
        item: AiCapabilityItem,
        kind: AiAssetKind,
        fallbackCategory: String,
        checkpointTitles: [String: String]
    ) {
        let metadata = AiAssetMetadata(json: item.metadataJson)
        self.id = "\(kind.rawValue):\(item.id)"
        self.kind = kind
        self.name = item.name
        self.displayName = AiAssetDisplayName.resolve(
            preferred: [metadata.firstText("display_name", "displayName"), item.displayName],
            rawName: item.name,
            fallback: kind.fallbackDisplayName
        )
        self.category = metadata.firstText("category", "category_name", "categoryDisplayName", "franchise") ?? fallbackCategory
        self.categoryType = metadata.firstText("category_type", "categoryType", "type") ?? ""
        self.triggerWords = metadata.firstText("trigger_words", "triggerWords", "trigger") ?? ""
        self.negativeTags = metadata.firstText("default_negative", "defaultNegative") ?? ""
        self.recommendedStrength = metadata.firstNumber("recommended_strength", "recommendedStrength", "lora_strength", "loraStrength")
        let recommendedCheckpoint = metadata.firstText("recommended_checkpoint", "recommendedCheckpoint") ?? ""
        self.recommendedCheckpoint = recommendedCheckpoint
        self.recommendedCheckpointTitle = recommendedCheckpoint.isEmpty
            ? ""
            : checkpointTitles[recommendedCheckpoint] ?? "推荐基础画风"
        self.linkedLoraName = metadata.firstText("lora_name", "loraName") ?? ""
        self.previewImage = metadata.previewImage
        self.notes = metadata.firstText("notes", "description", "summary") ?? ""
        self.nsfwOnly = metadata.bool("nsfw_only") || metadata.bool("nsfwOnly")
    }

    init(styleItem item: AiCapabilityItem, kind: AiAssetKind, checkpointTitles: [String: String]) {
        let metadata = AiAssetMetadata(json: item.metadataJson)
        self.id = "\(kind.rawValue):\(item.id)"
        self.kind = kind
        self.name = item.name
        self.displayName = AiAssetDisplayName.resolve(
            preferred: [metadata.firstText("display_name", "displayName", "name"), item.displayName],
            rawName: item.name,
            fallback: kind.fallbackDisplayName
        )
        self.category = metadata.firstText("category") ?? "风格预设"
        self.categoryType = metadata.firstText("category_type", "categoryType") ?? "风格"
        self.triggerWords = metadata.mergedTags("trigger_words", "triggerWords", "default_positive", "defaultPositive", "style_tags", "styleTags")
        self.negativeTags = metadata.firstText("default_negative", "defaultNegative") ?? ""
        self.recommendedStrength = nil
        let recommendedCheckpoint = metadata.firstText("recommended_checkpoint", "recommendedCheckpoint") ?? ""
        self.recommendedCheckpoint = recommendedCheckpoint
        self.recommendedCheckpointTitle = recommendedCheckpoint.isEmpty
            ? ""
            : checkpointTitles[recommendedCheckpoint] ?? "推荐基础画风"
        self.linkedLoraName = ""
        self.previewImage = metadata.previewImage
        self.notes = metadata.firstText("notes", "description") ?? ""
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
        return "适用于当前创作"
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
    let selectionState: AiAssetSelectionState?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AiAssetPreview(asset: asset)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(asset.displayName)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Spacer()
                    if asset.nsfwOnly {
                        SetuPill(text: "成人内容", systemImage: "exclamationmark.triangle", tone: .danger)
                    }
                    if let selectionState {
                        SetuPill(
                            text: selectionState.title,
                            systemImage: selectionState.systemImage,
                            tone: selectionState.pillTone
                        )
                    }
                }
                Text(asset.summary)
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(asset.categoryPath.isEmpty ? "未分组" : asset.categoryPath, systemImage: asset.kind.systemImage)
                    if let strength = asset.recommendedStrength {
                        Label(strength.formatted(.number.precision(.fractionLength(2))), systemImage: "dial.low")
                    }
                }
                .font(.caption2)
                .foregroundStyle(SetuColor.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, selectionState == nil ? 0 : 8)
        .background {
            if let selectionState {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectionState.color.opacity(0.10))
            }
        }
        .overlay {
            if let selectionState {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectionState.color.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

private struct AiAssetActionRow: View {
    let asset: AiAssetDisplayItem
    let selectionState: AiAssetSelectionState?
    let onSelect: () -> Void
    let onDetail: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onSelect()
            } label: {
                AiAssetRow(asset: asset, selectionState: selectionState)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("使用 \(asset.displayName)")
            .accessibilityValue(selectionState?.title ?? "未选择")

            Button {
                onDetail()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(SetuColor.brandInk)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("查看 \(asset.displayName) 详情")
        }
    }
}

private struct AiAssetDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let asset: AiAssetDisplayItem
    let onUse: () -> Void

    var body: some View {
        NavigationStack {
            SetuBoard {
                Section {
                    SetuCard {
                        HStack(spacing: 14) {
                            AiAssetPreview(asset: asset)
                                .frame(width: 86, height: 86)
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text(asset.displayName)
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                                if asset.nsfwOnly {
                                    SetuPill(text: "仅限成人内容", systemImage: "exclamationmark.triangle", tone: .danger)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "详情", subtitle: "应用到当前 AI 创作的风格与角色信息")
                            AiAssetDetailRow(title: "类型", value: asset.kind.title)
                            AiAssetDetailRow(title: "目录", value: asset.categoryPath.isEmpty ? "未分组" : asset.categoryPath)
                            if !asset.triggerWords.isEmpty {
                                AiAssetDetailRow(title: "画面关键词", value: asset.triggerWords)
                            }
                            if !asset.negativeTags.isEmpty {
                                AiAssetDetailRow(title: "需要避开的内容", value: asset.negativeTags)
                            }
                            if let strength = asset.recommendedStrength {
                                AiAssetDetailRow(
                                    title: "推荐强度",
                                    value: strength.formatted(.number.precision(.fractionLength(2)))
                                )
                            }
                            if !asset.recommendedCheckpointTitle.isEmpty {
                                AiAssetDetailRow(title: "推荐基础画风", value: asset.recommendedCheckpointTitle)
                            }
                            if !asset.notes.isEmpty {
                                Text(asset.notes)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Section {
                    SetuCard {
                        Button {
                            onUse()
                        } label: {
                            Label("用于 AI 绘画", systemImage: "wand.and.stars")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(SetuColor.brandInk)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }

            }

            .setuBackground()
            .navigationTitle("风格与角色详情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct AiAssetDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SetuColor.textTertiary)
            Text(value)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SetuSpacing.xs)
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
            .fill(SetuColor.brandSoft.opacity(0.18))
            .overlay {
                Text(String(asset.displayName.prefix(2)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
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
