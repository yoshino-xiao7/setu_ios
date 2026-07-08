import SetuIOSCore
import SwiftUI

struct NotificationsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<UserNotificationPage> = .idle
    @State private var unreadOnly = false
    @State private var unreadCount = 0
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        List {
            Section {
                SetuCard {
                    Toggle("仅看未读", isOn: $unreadOnly)
                        .tint(SetuColor.brandPink)
                        .onChange(of: unreadOnly) {
                            Task {
                                page = 1
                                await load()
                            }
                        }
                    if unreadCount > 0 {
                        SetuPill(text: "\(unreadCount) 条未读", systemImage: "bell.badge", tone: .brand)
                    }
                }
            }
            .setuListRow()

            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载通知", systemImage: "bell", isLoading: true)
                    }
                }
                .setuListRow()
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "通知加载失败", message: message, systemImage: "bell.badge")
                    }
                }
                .setuListRow()
            case .loaded(let page):
                if page.list.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(title: "暂无通知", systemImage: "bell")
                        }
                    }
                    .setuListRow()
                } else {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "共 \(page.total) 条")
                                ForEach(page.list) { notification in
                                    NotificationRow(notification: notification) {
                                        Task { await handleNotificationTap(notification) }
                                    }
                                }
                            }
                        }
                    }
                    .setuListRow()
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle(unreadCount > 0 ? "通知中心 (\(unreadCount))" : "通知中心")
        .toolbar {
            Button("全部已读") {
                Task { await markAllRead() }
            }
            .disabled(unreadCount == 0)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: UserNotificationPage) -> some View {
        Section {
            HStack(spacing: SetuSpacing.md) {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)
                .buttonStyle(.bordered)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(result.page * result.pageSize >= result.total)
                .buttonStyle(.bordered)
            }
        }
        .setuListRow()
    }

    private func load() async {
        state = .loading
        do {
            async let notifications = environment.notificationClient.list(page: page, pageSize: pageSize, unreadOnly: unreadOnly)
            async let unread = environment.notificationClient.unreadCount()
            state = .loaded(try await notifications)
            unreadCount = (try? await unread) ?? unreadCount
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func handleNotificationTap(_ notification: UserNotification) async {
        if !notification.read {
            do {
                try await environment.notificationClient.markRead(id: notification.id)
                unreadCount = max(0, unreadCount - 1)
            } catch {
                // Keep navigation responsive; the next load will reconcile read state.
            }
        }

        if let route = targetRoute(for: notification) {
            router.navigate(to: route)
        } else {
            await load()
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
        try? await environment.notificationClient.markAllRead()
        unreadCount = 0
        page = 1
        await load()
    }
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
    let onRead: () -> Void

    var body: some View {
        Button(action: onRead) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Spacer()
                    if !notification.read {
                        Circle()
                            .fill(SetuColor.brandPink)
                            .frame(width: 8, height: 8)
                    }
                }
                HStack(spacing: 8) {
                    NotificationTypeBadge(type: notification.type)
                    if let targetText = targetText {
                        Text(targetText)
                            .font(.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
                Text(notification.content)
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                Text(notification.createdAt)
                    .font(.caption)
                    .foregroundStyle(SetuColor.textTertiary)
            }
            .padding(.vertical, SetuSpacing.sm)
        }
        .buttonStyle(.plain)
    }

    private var targetText: String? {
        guard notification.targetType?.isEmpty == false || notification.targetId?.isEmpty == false else {
            return nil
        }
        return "\(notification.targetType ?? "目标") #\(notification.targetId ?? "-")"
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
        default: type
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
