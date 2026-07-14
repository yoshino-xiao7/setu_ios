import SetuIOSCore
import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @Environment(RouterPath.self) private var router
    @Environment(SystemPushCoordinator.self) private var pushNotifications
    @Bindable var environment: AppEnvironment
    @State private var notifications: [UserNotification] = []
    @State private var unreadOnly = false
    @State private var unreadCount: Int?
    @State private var unreadCountPhase: NotificationUnreadCountPhase = .unknown
    @State private var unreadCountError: String?
    @State private var total = 0
    @State private var nextPage = 1
    @State private var hasLoadedFirstPage = false
    @State private var isLoadingFirstPage = false
    @State private var isLoadingMore = false
    @State private var firstPageError: String?
    @State private var loadMoreError: String?
    @State private var listGeneration = 0
    @State private var countGeneration = 0
    @State private var optimisticReadIDs: Set<Int> = []
    @State private var pendingMarkAllRead = false
    @State private var markAllReadCutoffID: Int?
    @State private var pendingUnreadCountCeiling: Int?
    @State private var latestFirstPageServerUnreadIDs: Set<Int> = []
    @State private var markingReadIDs: Set<Int> = []
    @State private var feedback: SetuFeedback?
    @State private var isMarkingAllRead = false
    private let pageSize = 20

    var body: some View {
        List {
            notificationPermissionSection

            Section {
                SetuCard {
                    Toggle("仅看未读", isOn: $unreadOnly)
                        .tint(SetuColor.brandPink)
                        .disabled(isMarkingAllRead)
                        .accessibilityIdentifier("notifications.filter.unread-only")
                        .onChange(of: unreadOnly) { _, newValue in
                            Task { await loadFirstPage(for: newValue, clearExisting: true) }
                        }
                    if let unreadStatusText {
                        SetuPill(
                            text: unreadStatusText,
                            systemImage: "bell.badge",
                            tone: unreadCountPhase == .loaded ? .brand : .warning
                        )
                        .accessibilityIdentifier("notifications.unread-count")
                    }
                    if let unreadCountError {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            Text(unreadCountError)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.warning)
                            Button("重新同步未读数量") {
                                Task { await loadFirstPage(for: unreadOnly, clearExisting: false) }
                            }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("notifications.retry.unread-count")
                        }
                    }
                }
            }
            .setuListRow()

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                        .accessibilityIdentifier("notifications.feedback")
                }
                .setuListRow()
            }

            if isInitialLoading {
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载通知", systemImage: "bell", isLoading: true)
                    }
                }
                .setuListRow()
            } else if notifications.isEmpty {
                Section {
                    SetuCard {
                        if let firstPageError {
                            VStack(spacing: SetuSpacing.md) {
                                SetuEmptyState(
                                    title: "通知加载失败",
                                    message: firstPageError,
                                    systemImage: "bell.badge"
                                )
                                Button("重试") {
                                    Task { await loadFirstPage(for: unreadOnly, clearExisting: false) }
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("notifications.retry.initial")
                            }
                        } else {
                            SetuEmptyState(title: unreadOnly ? "暂无未读通知" : "暂无通知", systemImage: "bell")
                        }
                    }
                }
                .setuListRow()
            } else {
                if let firstPageError {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                SetuFeedbackBanner(feedback: .warning(firstPageError))
                                Button("重新刷新") {
                                    Task { await loadFirstPage(for: unreadOnly, clearExisting: false) }
                                }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                            }
                        }
                    }
                    .setuListRow()
                }
                Section {
                    ForEach(notifications) { notification in
                        NotificationRow(
                            notification: notification,
                            isRead: isEffectivelyRead(notification),
                            isUpdating: markingReadIDs.contains(notification.id)
                        ) {
                            Task { await handleNotificationTap(notification) }
                        }
                        .onAppear {
                            if notification.id == notifications.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }

                    SetuLoadMoreFooter(state: loadMoreFooterState) {
                        Task { await loadMore() }
                    }
                } header: {
                    Text("共 \(total) 条")
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .accessibilityIdentifier("notifications.page")
        .navigationTitle(navigationTitle)
        .toolbar {
            Button("全部已读") {
                Task { await markAllRead() }
            }
            .disabled(!canMarkAllRead || isMarkingAllRead || !markingReadIDs.isEmpty)
            .accessibilityIdentifier("notifications.mark-all-read")
            .accessibilityValue(isMarkingAllRead ? "处理中" : "")
        }
        .task {
            await pushNotifications.refreshAuthorizationStatus()
            await loadFirstPage(for: unreadOnly, clearExisting: false)
        }
        .refreshable { await loadFirstPage(for: unreadOnly, clearExisting: false) }
    }

    private var notificationPermissionSection: some View {
        Section {
            SetuCard {
                SetuPermissionPrompt(
                    title: "系统通知",
                    message: "用于作品生成完成、投稿结果和账号安全提醒",
                    systemImage: "bell.badge",
                    state: notificationPermissionState,
                    actionTitle: notificationPermissionActionTitle,
                    action: notificationPermissionAction
                )
                .accessibilityIdentifier("notifications.permission.prompt")
            }
        }
        .setuListRow()
    }

    private var notificationPermissionState: SetuPermissionState {
        switch pushNotifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private var notificationPermissionActionTitle: String? {
        switch pushNotifications.authorizationStatus {
        case .notDetermined: "开启通知"
        case .denied: "前往系统设置"
        default: nil
        }
    }

    private var notificationPermissionAction: (() -> Void)? {
        switch pushNotifications.authorizationStatus {
        case .notDetermined:
            return {
                Task { _ = await pushNotifications.requestAuthorizationForGenerationUpdates() }
            }
        case .denied:
            return { pushNotifications.openSystemSettings() }
        default:
            return nil
        }
    }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadMoreError { return .failed(loadMoreError) }
        if !hasMore { return .complete("已加载全部 \(total) 条通知") }
        return .idle
    }

    private var hasMore: Bool { notifications.count < total }

    private var isInitialLoading: Bool {
        !hasLoadedFirstPage && isLoadingFirstPage
    }

    private var visibleUnreadCount: Int {
        notifications.reduce(into: 0) { count, notification in
            if !isEffectivelyRead(notification) { count += 1 }
        }
    }

    private var unreadStatusText: String? {
        if unreadCountPhase == .loaded, let unreadCount, unreadCount > 0 {
            return "\(unreadCount) 条未读"
        }
        if visibleUnreadCount > 0 {
            return unreadCountPhase == .loading ? "有未读通知 · 正在同步" : "有未读通知 · 数量待同步"
        }
        switch unreadCountPhase {
        case .loading:
            return "未读数量同步中"
        case .failed:
            return "未读数量待同步"
        case .unknown, .loaded:
            return nil
        }
    }

    private var navigationTitle: String {
        guard unreadCountPhase == .loaded, let unreadCount, unreadCount > 0 else {
            return "通知中心"
        }
        return "通知中心 (\(unreadCount))"
    }

    private var canMarkAllRead: Bool {
        if pendingMarkAllRead { return false }
        if visibleUnreadCount > 0 { return true }
        if unreadCountPhase == .loaded { return (unreadCount ?? 0) > 0 }
        return false
    }

    private func isEffectivelyRead(_ notification: UserNotification) -> Bool {
        NotificationReadConsistency.isEffectivelyRead(
            notificationID: notification.id,
            serverRead: notification.read,
            confirmedReadIDs: optimisticReadIDs,
            markAllCutoffID: markAllReadCutoffID
        )
    }

    private func loadFirstPage(for requestedUnreadOnly: Bool, clearExisting: Bool) async {
        guard requestedUnreadOnly == unreadOnly else { return }

        listGeneration += 1
        countGeneration += 1
        let requestedListGeneration = listGeneration
        let requestedCountGeneration = countGeneration

        if clearExisting {
            notifications = []
            total = 0
            nextPage = 1
            hasLoadedFirstPage = false
        }
        isLoadingFirstPage = true
        isLoadingMore = false
        firstPageError = nil
        loadMoreError = nil
        unreadCountPhase = .loading
        unreadCountError = nil

        if requestedUnreadOnly {
            let pageOutcome = await fetchPageOutcome(page: 1, unreadOnly: true)
            guard requestedListGeneration == listGeneration,
                  requestedUnreadOnly == unreadOnly else { return }
            isLoadingFirstPage = false

            switch pageOutcome {
            case .success(let page):
                commitFirstPage(page, unreadOnly: true)
                hasLoadedFirstPage = true
                guard requestedCountGeneration == countGeneration else { return }
                commitUnreadCount(.success(page.total))
            case .failure(let message):
                firstPageError = message
                unreadCountPhase = unreadCount == nil ? .unknown : .failed
                unreadCountError = "未读数量暂未同步"
            }
            return
        }

        async let pageOutcome = fetchPageOutcome(page: 1, unreadOnly: false)
        async let countOutcome = fetchUnreadCountOutcome()

        let resolvedPage = await pageOutcome
        if requestedListGeneration == listGeneration, requestedUnreadOnly == unreadOnly {
            isLoadingFirstPage = false
            switch resolvedPage {
            case .success(let page):
                commitFirstPage(page, unreadOnly: false)
                hasLoadedFirstPage = true
            case .failure(let message):
                firstPageError = message
            }
        }

        let resolvedCount = await countOutcome
        guard requestedCountGeneration == countGeneration,
              requestedUnreadOnly == unreadOnly else { return }
        commitUnreadCount(resolvedCount)
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoadingFirstPage else { return }
        let requestedGeneration = listGeneration
        let requestedUnreadOnly = unreadOnly
        let requestedPage = nextPage
        isLoadingMore = true
        loadMoreError = nil
        defer {
            if requestedGeneration == listGeneration {
                isLoadingMore = false
            }
        }

        let outcome = await fetchPageOutcome(page: requestedPage, unreadOnly: requestedUnreadOnly)
        guard requestedGeneration == listGeneration,
              requestedUnreadOnly == unreadOnly,
              requestedPage == nextPage else { return }

        switch outcome {
        case .success(let page):
            reconcileConfirmedReadIDs(from: page.list)
            let existingIDs = Set(notifications.map(\.id))
            let incoming = page.list.filter { notification in
                !existingIDs.contains(notification.id)
                    && (!requestedUnreadOnly || !isEffectivelyRead(notification))
            }
            notifications.append(contentsOf: incoming)
            total = clampedUnreadTotal(
                adjustedTotal(page.total, pageItems: page.list, unreadOnly: requestedUnreadOnly),
                unreadOnly: requestedUnreadOnly
            )
            nextPage = requestedPage + 1
            if page.list.isEmpty {
                total = notifications.count
            }
            if requestedUnreadOnly {
                commitUnreadCount(.success(page.total))
            }
        case .failure(let message):
            loadMoreError = message
        }
    }

    private func fetchPageOutcome(
        page: Int,
        unreadOnly: Bool
    ) async -> NotificationFetchOutcome<UserNotificationPage> {
        do {
            return .success(
                try await environment.notificationClient.list(
                    page: page,
                    pageSize: pageSize,
                    unreadOnly: unreadOnly
                )
            )
        } catch {
            return .failure(UserFacingErrorMapper.map(error).message)
        }
    }

    private func fetchUnreadCountOutcome() async -> NotificationFetchOutcome<Int> {
        do {
            return .success(try await environment.notificationClient.unreadCount())
        } catch {
            return .failure("未读数量暂未同步")
        }
    }

    private func commitFirstPage(_ page: UserNotificationPage, unreadOnly: Bool) {
        latestFirstPageServerUnreadIDs = Set(page.list.lazy.filter { !$0.read }.map(\.id))
        reconcileConfirmedReadIDs(from: page.list)
        notifications = page.list.filter { notification in
            !unreadOnly || !isEffectivelyRead(notification)
        }
        total = clampedUnreadTotal(
            adjustedTotal(page.total, pageItems: page.list, unreadOnly: unreadOnly),
            unreadOnly: unreadOnly
        )
        nextPage = page.page + 1
    }

    private func reconcileConfirmedReadIDs(from pageItems: [UserNotification]) {
        let confirmedReadIDs = Set(pageItems.lazy.filter(\.read).map(\.id))
        optimisticReadIDs.subtract(confirmedReadIDs)
    }

    private func adjustedTotal(
        _ serverTotal: Int,
        pageItems: [UserNotification],
        unreadOnly: Bool
    ) -> Int {
        guard unreadOnly else { return serverTotal }
        let hiddenOptimisticCount = pageItems.reduce(into: 0) { count, notification in
            if isEffectivelyRead(notification), !notification.read {
                count += 1
            }
        }
        return max(0, serverTotal - hiddenOptimisticCount)
    }

    private func clampedUnreadTotal(_ serverTotal: Int, unreadOnly: Bool) -> Int {
        guard unreadOnly, let pendingUnreadCountCeiling else { return serverTotal }
        return min(serverTotal, pendingUnreadCountCeiling)
    }

    private func commitUnreadCount(_ outcome: NotificationFetchOutcome<Int>) {
        switch outcome {
        case .success(let count):
            let decision = NotificationReadConsistency.resolveCount(
                .init(
                    serverCount: count,
                    firstPageUnreadIDs: latestFirstPageServerUnreadIDs,
                    pendingMarkAll: pendingMarkAllRead,
                    markAllCutoffID: markAllReadCutoffID,
                    confirmedReadIDs: optimisticReadIDs,
                    pendingCountCeiling: pendingUnreadCountCeiling
                )
            )
            switch decision {
            case .retry:
                unreadCountPhase = .failed
                unreadCountError = "已读状态尚未同步，请重新同步"
                return
            case .accept(let clearMarkAllPending, let clearCountCeiling):
                if clearMarkAllPending {
                    pendingMarkAllRead = false
                }
                if clearCountCeiling {
                    pendingUnreadCountCeiling = nil
                }
            }
            guard count >= visibleUnreadCount else {
                unreadCount = nil
                unreadCountPhase = .failed
                unreadCountError = "未读数量暂未同步"
                return
            }
            unreadCount = count
            unreadCountPhase = .loaded
            unreadCountError = nil
        case .failure(let message):
            unreadCountPhase = unreadCount == nil ? .unknown : .failed
            unreadCountError = message
        }
    }

    private func handleNotificationTap(_ notification: UserNotification) async {
        var didMarkRead = false
        if !isEffectivelyRead(notification) {
            didMarkRead = await markRead(notification)
        }

        if let route = targetRoute(for: notification) {
            router.navigate(to: route)
            if didMarkRead {
                let currentFilter = unreadOnly
                Task { await loadFirstPage(for: currentFilter, clearExisting: false) }
            }
        } else {
            await loadFirstPage(for: unreadOnly, clearExisting: false)
        }
    }

    private func markRead(_ notification: UserNotification) async -> Bool {
        guard !isMarkingAllRead,
              !isEffectivelyRead(notification),
              markingReadIDs.insert(notification.id).inserted else { return false }
        defer { markingReadIDs.remove(notification.id) }
        let exactCountBeforeMutation = unreadCountPhase == .loaded ? unreadCount : nil

        do {
            try await environment.notificationClient.markRead(id: notification.id)
            invalidateNotificationRequests()
            optimisticReadIDs.insert(notification.id)

            if unreadOnly {
                notifications.removeAll { $0.id == notification.id }
                total = max(0, total - 1)
            }
            if let exactCountBeforeMutation {
                let currentCeiling = pendingUnreadCountCeiling ?? exactCountBeforeMutation
                let expectedCount = max(0, currentCeiling - 1)
                unreadCount = expectedCount
                unreadCountPhase = .loaded
                if let pendingUnreadCountCeiling {
                    self.pendingUnreadCountCeiling = min(pendingUnreadCountCeiling, expectedCount)
                } else {
                    pendingUnreadCountCeiling = expectedCount
                }
            } else {
                unreadCount = nil
                unreadCountPhase = .unknown
            }
            unreadCountError = nil
            return true
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
            return false
        }
    }

    private func targetRoute(for notification: UserNotification) -> AppRoute? {
        guard let targetID = normalizedTargetID(notification.targetId) else {
            return nil
        }

        switch targetKind(for: notification) {
        case .gallery:
            return .galleryUploadDetail(targetID)
        case .deleteRequest:
            return .imageDeleteRequestDetail(targetID)
        case .aiGeneration:
            return .aiGenerationDetail(targetID)
        case nil:
            return nil
        }
    }

    private func normalizedTargetID(_ value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let id = Int(value),
              id > 0 else {
            return nil
        }
        return id
    }

    private func targetKind(for notification: UserNotification) -> NotificationTargetKind? {
        let targetType = normalizedTargetType(notification.targetType)
        let compactType = targetType.filter { $0.isLetter || $0.isNumber }

        if NotificationTargetKind.galleryTypes.contains(targetType) {
            return .gallery
        }
        if NotificationTargetKind.deleteRequestTypes.contains(targetType) {
            return .deleteRequest
        }
        if targetType == "AI_GENERATION" || notification.type == "AI_GENERATION_COMPLETED" {
            return .aiGeneration
        }
        if compactType.contains("GALLERY") && (compactType.contains("BATCH") || compactType.contains("SUBMISSION")) {
            return .gallery
        }
        if compactType.contains("DELETE") && compactType.contains("REQUEST") {
            return .deleteRequest
        }
        if notification.type.hasPrefix("GALLERY_SUBMISSION_") {
            return .gallery
        }
        if notification.type.hasPrefix("IMAGE_DELETE_REQUEST_") || notification.type == "IMAGE_AUDIT_PROBLEM_CREATED_DELETE_REQUEST" {
            return .deleteRequest
        }
        return nil
    }

    private func normalizedTargetType(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .map { $0 == "-" || $0.isWhitespace ? "_" : $0 }
            .reduce(into: "") { result, character in
                if character == "_" && result.last == "_" {
                    return
                }
                result.append(character)
            }
    }

    private func markAllRead() async {
        guard !isMarkingAllRead, markingReadIDs.isEmpty else { return }
        let mutationCutoffID = notifications.map(\.id).max()
        let mutationReadIDs = Set(
            notifications.lazy.filter { !isEffectivelyRead($0) }.map(\.id)
        )
        isMarkingAllRead = true
        defer { isMarkingAllRead = false }
        do {
            try await environment.notificationClient.markAllRead()
            invalidateNotificationRequests()
            pendingMarkAllRead = true
            pendingUnreadCountCeiling = 0
            if let mutationCutoffID {
                markAllReadCutoffID = max(markAllReadCutoffID ?? mutationCutoffID, mutationCutoffID)
            }
            optimisticReadIDs.formUnion(mutationReadIDs)
            if unreadOnly {
                notifications = []
                total = 0
                nextPage = 1
            }
            unreadCount = 0
            unreadCountPhase = .loaded
            unreadCountError = nil
            feedback = .success("已将全部通知标为已读")
            let filterAtCommit = unreadOnly
            Task {
                await loadFirstPage(for: filterAtCommit, clearExisting: false)
            }
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error).message)
        }
    }

    private func invalidateNotificationRequests() {
        listGeneration += 1
        countGeneration += 1
        isLoadingFirstPage = false
        isLoadingMore = false
    }
}

