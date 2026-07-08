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
                SetuCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .setuListRow()
            }

            switch state {
            case .idle, .loading:
                ContentImageStateSection(title: "正在加载收藏", message: "默认收藏会按最新顺序展示。", systemImage: "heart", isLoading: true)
            case .failed(let message):
                ContentImageStateSection(title: "收藏加载失败", message: message, systemImage: "heart.slash")
            case .loaded(let page):
                if page.items.isEmpty {
                    ContentImageStateSection(title: "暂无默认收藏", message: "收藏图片后会显示在这里。", systemImage: "heart")
                } else {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "共 \(page.total) 张", subtitle: "默认收藏")
                            ForEach(Array(page.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Divider()
                                        .overlay(SetuColor.separator)
                                }
                                FavoriteImageRow(item: item) {
                                    Task { await remove(item) }
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
        .navigationTitle("默认收藏")
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: FavoritePage) -> some View {
        SetuCard {
            HStack {
                Button {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()

                Button {
                    Task {
                        page += 1
                        await load()
                    }
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .frame(minHeight: 44)
                }
                .disabled(result.page * result.size >= result.total)
            }
            .font(SetuTypography.body)
        }
        .setuListRow()
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
        HStack(spacing: SetuSpacing.md) {
            ImageThumbnailView(urlString: item.image?.urlSmall ?? item.image?.urlRegular)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(item.image?.title ?? "PID \(item.pid)")
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.image?.author ?? "未知作者")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.p)", systemImage: "number")
                    if let favoritedAt = item.favoritedAt {
                        Label(favoritedAt, systemImage: "calendar")
                    }
                }
                .font(.caption2)
                .foregroundStyle(SetuColor.textTertiary)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "heart.slash")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

struct ContentImageStateSection: View {
    let title: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        SetuCard {
            SetuEmptyState(title: title, message: message, systemImage: systemImage, isLoading: isLoading)
        }
        .setuListRow()
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
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
            .fill(SetuColor.brandSoft.opacity(0.18))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(SetuColor.brandPink)
            }
    }
}
