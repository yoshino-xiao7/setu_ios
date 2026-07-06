import SetuIOSCore
import SwiftUI

struct NotificationsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<UserNotificationPage> = .idle
    @State private var unreadOnly = false
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        List {
            Toggle("仅看未读", isOn: $unreadOnly)
                .onChange(of: unreadOnly) {
                    Task {
                        page = 1
                        await load()
                    }
                }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无通知", systemImage: "bell")
                } else {
                    Section("共 \(page.total) 条") {
                        ForEach(page.list) { notification in
                            NotificationRow(notification: notification) {
                                Task { await handleNotificationTap(notification) }
                            }
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .navigationTitle("通知中心")
        .toolbar {
            Button("全部已读") {
                Task { await markAllRead() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: UserNotificationPage) -> some View {
        Section {
            HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(result.page * result.pageSize >= result.total)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.notificationClient.list(page: page, pageSize: pageSize, unreadOnly: unreadOnly))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func handleNotificationTap(_ notification: UserNotification) async {
        if !notification.read {
            try? await environment.notificationClient.markRead(id: notification.id)
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
                        .foregroundStyle(.primary)
                    Spacer()
                    if !notification.read {
                        Circle()
                            .fill(.pink)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(notification.content)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(notification.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
    }
}