private enum NotificationUnreadCountPhase: Equatable {
    case unknown
    case loading
    case loaded
    case failed
}

struct NotificationReadConsistency {
    struct CountSnapshot: Equatable {
        let serverCount: Int
        let firstPageUnreadIDs: Set<Int>
        let pendingMarkAll: Bool
        let markAllCutoffID: Int?
        let confirmedReadIDs: Set<Int>
        let pendingCountCeiling: Int?
    }

    enum CountDecision: Equatable {
        case accept(clearMarkAllPending: Bool, clearCountCeiling: Bool)
        case retry
    }

    static func resolveCount(_ snapshot: CountSnapshot) -> CountDecision {
        if snapshot.pendingMarkAll {
            let hasStaleMarkedAllRows = snapshot.firstPageUnreadIDs.contains { id in
                guard let cutoff = snapshot.markAllCutoffID else { return false }
                return id <= cutoff
            }
            let hasPostMutationUnreadRows = !snapshot.firstPageUnreadIDs.isEmpty
            guard snapshot.serverCount == 0
                    || (hasPostMutationUnreadRows && !hasStaleMarkedAllRows) else {
                return .retry
            }
            return .accept(clearMarkAllPending: true, clearCountCeiling: true)
        }

        if let ceiling = snapshot.pendingCountCeiling {
            let hasStaleReadRows = !snapshot.firstPageUnreadIDs.isDisjoint(
                with: snapshot.confirmedReadIDs
            )
            let hasPostMutationUnreadRows = !snapshot.firstPageUnreadIDs.isEmpty
            guard snapshot.serverCount <= ceiling
                    || (hasPostMutationUnreadRows && !hasStaleReadRows) else {
                return .retry
            }
            return .accept(clearMarkAllPending: false, clearCountCeiling: true)
        }

        return .accept(clearMarkAllPending: false, clearCountCeiling: false)
    }

