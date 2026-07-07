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
    @State private var negativePrompt = ""
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
    @State private var message: String?
    @State private var createdJob: AiGenerationJob?
    @State private var draftLoaded = false
    @State private var isApplyingDraft = false
    @State private var loadedDraftUpdatedAt: Date?

    var body: some View {
        Form {
            statusSection
            promptSection
            generationSection
            assetSection
            actionSection
        }
        .navigationTitle("AI 绘画")
        .onAppear { applyDraftIfNeeded() }
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
        Section("生成队列") {
            switch statusState {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let status):
                LabeledContent("状态", value: status.statusTitle)
                if let message = status.message, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("\(status.activeWorkerCount ?? 0)/\(status.workerCount ?? 0) 可用节点", systemImage: "sparkles")
                    Spacer()
                    if let queued = status.queuedCount {
                        Label("\(queued) 排队", systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var promptSection: some View {
        Section("提示词") {
            TextField("中文提示词", text: $promptCn, axis: .vertical)
                .lineLimit(3...6)
            TextField("风格标签", text: $styleTags)
            TextField("英文正向提示词", text: $positivePrompt, axis: .vertical)
                .lineLimit(2...5)
            TextField("英文负向提示词", text: $negativePrompt, axis: .vertical)
                .lineLimit(2...5)
            TextField("风格说明", text: $styleNotes, axis: .vertical)
                .lineLimit(2...4)
            Button(isTranslating ? "翻译中" : "翻译提示词") {
                Task { await translate() }
            }
            .disabled(promptCn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
        }
    }

    private var generationSection: some View {
        Section("生成参数") {
            canvasPresetGrid
            Stepper("宽度 \(width)", value: $width, in: 512...1536, step: 64)
            Stepper("高度 \(height)", value: $height, in: 512...1536, step: 64)
            Stepper("步数 \(steps)", value: $steps, in: 12...60)
            HStack {
                Text("CFG")
                Slider(value: $cfg, in: 3...12, step: 0.5)
                Text(cfg.formatted(.number.precision(.fractionLength(1))))
                    .monospacedDigit()
            }
            Toggle("NSFW 模式", isOn: $nsfwMode)
            Picker("生成模式", selection: $generationMode) {
                Text("单角色").tag("SINGLE")
                Text("双角色").tag("DUAL")
            }
            Picker("可见性", selection: $nsfwVisibilityLevel) {
                Text("轻度").tag("LIGHT")
                Text("标准").tag("STANDARD")
                Text("严格").tag("STRONG")
            }
        }
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
                    .tint(width == preset.width && height == preset.height ? .pink : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var assetSection: some View {
        Section("模型资产") {
            Button {
                router.navigate(to: .feature(.aiAssets))
            } label: {
                Label("浏览 AI 资产选择", systemImage: "photo.stack")
            }
            if draftLoaded, hasAssetDraft {
                Label("已载入资产草稿", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            switch capabilityState {
            case .idle, .loading:
                ProgressView("正在加载模型")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let capabilities):
                Picker("Checkpoint", selection: $selectedCheckpoint) {
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
                            Text(secondLoraStrength.formatted(.number.precision(.fractionLength(1))))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button(isSubmitting ? "提交中" : "创建生成任务") {
                Task { await submit() }
            }
            .disabled(promptCn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let createdJob {
                AiCreatedJobSummary(job: createdJob)
                Button {
                    router.navigate(to: .aiGenerationDetail(createdJob.id))
                } label: {
                    Label("查看任务详情", systemImage: "sparkles.rectangle.stack")
                }
                Button {
                    router.navigate(to: .aiHistory)
                } label: {
                    Label("查看绘画历史", systemImage: "clock.arrow.circlepath")
                }
            }
        }
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

    private func translate() async {
        let prompt = promptCn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }
        do {
            let response = try await environment.aiGenerationClient.translatePrompt(
                AiPromptTranslateRequest(
                    promptCn: prompt,
                    styleTags: styleTags.trimmingCharacters(in: .whitespacesAndNewlines),
                    negativePrompt: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    nsfwMode: nsfwMode,
                    nsfwVisibilityLevel: nsfwVisibilityLevel
                )
            )
            if let positive = response.positive, !positive.isEmpty {
                positivePrompt = positive
            }
            if let negative = response.negative, !negative.isEmpty {
                negativePrompt = negative
            }
            if let styleNotes = response.styleNotes, !styleNotes.isEmpty {
                self.styleNotes = styleNotes
            }
            message = response.status.map { "翻译任务状态：\($0)" } ?? "提示词已翻译"
        } catch {
            message = error.localizedDescription
        }
    }

    private func submit() async {
        let prompt = promptCn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let job = try await environment.aiGenerationClient.create(
                AiGenerationCreateRequest(
                    promptCn: prompt,
                    promptPositive: positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    promptNegative: negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
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
                    nsfwVisibilityLevel: nsfwVisibilityLevel
                )
            )
            createdJob = job
            message = "任务已创建：#\(job.id)"
            saveDraft()
        } catch {
            message = error.localizedDescription
        }
    }

    private var hasAssetDraft: Bool {
        !selectedCheckpoint.isEmpty
            || !selectedLora.isEmpty
            || !selectedCharacter.isEmpty
            || !selectedSecondLora.isEmpty
            || !selectedSecondCharacter.isEmpty
            || !styleTags.isEmpty
            || !negativePrompt.isEmpty
            || !styleNotes.isEmpty
    }

    private func applyDraftIfNeeded() {
        let draft = AiDrawDraftStore.load()
        guard loadedDraftUpdatedAt != draft.updatedAt else { return }
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
        negativePrompt = draft.negativePrompt
        styleNotes = draft.styleNotes
        loadedDraftUpdatedAt = draft.updatedAt
        draftLoaded = true
        isApplyingDraft = false
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

private struct AiCreatedJobSummary: View {
    let job: AiGenerationJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(job.id) \(job.statusTitle)")
                .font(.headline)
            Text("\(job.width)x\(job.height) · \(job.steps) 步")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let cost = job.pointsCost {
                Label("\(cost) 积分", systemImage: "bolt.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
