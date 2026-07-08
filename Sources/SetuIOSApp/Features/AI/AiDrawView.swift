import SetuIOSCore
import SwiftUI

struct AiDrawView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var statusState: LoadState<AiServiceStatusResponse> = .idle
    @State private var capabilityState: LoadState<AiCapabilityResponse> = .idle
    @State private var promptCn = ""
    @State private var styleTags = ""
    @State private var positivePrompt = ""
    @State private var negativePrompt = AiDrawDefaults.defaultNegativePrompt
    @State private var styleNotes = ""
    @State private var width = 768
    @State private var height = 1024
    @State private var steps = 28
    @State private var cfg = 7.0
    @State private var nsfwMode = false
    @State private var nsfwVisibilityLevel = "STANDARD"
    @State private var generationMode = "SINGLE"
    @State private var selectedCheckpoint = ""
    @State private var selectedLora = ""
    @State private var loraStrength = 0.8
    @State private var selectedCharacter = ""
    @State private var selectedSecondLora = ""
    @State private var secondLoraStrength = 0.65
    @State private var selectedSecondCharacter = ""
    @State private var isTranslating = false
    @State private var isSubmitting = false
    @State private var promptPreparationStatus: String?
    @State private var message: String?
    @State private var draftLoaded = false
    @State private var isApplyingDraft = false
    @State private var loadedDraftUpdatedAt: Date?
    @State private var isNavigatingToAssetBrowser = false
    @State private var enabledStylePresetNames: [String] = []

    var body: some View {
        Form {
            statusSection
            promptSection
            generationSection
            assetSection
            actionSection
        }
        .setuBackground()
        .navigationTitle("AI 绘画")
        .onAppear {
            applyDraftIfNeeded()
            refreshEnabledStylePresets()
        }
        .onDisappear { handleDisappear() }
        .onChange(of: promptCn) { saveDraft() }
        .onChange(of: positivePrompt) { saveDraft() }
        .onChange(of: width) { saveDraft() }
        .onChange(of: height) { saveDraft() }
        .onChange(of: steps) { saveDraft() }
        .onChange(of: cfg) { saveDraft() }
        .onChange(of: nsfwMode) { saveDraft() }
        .onChange(of: nsfwVisibilityLevel) { saveDraft() }
        .onChange(of: generationMode) { saveDraft() }
        .onChange(of: selectedCheckpoint) { saveDraft() }
        .onChange(of: selectedLora) { saveDraft() }
        .onChange(of: loraStrength) { saveDraft() }
        .onChange(of: selectedCharacter) { saveDraft() }
        .onChange(of: selectedSecondLora) { saveDraft() }
        .onChange(of: secondLoraStrength) { saveDraft() }
        .onChange(of: selectedSecondCharacter) { saveDraft() }
        .onChange(of: styleTags) { saveDraft() }
        .onChange(of: negativePrompt) { saveDraft() }
        .onChange(of: styleNotes) { saveDraft() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    router.navigate(to: .aiHistory)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("AI 绘画历史")

                Button {
                    router.navigate(to: .aiDeleteRequests)
                } label: {
                    Image(systemName: "xmark.bin")
                }
                .accessibilityLabel("我的删除记录")
            }
        }
        .task { await loadMetadata() }
        .refreshable { await loadMetadata() }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "生成队列")
                    switch statusState {
                    case .idle, .loading:
                        HStack {
                            ProgressView()
                                .tint(SetuColor.brandPink)
                            Text("正在加载")
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    case .failed(let message):
                        Text(message)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.danger)
                    case .loaded(let status):
                        HStack(spacing: SetuSpacing.sm) {
                            SetuPill(text: status.statusTitle, systemImage: "sparkles", tone: status.statusTitle == "可用" ? .success : .warning)
                            if let queued = status.queuedCount {
                                SetuPill(text: "\(queued) 排队", systemImage: "clock", tone: .info)
                            }
                        }
                        if let message = status.message, !message.isEmpty {
                            Text(message)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                        Label("\(status.activeWorkerCount ?? 0)/\(status.workerCount ?? 0) 可用节点", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
            }
        }
        .setuListRow()
    }

    private var promptSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "提示词")
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text("自然语言描述")
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.textPrimary)
                        TextField("例如：银发少女，雨夜街角，霓虹灯，电影感光影", text: $promptCn, axis: .vertical)
                            .lineLimit(5...10)
                            .textFieldStyle(.roundedBorder)
                        Text("\(promptCn.count) 字")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textTertiary)
                    }

                    Button {
                        Task { await preparePrompt() }
                    } label: {
                        HStack {
                            if isTranslating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "wand.and.sparkles")
                            }
                            Text(isTranslating ? "正在生成提示词" : "生成提示词")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SetuColor.brandPink)
                    .controlSize(.large)
                    .disabled(!canPreparePrompt)

                    if let promptPreparationStatus {
                        SetuPill(text: promptPreparationStatus, systemImage: isTranslating ? "clock" : "checkmark.circle", tone: .brand)
                    } else if !serviceReady, !hasPresetPromptSeed {
                        SetuPill(text: serviceUnavailableText, systemImage: "exclamationmark.triangle", tone: .warning)
                    }

                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text("生成后的提示词")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SetuColor.textPrimary)
                        TextField("正向提示词会在生成后写入，也可以手动编辑", text: $positivePrompt, axis: .vertical)
                            .lineLimit(4...8)
                            .textFieldStyle(.roundedBorder)
                        TextField("反向提示词", text: $negativePrompt, axis: .vertical)
                            .lineLimit(4...8)
                            .textFieldStyle(.roundedBorder)
                        TextField("风格说明", text: $styleNotes, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .setuListRow()
    }

    private var generationSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "生成参数")
                    canvasPresetGrid
                    Stepper("宽度 \(width)", value: $width, in: 512...1536, step: 64)
                    Stepper("高度 \(height)", value: $height, in: 512...1536, step: 64)
                    Stepper("步数 \(steps)", value: $steps, in: 12...60)
                    HStack {
                        Text("CFG")
                        Slider(value: $cfg, in: 3...12, step: 0.5)
                            .tint(SetuColor.brandPink)
                        Text(cfg.formatted(.number.precision(.fractionLength(1))))
                            .monospacedDigit()
                    }
                    Toggle("NSFW 模式", isOn: $nsfwMode)
                        .tint(SetuColor.brandPink)
                    if nsfwMode {
                        Picker("NSFW 可见性强度", selection: $nsfwVisibilityLevel) {
                            Text("轻度").tag("LIGHT")
                            Text("标准").tag("STANDARD")
                            Text("强力").tag("STRONG")
                        }
                        Text("可见性强度会传给生成提示词接口，影响遮挡、服装和局部细节相关提示词。")
                            .font(.footnote)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                    Picker("生成模式", selection: $generationMode) {
                        Text("单角色").tag("SINGLE")
                        Text("双角色").tag("DUAL")
                    }
                }
            }
        }
        .setuListRow()
    }

    private var canvasPresetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("画布比例")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(AiCanvasPreset.allCases) { preset in
                    Button {
                        width = preset.width
                        height = preset.height
                        saveDraft()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.title)
                                .font(.footnote.weight(.semibold))
                            Text("\(preset.width)x\(preset.height)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(width == preset.width && height == preset.height ? SetuColor.brandPink : SetuColor.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var assetSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "模型资产")
                    SetuNavigationRow(title: "浏览 AI 资产选择", subtitle: "选择 LoRA、角色和风格预设", systemImage: "photo.stack") {
                        isNavigatingToAssetBrowser = true
                        saveDraft()
                        router.navigate(to: .aiAssets)
                    }
                    if draftLoaded, hasAssetDraft {
                        SetuPill(text: "已载入资产草稿", systemImage: "checkmark.circle", tone: .success)
                    }
                    if !enabledStylePresetNames.isEmpty {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            Text("风格预设")
                                .font(.subheadline.weight(.semibold))
                            Text(enabledStylePresetNames.joined(separator: "、"))
                                .font(.headline)
                                .foregroundStyle(SetuColor.textPrimary)
                            Text("已选择 \(enabledStylePresetNames.count) 个")
                                .font(.footnote)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                    switch capabilityState {
                    case .idle, .loading:
                        ProgressView("正在加载模型")
                            .tint(SetuColor.brandPink)
                    case .failed(let message):
                        Text(message)
                            .foregroundStyle(SetuColor.danger)
                    case .loaded(let capabilities):
                        Picker("模型", selection: $selectedCheckpoint) {
                            Text("默认").tag("")
                            ForEach(capabilities.checkpoints) { item in
                                Text(item.displayName ?? item.name).tag(item.name)
                            }
                        }
                        Picker("LoRA", selection: $selectedLora) {
                            Text("不使用").tag("")
                            ForEach(capabilities.loras) { item in
                                Text(item.displayName ?? item.name).tag(item.name)
                            }
                        }
                        Picker("角色预设", selection: $selectedCharacter) {
                            Text("不使用").tag("")
                            ForEach(capabilities.characters) { item in
                                Text(item.displayName ?? item.name).tag(item.name)
                            }
                        }
                        if !selectedLora.isEmpty {
                            HStack {
                                Text("LoRA 强度")
                                Slider(value: $loraStrength, in: 0.1...1.5, step: 0.1)
                                    .tint(SetuColor.brandPink)
                                Text(loraStrength.formatted(.number.precision(.fractionLength(1))))
                                    .monospacedDigit()
                            }
                        }
                        if generationMode == "DUAL" {
                            Picker("副角色 LoRA", selection: $selectedSecondLora) {
                                Text("不使用").tag("")
                                ForEach(capabilities.loras) { item in
                                    Text(item.displayName ?? item.name).tag(item.name)
                                }
                            }
                            Picker("副角色预设", selection: $selectedSecondCharacter) {
                                Text("不使用").tag("")
                                ForEach(capabilities.characters) { item in
                                    Text(item.displayName ?? item.name).tag(item.name)
                                }
                            }
                            if !selectedSecondLora.isEmpty {
                                HStack {
                                    Text("副 LoRA 强度")
                                    Slider(value: $secondLoraStrength, in: 0.1...1.5, step: 0.1)
                                        .tint(SetuColor.brandPink)
                                    Text(secondLoraStrength.formatted(.number.precision(.fractionLength(1))))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            SetuPrimaryButton {
                Task { await submit() }
            } label: {
                Label(isSubmitting ? "提交中" : "创建生成任务", systemImage: "sparkles")
            }
            .disabled(!hasDrawablePrompt || isSubmitting || isTranslating)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
        .setuListRow()
    }

    private func loadMetadata() async {
        statusState = .loading
        capabilityState = .loading
        async let status = environment.aiGenerationClient.serviceStatus()
        async let capabilities = environment.aiGenerationClient.capabilities()
        do {
            statusState = .loaded(try await status)
        } catch {
            statusState = .failed(error.localizedDescription)
        }
        do {
            capabilityState = .loaded(try await capabilities)
        } catch {
            capabilityState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func preparePrompt() async -> Bool {
        let prompt = promptCn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            if applyPresetPromptToGeneratedFields() {
                promptPreparationStatus = "已使用已选预设写入提示词"
                message = nil
                saveDraft()
                return true
            }
            promptPreparationStatus = "先写一点你想画什么，或选择风格预设/角色/LoRA"
            return false
        }
        guard serviceReady else {
            if applyPresetPromptToGeneratedFields() {
                promptPreparationStatus = "AI 服务暂不可用，已使用已选预设写入提示词"
                message = nil
                saveDraft()
                return true
            }
            promptPreparationStatus = serviceUnavailableText
            return false
        }
        if generationMode == "DUAL", selectedSecondCharacter.isEmpty, selectedSecondLora.isEmpty {
            promptPreparationStatus = "双角色模式需要选择角色 B 或第二个 LoRA"
            return false
        }

        isTranslating = true
        promptPreparationStatus = "正在请求提示词生成"
        defer {
            isTranslating = false
        }
        do {
            var response = try await environment.aiGenerationClient.translatePrompt(
                AiPromptTranslateRequest(
                    promptCn: prompt,
                    styleTags: trimmedOptional(styleTags),
                    negativePrompt: trimmedOptional(negativePrompt),
                    nsfwMode: nsfwMode,
                    nsfwVisibilityLevel: nsfwMode ? nsfwVisibilityLevel : "STANDARD"
                )
            )
            if response.status != "COMPLETED", response.positive?.isEmpty != false {
                guard let id = response.id else {
                    throw AiDrawPromptPreparationError.missingTranslationId
                }
                promptPreparationStatus = "本地 Ollama 正在生成提示词"
                response = try await waitForPromptTranslation(id: id)
            }
            if let positive = response.positive, !positive.isEmpty {
                positivePrompt = positive
            }
            if let negative = response.negative, !negative.isEmpty {
                negativePrompt = negative
            } else if negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                negativePrompt = AiDrawDefaults.defaultNegativePrompt
            }
            if let styleNotes = response.styleNotes, !styleNotes.isEmpty {
                self.styleNotes = styleNotes
            }
            promptPreparationStatus = "提示词已生成，并已写入正向/反向提示词"
            message = nil
            saveDraft()
            return true
        } catch {
            promptPreparationStatus = nil
            message = "生成提示词失败：\(error.localizedDescription)"
            return false
        }
    }

    private func waitForPromptTranslation(id: Int) async throws -> AiPromptTranslateResponse {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let response = try await environment.aiGenerationClient.promptTranslation(id: id)
            switch response.status {
            case "COMPLETED":
                return response
            case "FAILED":
                throw AiDrawPromptPreparationError.translationFailed(response.errorMessage)
            default:
                promptPreparationStatus = "提示词生成中，正在等待结果"
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        throw AiDrawPromptPreparationError.translationTimedOut
    }

    private func submit() async {
        let prompt = promptCn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasDrawablePrompt else {
            message = "先填写自然语言描述、手动填写正向提示词，或选择风格预设/角色/LoRA"
            return
        }
        guard serviceReady else {
            message = serviceUnavailableText
            return
        }
        var promptPositive = positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if promptPositive.isEmpty {
            if !prompt.isEmpty {
                let prepared = await preparePrompt()
                guard prepared else { return }
                promptPositive = positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if applyPresetPromptToGeneratedFields() {
                promptPositive = presetPromptSeed
            }
        }
        let promptNegative = resolvedNegativePrompt
        isSubmitting = true
        message = nil
        defer { isSubmitting = false }
        do {
            let job = try await environment.aiGenerationClient.create(
                AiGenerationCreateRequest(
                    promptCn: prompt,
                    promptPositive: promptPositive,
                    promptNegative: promptNegative,
                    styleNotes: styleNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                    width: width,
                    height: height,
                    steps: steps,
                    cfg: cfg,
                    checkpoint: selectedCheckpoint.isEmpty ? nil : selectedCheckpoint,
                    generationMode: generationMode,
                    loraName: selectedLora.isEmpty ? nil : selectedLora,
                    loraStrength: selectedLora.isEmpty ? nil : loraStrength,
                    characterId: selectedCharacter.isEmpty ? nil : selectedCharacter,
                    secondLoraName: generationMode == "DUAL" && !selectedSecondLora.isEmpty ? selectedSecondLora : nil,
                    secondLoraStrength: generationMode == "DUAL" && !selectedSecondLora.isEmpty ? secondLoraStrength : nil,
                    secondCharacterId: generationMode == "DUAL" && !selectedSecondCharacter.isEmpty ? selectedSecondCharacter : nil,
                    nsfwMode: nsfwMode,
                    nsfwVisibilityLevel: nsfwMode ? nsfwVisibilityLevel : "STANDARD"
                )
            )
            message = "任务已创建，正在跟踪状态：#\(job.id)"
            saveDraft()
            await AiGenerationLiveActivityCenter.start(job: job, mobileClient: environment.mobileAppClient)
            router.navigate(to: .aiGenerationDetail(job.id))
        } catch {
            message = error.localizedDescription
        }
    }

    private var canPreparePrompt: Bool {
        (hasPresetPromptSeed || (!promptCn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && serviceReady))
            && !isTranslating
            && !isSubmitting
    }

    private var hasDrawablePrompt: Bool {
        !promptCn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasPresetPromptSeed
    }

    private var presetPromptSeed: String {
        styleTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPresetPromptSeed: Bool {
        !presetPromptSeed.isEmpty
    }

    private var resolvedNegativePrompt: String {
        let trimmed = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AiDrawDefaults.defaultNegativePrompt : trimmed
    }

    private var serviceReady: Bool {
        if case .loaded(let status) = statusState {
            return status.available
        }
        return false
    }

    private var serviceUnavailableText: String {
        if case .loaded(let status) = statusState {
            return status.message ?? status.statusTitle
        }
        if case .failed(let message) = statusState {
            return message
        }
        return "AI 服务状态加载中"
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    private func applyPresetPromptToGeneratedFields() -> Bool {
        guard hasPresetPromptSeed else { return false }
        if positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            positivePrompt = presetPromptSeed
        }
        if negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            negativePrompt = AiDrawDefaults.defaultNegativePrompt
        }
        return true
    }

    private var hasAssetDraft: Bool {
        !selectedCheckpoint.isEmpty
            || !selectedLora.isEmpty
            || !selectedCharacter.isEmpty
            || !selectedSecondLora.isEmpty
            || !selectedSecondCharacter.isEmpty
            || !styleTags.isEmpty
            || !isDefaultNegativePrompt
    }

    private func applyDraftIfNeeded() {
        guard let draft = AiDrawDraftStore.loadPendingExternalDraft() else {
            AiAssetBrowserCacheStore.clearSelectedStyles()
            enabledStylePresetNames = []
            draftLoaded = true
            return
        }
        guard loadedDraftUpdatedAt != draft.updatedAt else {
            draftLoaded = true
            return
        }
        isApplyingDraft = true
        promptCn = draft.promptCn
        positivePrompt = draft.promptPositive
        width = draft.width
        height = draft.height
        steps = draft.steps
        cfg = draft.cfg
        nsfwMode = draft.nsfwMode
        nsfwVisibilityLevel = draft.nsfwVisibilityLevel
        generationMode = draft.generationMode
        selectedCheckpoint = draft.checkpoint
        selectedLora = draft.loraName
        loraStrength = draft.loraStrength
        selectedCharacter = draft.characterId
        selectedSecondLora = draft.secondLoraName
        secondLoraStrength = draft.secondLoraStrength
        selectedSecondCharacter = draft.secondCharacterId
        styleTags = draft.styleTags
        negativePrompt = draft.negativePrompt.isEmpty ? AiDrawDefaults.defaultNegativePrompt : draft.negativePrompt
        styleNotes = draft.styleNotes
        loadedDraftUpdatedAt = draft.updatedAt
        draftLoaded = true
        isApplyingDraft = false
    }

    private func handleDisappear() {
        if isNavigatingToAssetBrowser {
            isNavigatingToAssetBrowser = false
        } else {
            AiDrawDraftStore.clear()
            AiAssetBrowserCacheStore.clearSelectedStyles()
        }
    }

    private func refreshEnabledStylePresets() {
        enabledStylePresetNames = AiAssetBrowserCacheStore.enabledStyleDisplayNames()
    }

    private func saveDraft() {
        guard draftLoaded, !isApplyingDraft else { return }
        AiDrawDraftStore.updateFromForm(
            promptCn: promptCn,
            promptPositive: positivePrompt,
            width: width,
            height: height,
            steps: steps,
            cfg: cfg,
            nsfwMode: nsfwMode,
            nsfwVisibilityLevel: nsfwVisibilityLevel,
            generationMode: generationMode,
            checkpoint: selectedCheckpoint,
            loraName: selectedLora,
            loraStrength: loraStrength,
            characterId: selectedCharacter,
            secondLoraName: selectedSecondLora,
            secondLoraStrength: secondLoraStrength,
            secondCharacterId: selectedSecondCharacter,
            styleTags: styleTags,
            negativePrompt: negativePrompt,
            styleNotes: styleNotes
        )
    }

    private var isDefaultNegativePrompt: Bool {
        negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines) == AiDrawDefaults.defaultNegativePrompt
    }
}

private enum AiCanvasPreset: String, CaseIterable, Identifiable {
    case portrait
    case square
    case landscape
    case tall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: "竖图"
        case .square: "方图"
        case .landscape: "横图"
        case .tall: "长竖图"
        }
    }

    var width: Int {
        switch self {
        case .portrait: 768
        case .square: 1024
        case .landscape: 1024
        case .tall: 832
        }
    }

    var height: Int {
        switch self {
        case .portrait: 1024
        case .square: 1024
        case .landscape: 768
        case .tall: 1216
        }
    }
}

enum AiDrawDefaults {
    static let defaultNegativePrompt = "low quality, worst quality, bad anatomy, bad hands, extra fingers, missing fingers, deformed, blurry, text, watermark, logo, cropped"
}

private enum AiDrawPromptPreparationError: LocalizedError {
    case missingTranslationId
    case translationFailed(String?)
    case translationTimedOut

    var errorDescription: String? {
        switch self {
        case .missingTranslationId:
            return "后端未返回提示词生成任务 ID"
        case .translationFailed(let message):
            return message ?? "本地 Ollama 生成提示词失败"
        case .translationTimedOut:
            return "本地 Ollama 生成提示词超时"
        }
    }
}
