import SetuIOSCore
import SwiftUI

struct AiChatDrawView: View {
    @Environment(RouterPath.self) private var router
    @Environment(SystemPushCoordinator.self) private var pushNotifications
    @Bindable var environment: AppEnvironment

    @AppStorage("setu_has_explained_generation_notifications") private var hasExplainedGenerationNotifications = false
    @State private var sessions: [AiChatDrawSession] = []
    @State private var archivedSessions: [AiChatDrawSession] = []
    @State private var detail: AiChatDrawSessionDetail?
    @State private var jobOverrides: [Int: AiGenerationJob] = [:]
    @State private var input = ""
    @State private var nsfwMode = false
    @State private var isLoading = false
    @State private var isSending = false
    @State private var cooldownSeconds = 0
    @State private var feedback: SetuFeedback?
    @State private var userFacingError: UserFacingError?
    @State private var showingGenerationNotificationPrompt = false
    @State private var pendingGenerationID: Int?
    @State private var pendingUserMessage: String?
    @State private var streamingDraft: AiChatDrawStreamingDraft?
    @FocusState private var isComposerFocused: Bool

    private var isAdmin: Bool {
        environment.authSession.currentUser?.role == .admin
    }

    private var tokensPerPoint: Int {
        detail?.tokensPerPoint ?? AiChatDrawBilling.defaultTokensPerPoint
    }

    private var pricingText: String {
        AiChatDrawBilling.pricingText(tokensPerPoint: tokensPerPoint)
    }

