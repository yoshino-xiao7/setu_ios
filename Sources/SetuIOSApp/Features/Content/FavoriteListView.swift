import SetuIOSCore
import SwiftUI

struct FavoriteListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<FavoritePage> = .idle
    @State private var errorMessage: String?
    @State private var page = 1
    private let pageSize = 24

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("收藏加载失败", systemImage: "heart.slash", description: Text(message))
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentUnavailableView("暂无默认收藏", systemImage: "heart", description: Text("收藏图片后会显示在这里。"))
                } else {
                    Section("共 \(page.total) 张") {
                        ForEach(page.items) { item in
                            FavoriteImageRow(item: item) {
                                Task { await remove(item) }
                            }
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .navigationTitle("默认收藏")
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: FavoritePage) -> some View {
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
                .disabled(result.page * result.size >= result.total)
            }
        }
    }

    private func load() async {
        state = .loading
        errorMessage = nil
        do {
            state = .loaded(try await environment.favoriteClient.list(page: page, size: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func remove(_ item: FavoriteItem) async {
        errorMessage = nil
        do {
            try await environment.favoriteClient.remove(pid: item.pid, p: item.p)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FavoriteImageRow: View {
    let item: FavoriteItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: item.image?.urlSmall ?? item.image?.urlRegular)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.image?.title ?? "PID \(item.pid)")
                    .font(.headline)
                    .lineLimit(2)
                Text(item.image?.author ?? "未知作者")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.p)", systemImage: "number")
                    if let favoritedAt = item.favoritedAt {
                        Label(favoritedAt, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "heart.slash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct ImageThumbnailView: View {
    let urlString: String?
    var width: CGFloat = 58
    var height: CGFloat = 58

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
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
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.pink.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.pink)
            }
    }
}