    static func isEffectivelyRead(
        notificationID: Int,
        serverRead: Bool,
        confirmedReadIDs: Set<Int>,
        markAllCutoffID: Int?
    ) -> Bool {
        if serverRead || confirmedReadIDs.contains(notificationID) {
            return true
        }
        guard let markAllCutoffID else { return false }
        return notificationID <= markAllCutoffID
    }
}

private enum NotificationFetchOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

private enum NotificationTargetKind {
    case gallery
    case deleteRequest
    case aiGeneration

    static let galleryTypes: Set<String> = [
        "BATCH",
        "GALLERY_BATCH",
        "GALLERY_UPLOAD_BATCH",
        "GALLERY_SUBMISSION",
        "GALLERY_SUBMISSION_BATCH",
    ]

    static let deleteRequestTypes: Set<String> = [
        "DELETE_REQUEST",
        "IMAGE_DELETE",
        "IMAGE_DELETE_REQUEST",
    ]
}

private struct NotificationRow: View {
    let notification: UserNotification
    let isRead: Bool
    let isUpdating: Bool
    let onRead: () -> Void

    var body: some View {
        Button(action: onRead) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                HStack {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Spacer()
                    if !isRead {
                        Circle()
                            .fill(SetuColor.brandPink)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 8) {
                    NotificationTypeBadge(type: notification.type)
                }
                Text(notification.content)
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                Text(SetuDateFormatter.string(from: notification.createdAt))
                    .font(.caption)
                    .foregroundStyle(SetuColor.textTertiary)
            }
            .padding(.vertical, SetuSpacing.sm)
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .accessibilityIdentifier("notifications.item.\(notification.id)")
        .accessibilityValue(isUpdating ? "正在标记为已读" : (isRead ? "已读" : "未读"))
        .accessibilityHint(
            isUpdating
                ? "正在更新已读状态"
                : (isRead ? "打开相关内容" : "打开相关内容并标记为已读")
        )
    }
}

