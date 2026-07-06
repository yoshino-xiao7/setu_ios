import SetuIOSCore
import SwiftUI

struct NotificationsView: View {
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
                                Task { await markRead(notification) }
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

    private func markRead(_ notification: UserNotification) async {
        guard !notification.read else { return }
        try? await environment.notificationClient.markRead(id: notification.id)
        await load()
    }

    private func markAllRead() async {
        try? await environment.notificationClient.markAllRead()
        page = 1
        await load()
    }
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