    private var canSend: Bool {
        !isSending
            && !(detail?.session.isArchived ?? false)
            && cooldownSeconds <= 0
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonTitle: String {
        if detail?.session.isArchived == true { return "已归档，取消归档后可继续" }
        if isSending { return "思考并绘画中…" }
        if cooldownSeconds > 0 { return "请 \(cooldownSeconds) 秒后再对话" }
        if isAdmin { return "发送，管理员免费" }
        return "发送（\(pricingText)）"
    }

    private var messages: [AiChatDrawMessage] {
        detail?.messages ?? []
    }

    private var activeJobIDs: [Int] {
        messages.compactMap { resolvedJob(for: $0) }
            .filter { !$0.isAiLiveActivityTerminal }
            .map(\.id)
    }

    private var toolbarLogo: some View {
        SetuToolbarLogo(assetName: "AiDrawLogo", accessibilityLabel: "AI 绘画")
    }

    var body: some View {
        messageArea
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .setuRefreshAfterLogin(environment.authSession) {
            Task { await bootstrap() }
        }
        .setuRetry {
            Task { await bootstrap() }
        }
        .navigationTitle("AI 绘画")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.draw.page")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                toolbarLogo
            }
            #else
            ToolbarItem(placement: .automatic) {
                toolbarLogo
            }
            #endif

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await startNewConversation() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(isLoading || isSending)
                .accessibilityLabel("开新对话")
                .accessibilityIdentifier("ai.chat.new")

                Menu {
                    Section("对话") {
                        if sessions.isEmpty {
                            Text("暂无进行中的对话")
                        } else {
                            ForEach(sessions) { session in
                                Button {
                                    Task { await loadSession(id: session.id) }
                                } label: {
                                    if session.id == detail?.session.id {
                                        Label(session.displayTitle, systemImage: "checkmark")
                                    } else {
                                        Text(session.displayTitle)
                                    }
                                }
                            }
                        }
                    }

                    if !archivedSessions.isEmpty {
                        Section("已归档") {
                            ForEach(archivedSessions) { session in
                                Button {
                                    Task { await loadSession(id: session.id) }
                                } label: {
                                    if session.id == detail?.session.id {
                                        Label(session.displayTitle, systemImage: "checkmark")
                                    } else {
                                        Text(session.displayTitle)
                                    }
                                }
                            }
                        }
                    }

                    Section("当前对话") {
                        if let current = detail?.session, current.isActive {
                            Button {
                                Task { await archiveCurrentSession() }
                            } label: {
                                Label("归档当前对话", systemImage: "archivebox")
                            }
                            .disabled(isLoading || isSending)
                        } else if detail?.session.isArchived == true {
                            Button {
                                Task { await unarchiveCurrentSession() }
                            } label: {
                                Label("取消归档", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(isLoading || isSending)
                        }
                    }

                    Section("更多") {
                        Button {
                            router.navigate(to: .aiHistory)
                        } label: {
                            Label("绘画历史", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            router.navigate(to: .aiSquare)
                        } label: {
                            Label("AI 广场", systemImage: "square.grid.2x2")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多")
                .accessibilityIdentifier("ai.chat.session")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { isComposerFocused = false }
                    .accessibilityIdentifier("ai.draw.keyboard.done")
            }
        }
        .task {
            consumePendingPromptIfNeeded()
            await bootstrap()
        }
        .onAppear { consumePendingPromptIfNeeded() }
        .alert("生成进度提醒", isPresented: $showingGenerationNotificationPrompt) {
            Button("开启通知") {
                Task {
                    _ = await pushNotifications.requestAuthorizationForGenerationUpdates()
                    openPendingGenerationIfNeeded()
                }
            }
            Button("暂不", role: .cancel) {
                openPendingGenerationIfNeeded()
            }
        } message: {
            Text("开启后，作品完成时会通过系统通知提醒你。")
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if cooldownSeconds > 0 {
                cooldownSeconds -= 1
            }
        }
        .task(id: activeJobIDs.map(String.init).joined(separator: ",")) {
            await pollActiveJobs()
        }
    }

    @ViewBuilder
    private var messageArea: some View {
        if isLoading, detail == nil {
            ProgressView("正在加载对话…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let userFacingError, detail == nil {
            SetuEmptyState(error: userFacingError) {
                Task { await bootstrap() }
            }
            .padding()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SetuSpacing.xl) {
                        if messages.isEmpty, pendingUserMessage == nil, streamingDraft == nil, !isSending {
                            emptyConversation
                                .padding(.top, 72)
                        }

                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }

                        if let pendingUserMessage {
                            let alreadyPersisted = messages.contains {
                                $0.isUser
                                    && ($0.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    == pendingUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            if !alreadyPersisted {
                                userBubbleText(pendingUserMessage)
                                    .id("pending-user")
                            }
                        }

                        if let streamingDraft {
                            streamingAssistantBlock(streamingDraft)
                                .id("streaming")
                        } else if isSending {
                            sendingPlaceholder
                                .id("sending")
                        }
                    }
                    .padding(.horizontal, SetuSpacing.lg)
                    .padding(.top, SetuSpacing.sm)
                    .padding(.bottom, SetuSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isSending) { _, sending in
                    if sending { scrollToBottom(proxy) }
                }
                .onChange(of: streamingDraft?.content) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: SetuSpacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(SetuColor.brandPink)
            Text("今天想画点什么？")
                .font(SetuTypography.title)
                .foregroundStyle(SetuColor.textPrimary)
            Text("直接描述画面即可，例如：雨夜里撑伞的猫娘，竖构图。")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SetuSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private var sendingPlaceholder: some View {
        HStack(alignment: .center, spacing: SetuSpacing.sm) {
            ProgressView()
            Text("正在思考并安排绘画…")
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    @ViewBuilder
    private func messageRow(_ message: AiChatDrawMessage) -> some View {
        if message.isUser {
            userBubble(message)
        } else {
            assistantBlock(message)
        }
    }

    private func userBubble(_ message: AiChatDrawMessage) -> some View {
        userBubbleText(message.displayContent)
    }

    private func userBubbleText(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 48)
            Text(text)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.brandInk)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .padding(.horizontal, SetuSpacing.md)
                .padding(.vertical, SetuSpacing.sm + 2)
                .background(SetuColor.brandSoft.opacity(0.55), in: Capsule(style: .continuous))
        }
    }

    private func streamingAssistantBlock(_ draft: AiChatDrawStreamingDraft) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            if !draft.status.isEmpty {
                HStack(spacing: SetuSpacing.sm) {
                    if draft.content.isEmpty {
                        ProgressView()
                    }
                    Text(draft.status)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    Spacer(minLength: 0)
                }
            }

            if !draft.content.isEmpty {
                Text(draft.content)
                    .font(SetuTypography.body)
                    .foregroundStyle(SetuColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else if draft.status.isEmpty {
                HStack(spacing: SetuSpacing.sm) {
                    ProgressView()
                    Text("正在思考…")
                        .font(SetuTypography.body)
                        .foregroundStyle(SetuColor.textSecondary)
                    Spacer(minLength: 0)
                }
            }

            if !draft.reasoningContent.isEmpty {
                DisclosureGroup("查看思考过程") {
                    Text(draft.reasoningContent)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .textSelection(.enabled)
                }
                .tint(SetuColor.textSecondary)
            }

            if let job = draft.job {
                jobCard(job)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assistantBlock(_ message: AiChatDrawMessage) -> some View {
        let job = resolvedJob(for: message)
        let content = AiChatDrawBilling.displayContent(for: message, job: job)
        return VStack(alignment: .leading, spacing: SetuSpacing.md) {
            if !content.isEmpty {
                Text(content)
                    .font(SetuTypography.body)
                    .foregroundStyle(SetuColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let reasoning = message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reasoning.isEmpty {
                DisclosureGroup("查看思考过程") {
                    Text(reasoning)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .textSelection(.enabled)
                }
                .tint(SetuColor.textSecondary)
            }

            if let job {
                jobCard(job)
            } else if let errorMessage = message.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.danger)
            }

            assistantActions(message, displayContent: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assistantActions(_ message: AiChatDrawMessage, displayContent: String) -> some View {
        HStack(spacing: SetuSpacing.md) {
            if !displayContent.isEmpty {
                Button {
                    PlatformClipboard.copy(displayContent)
                    feedback = .success("已复制回复")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("复制回复")
            }

            if let job = resolvedJob(for: message) {
                Button {
                    router.navigate(to: .aiGenerationDetail(job.id))
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .accessibilityLabel("查看作品详情")
                .accessibilityIdentifier("ai.chat.open-job-\(job.id)")
            }

            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(SetuColor.textTertiary)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func jobCard(_ job: AiGenerationJob) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack(spacing: SetuSpacing.xs) {
                Text(job.statusTitle)
                    .font(SetuTypography.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textSecondary)
                Text("#\(job.id)")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textTertiary)
                Spacer(minLength: 0)
            }

            if let url = job.imageUrl, !url.isEmpty {
                SetuRemoteImage(
                    urlString: url,
                    accessibilityLabel: "AI 作品：\(job.promptCn)",
                    width: nil,
                    height: nil,
                    cornerRadius: SetuRadius.md,
                    contentMode: .fit,
                    onActivate: {
                        router.navigate(to: .aiGenerationDetail(job.id))
                    },
                    activationHint: "查看作品详情"
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxHeight: 420)
            } else if job.status != "FAILED" {
                RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                    .fill(SetuColor.surfaceMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: SetuSpacing.sm) {
                            ProgressView()
                            Text("正在生成图片…")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
            }

            if let error = job.userErrorMessage ?? job.errorMessage, !error.isEmpty {
                Text(error)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.danger)
            }
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            if let userFacingError, detail != nil {
                Text(userFacingError.message)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.danger)
                    .padding(.horizontal, SetuSpacing.lg)
            }

            HStack(alignment: .bottom, spacing: SetuSpacing.sm) {
                Menu {
                    Toggle("允许 NSFW 内容", isOn: $nsfwMode)
                    Text(isAdmin ? "管理员免费" : pricingText)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .modifier(AiChatNativeCircleChrome(emphasized: nsfwMode))
                }
                .accessibilityLabel(nsfwMode ? "选项，已开启 NSFW" : "选项")
                .accessibilityIdentifier("ai.chat.nsfw")

                TextField("描述你想画的画面", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .disabled(isSending || detail?.session.isArchived == true)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("ai.draw.prompt")

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .disabled(!canSend)
                .accessibilityLabel(sendButtonTitle)
                .accessibilityIdentifier("ai.draw.generate")
                .modifier(AiChatNativeSendButtonStyle(enabled: canSend))
            }
            .padding(.leading, 6)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .modifier(AiChatNativeCapsuleBarBackground())
            .padding(.horizontal, SetuSpacing.md)
            .padding(.top, SetuSpacing.xs)
            .padding(.bottom, SetuSpacing.sm)
        }
    }

    private func resolvedJob(for message: AiChatDrawMessage) -> AiGenerationJob? {
        if let id = message.generationJobId ?? message.generationJob?.id,
           let override = jobOverrides[id] {
            return override
        }
        return message.generationJob
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                if streamingDraft != nil {
                    proxy.scrollTo("streaming", anchor: .bottom)
                } else if isSending {
                    proxy.scrollTo(pendingUserMessage == nil ? "sending" : "pending-user", anchor: .bottom)
                } else if let lastID = messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private func consumePendingPromptIfNeeded() {
        if let pending = AiChatDrawComposerStore.consumePendingPrompt() {
            input = pending
            isComposerFocused = true
        }
    }

    @MainActor
    private func bootstrap() async {
        isLoading = true
        userFacingError = nil
        defer { isLoading = false }
        do {
            async let activePage = environment.aiChatDrawClient.listSessions(page: 1, pageSize: 20, status: "ACTIVE")
            async let archivedPage = environment.aiChatDrawClient.listSessions(page: 1, pageSize: 20, status: "ARCHIVED")
            let active = try await activePage
            let archived = try await archivedPage
            sessions = active.list
            archivedSessions = archived.list
            if let currentID = detail?.session.id {
                await loadSession(id: currentID)
            } else if let latest = active.list.first {
                await loadSession(id: latest.id)
            } else {
                await startNewConversation()
            }
        } catch {
            userFacingError = UserFacingErrorMapper.map(error)
        }
    }

    @MainActor
    private func startNewConversation() async {
        isLoading = true
        userFacingError = nil
        defer { isLoading = false }
        do {
            let session = try await environment.aiChatDrawClient.createSession()
            applyDetail(
                AiChatDrawSessionDetail(
                    session: session,
                    messages: [],
                    tokensPerPoint: tokensPerPoint,
                    rateLimitSeconds: detail?.rateLimitSeconds ?? AiChatDrawBilling.defaultRateLimitSeconds,
                    retryAfterSeconds: cooldownSeconds,
                    adminFree: isAdmin
                )
            )
            jobOverrides = [:]
        } catch {
            userFacingError = UserFacingErrorMapper.map(error)
            feedback = .error("开新对话失败")
        }
    }

    @MainActor
    private func loadSession(id: Int) async {
        isLoading = true
        userFacingError = nil
        defer { isLoading = false }
        do {
            applyDetail(try await environment.aiChatDrawClient.sessionDetail(id: id))
            jobOverrides = [:]
        } catch {
            userFacingError = UserFacingErrorMapper.map(error)
            feedback = .error("加载对话失败")
        }
    }

    @MainActor
    private func archiveCurrentSession() async {
        guard let sessionID = detail?.session.id, detail?.session.isActive == true else { return }
        isLoading = true
        userFacingError = nil
        defer { isLoading = false }
        do {
            _ = try await environment.aiChatDrawClient.archiveSession(id: sessionID)
            feedback = .success("对话已归档")
            let active = try await environment.aiChatDrawClient.listSessions(page: 1, pageSize: 20, status: "ACTIVE")
            let archived = try await environment.aiChatDrawClient.listSessions(page: 1, pageSize: 20, status: "ARCHIVED")
            sessions = active.list
            archivedSessions = archived.list
            if let next = active.list.first {
                await loadSession(id: next.id)
            } else {
                await startNewConversation()
            }
        } catch {
            userFacingError = UserFacingErrorMapper.map(error)
            feedback = .error("归档失败")
        }
    }

    @MainActor
    private func unarchiveCurrentSession() async {
        guard let sessionID = detail?.session.id, detail?.session.isArchived == true else { return }
        isLoading = true
        userFacingError = nil
        defer { isLoading = false }
        do {
            _ = try await environment.aiChatDrawClient.unarchiveSession(id: sessionID)
            feedback = .success("已取消归档")
            applyDetail(try await environment.aiChatDrawClient.sessionDetail(id: sessionID))
            let active = try await environment.aiChatDrawClient.listSessions(page: 1, pageSize: 20, status: "ACTIVE")
            let archived = try await environment.aiChatDrawClient.listSessions(page: 1, pageSize: 20, status: "ARCHIVED")
            sessions = active.list
            archivedSessions = archived.list
        } catch {
            userFacingError = UserFacingErrorMapper.map(error)
            feedback = .error("取消归档失败")
        }
    }

    @MainActor
    private func send() async {
        let content = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !content.isEmpty else { return }

        let previousJobIDs = Set(messages.compactMap { $0.generationJobId ?? $0.generationJob?.id })
        let previousCount = messages.count
        let sessionID = detail?.session.id
        input = ""
        pendingUserMessage = content
        streamingDraft = AiChatDrawStreamingDraft(status: "已收到请求，开始处理…")
        isSending = true
        userFacingError = nil
        feedback = nil
        defer {
            isSending = false
            if streamingDraft != nil { streamingDraft = nil }
        }

        do {
            var finalDetail: AiChatDrawSessionDetail?
            for try await event in environment.aiChatDrawClient.streamMessage(
                AiChatDrawSendRequest(
                    sessionId: sessionID,
                    content: content,
                    nsfwMode: nsfwMode
                )
            ) {
                switch event.kind {
                case .done:
                    finalDetail = event.detail
                case .error:
                    let message = event.message ?? "对话失败"
                    throw APIError.httpStatus(
                        AiChatDrawBilling.isClientDisconnectedMessage(message) ? 503 : 500,
                        message: message,
                        requestID: nil,
                        traceID: nil,
                        code: AiChatDrawBilling.isClientDisconnectedMessage(message)
                            ? "AI_CHAT_DRAW_STREAM_CLOSED"
                            : "AI_CHAT_DRAW_STREAM_ERROR"
                    )
                default:
                    var draft = streamingDraft ?? AiChatDrawStreamingDraft()
                    try draft.apply(event)
                    streamingDraft = draft
                    if let job = event.job {
                        jobOverrides[job.id] = job
                        // Don't block token deltas on Live Activity setup.
                        Task {
                            await AiGenerationLiveActivityCenter.start(
                                job: job,
                                mobileClient: environment.mobileAppClient
                            )
                        }
                    }
                    // Yield so each SSE chunk can paint before the next arrives.
                    await Task.yield()
                }
            }

            if let finalDetail {
                pendingUserMessage = nil
                streamingDraft = nil
                applyDetail(finalDetail)
                await handleNewJobs(in: finalDetail, previousJobIDs: previousJobIDs)
                _ = try? await environment.pointsClient.balance()
            } else {
                let recovered = await recoverSendFailure(
                    APIError.invalidResponse,
                    content: content,
                    sessionID: sessionID,
                    previousCount: previousCount,
                    previousJobIDs: previousJobIDs
                )
                if recovered {
                    pendingUserMessage = nil
                    streamingDraft = nil
                } else if AiChatDrawBilling.userTurnPersisted(content: content, detail: detail) {
                    pendingUserMessage = nil
                    streamingDraft = nil
                    feedback = .error("回复同步较慢，请下拉刷新查看是否已完成。")
                } else {
                    userFacingError = UserFacingErrorMapper.map(APIError.invalidResponse)
                }
            }
        } catch {
            let recovered = await recoverSendFailure(
                error,
                content: content,
                sessionID: sessionID,
                previousCount: previousCount,
                previousJobIDs: previousJobIDs
            )
            if recovered {
                pendingUserMessage = nil
                streamingDraft = nil
                let disconnect = AiChatDrawBilling.isClientDisconnectedMessage(Self.apiErrorMessage(error))
                if AiChatDrawBilling.isTransientSendFailure(error), !disconnect {
                    feedback = .success("对话已在后台完成，页面已自动同步。")
                }
            } else if AiChatDrawBilling.userTurnPersisted(content: content, detail: detail) {
                pendingUserMessage = nil
                streamingDraft = nil
                feedback = .error("连接中断，请下拉刷新查看是否已完成。")
            } else {
                pendingUserMessage = nil
                streamingDraft = nil
                input = content
                if AiChatDrawBilling.isClientDisconnectedMessage(Self.apiErrorMessage(error)) {
                    // Avoid scary false failures: keep UI synced and let user refresh if needed.
                    feedback = .error("连接中断，请下拉刷新查看是否已完成。")
                } else {
                    userFacingError = UserFacingErrorMapper.map(error)
                }
                if case .httpStatus(429, let message, _, _, _) = error as? APIError {
                    applyCooldown(
                        AiChatDrawBilling.parseRetrySeconds(
                            from: message,
                            fallback: detail?.rateLimitSeconds ?? AiChatDrawBilling.defaultRateLimitSeconds
                        )
                    )
                }
            }
        }
    }

    private static func apiErrorMessage(_ error: Error) -> String? {
        guard case .httpStatus(_, let message, _, _, _) = error as? APIError else {
            return error.localizedDescription
        }
        return message
    }

    @MainActor
    private func recoverSendFailure(
        _ error: Error,
        content: String,
        sessionID: Int?,
        previousCount: Int,
        previousJobIDs: Set<Int>
    ) async -> Bool {
        if case .httpStatus(429, let message, _, _, _) = error as? APIError {
            applyCooldown(
                AiChatDrawBilling.parseRetrySeconds(
                    from: message,
                    fallback: detail?.rateLimitSeconds ?? AiChatDrawBilling.defaultRateLimitSeconds
                )
            )
            if let sessionID {
                await loadSession(id: sessionID)
            } else {
                _ = await reloadLatestSessionDetail()
            }
            return false
        }

        // Stream often dies before `done` while the server keeps generating.
        // Poll until a visible assistant/job appears — user-only is not enough.
        if var draft = streamingDraft {
            draft.status = "连接中断，正在同步回复…"
            streamingDraft = draft
        }

        var lastReloaded: AiChatDrawSessionDetail?
        for delay in AiChatDrawBilling.recoverPollDelaysNanoseconds {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            let reloaded = await reloadLatestSessionDetail(preferredSessionID: sessionID)
            lastReloaded = reloaded
            if AiChatDrawBilling.userTurnPersisted(content: content, detail: reloaded) {
                pendingUserMessage = nil
            }
            if AiChatDrawBilling.turnLikelySucceeded(
                content: content,
                previousMessageCount: previousCount,
                detail: reloaded
            ) {
                applyCooldown(AiChatDrawBilling.cooldownSeconds(retryAfterSeconds: reloaded?.retryAfterSeconds))
                if let reloaded {
                    await handleNewJobs(in: reloaded, previousJobIDs: previousJobIDs)
                }
                return true
            }
        }

        if AiChatDrawBilling.isTransientSendFailure(error) {
            applyCooldown(AiChatDrawBilling.cooldownSeconds(retryAfterSeconds: lastReloaded?.retryAfterSeconds))
        }
        return false
    }

    @MainActor
    private func reloadLatestSessionDetail(preferredSessionID: Int? = nil) async -> AiChatDrawSessionDetail? {
        if let preferredSessionID {
            if let detail = try? await environment.aiChatDrawClient.sessionDetail(id: preferredSessionID) {
                applyDetail(detail)
                return detail
            }
        }
        guard let latest = try? await environment.aiChatDrawClient.listSessions(page: 1, pageSize: 1).list.first,
              let detail = try? await environment.aiChatDrawClient.sessionDetail(id: latest.id) else {
            return nil
        }
        applyDetail(detail)
        return detail
    }

    @MainActor
    private func applyDetail(_ next: AiChatDrawSessionDetail) {
        detail = next
        let session = next.session
        if session.isArchived {
            sessions = sessions.filter { $0.id != session.id }
            if archivedSessions.contains(where: { $0.id == session.id }) {
                archivedSessions = archivedSessions.map { $0.id == session.id ? session : $0 }
            } else {
                archivedSessions.insert(session, at: 0)
            }
        } else {
            archivedSessions = archivedSessions.filter { $0.id != session.id }
            if sessions.contains(where: { $0.id == session.id }) {
                sessions = sessions.map { $0.id == session.id ? session : $0 }
            } else {
                sessions.insert(session, at: 0)
            }
        }
        applyCooldown(AiChatDrawBilling.cooldownSeconds(retryAfterSeconds: next.retryAfterSeconds))
    }

    private func applyCooldown(_ seconds: Int) {
        cooldownSeconds = max(0, seconds)
    }

    @MainActor
    private func handleNewJobs(in detail: AiChatDrawSessionDetail, previousJobIDs: Set<Int>) async {
        let newJobs = detail.messages
            .compactMap(\.generationJob)
            .filter { !previousJobIDs.contains($0.id) }

        for job in newJobs {
            jobOverrides[job.id] = job
            await AiGenerationLiveActivityCenter.start(job: job, mobileClient: environment.mobileAppClient)
        }

        if let job = newJobs.last,
           !hasExplainedGenerationNotifications,
           pushNotifications.authorizationStatus == .notDetermined {
            hasExplainedGenerationNotifications = true
            pendingGenerationID = job.id
            showingGenerationNotificationPrompt = true
        }
    }

    @MainActor
    private func pollActiveJobs() async {
        while !Task.isCancelled {
            let ids = activeJobIDs
            guard !ids.isEmpty else { return }

            for id in ids {
                guard let latest = try? await environment.aiGenerationClient.get(id: id) else { continue }
                jobOverrides[id] = latest
                await AiGenerationLiveActivityCenter.update(job: latest, mobileClient: environment.mobileAppClient)
            }

            try? await Task.sleep(nanoseconds: AiChatDrawBilling.pollIntervalNanoseconds)
        }
    }

    private func openPendingGenerationIfNeeded() {
        guard let pendingGenerationID else { return }
        router.navigate(to: .aiGenerationDetail(pendingGenerationID))
        self.pendingGenerationID = nil
    }
}

#Preview {
    NavigationStack {
        AiChatDrawView(environment: .live())
    }
}

/// Apple Liquid Glass capsule composer (iOS 26+), with material fallback.
private struct AiChatNativeCapsuleBarBackground: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(SetuColor.separator.opacity(0.55), lineWidth: 0.5)
                }
        }
    }
}

private struct AiChatNativeCircleChrome: ViewModifier {
    let emphasized: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(emphasized ? SetuColor.brandPink : SetuColor.textPrimary)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .foregroundStyle(emphasized ? SetuColor.brandPink : SetuColor.textSecondary)
                .background(
                    emphasized ? SetuColor.brandSoft.opacity(0.7) : SetuColor.surfaceMuted,
                    in: Circle()
                )
        }
    }
}

private struct AiChatNativeSendButtonStyle: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(enabled ? SetuColor.brandPink : SetuColor.surfaceMuted)
                .opacity(enabled ? 1 : 0.55)
        } else if enabled {
            content
                .foregroundStyle(Color.white)
                .background(SetuColor.heroGradient, in: Circle())
        } else {
            content
                .foregroundStyle(SetuColor.textTertiary)
                .background(SetuColor.surfaceMuted, in: Circle())
        }
    }
}