private struct NotificationTypeBadge: View {
    let type: String

    var body: some View {
        SetuPill(text: title, tone: tone)
    }

    private var title: String {
        switch type {
        case "GALLERY_SUBMISSION_APPROVED": "投稿通过"
        case "GALLERY_SUBMISSION_REJECTED": "投稿拒绝"
        case "IMAGE_DELETE_REQUEST_APPROVED": "删除申请通过"
        case "IMAGE_DELETE_REQUEST_REJECTED": "删除申请拒绝"
        case "IMAGE_AUDIT_PROBLEM_CREATED_DELETE_REQUEST": "审核问题"
        case "ADMIN_POINTS_GRANTED": "积分到账"
        case "AI_GENERATION_COMPLETED": "AI 绘画完成"
        default: "系统通知"
        }
    }

    private var tone: SetuPillTone {
        switch type {
        case "GALLERY_SUBMISSION_APPROVED", "ADMIN_POINTS_GRANTED", "AI_GENERATION_COMPLETED":
            .success
        case "GALLERY_SUBMISSION_REJECTED":
            .danger
        case "IMAGE_DELETE_REQUEST_APPROVED":
            .success
        case "IMAGE_DELETE_REQUEST_REJECTED", "IMAGE_AUDIT_PROBLEM_CREATED_DELETE_REQUEST":
            .warning
        default:
            .muted
        }
    }
}
