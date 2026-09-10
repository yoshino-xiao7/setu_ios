import SetuIOSCore
import SwiftUI

struct JmFavoriteListView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<ModuleFavoriteItem>(pageSize: 24)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                if pager.phase == .loadingInitial {
                    SetuCard { SetuEmptyState(title: "正在加载收藏", systemImage: "heart", isLoading: true) }
                } else if pager.items.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: "我的 JM 收藏", subtitle: "共 \(pager.total) 部")
                    LazyVGrid(columns: columns, spacing: SetuSpacing.md) {
                        ForEach(pager.items) { item in
                            Button { router.navigate(to: .jmAlbum(item.externalId)) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    SetuImageTile(urlString: item.coverUrl, accessibilityLabel: item.title, aspectRatio: 3 / 4)
                                    Text(item.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(SetuColor.textPrimary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.id == pager.items.last?.id { Task { await loadMore() } }
                            }
                        }
                    }
                    SetuLoadMoreFooter(state: footerState) { Task { await loadMore() } }
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("JM 收藏")
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage(clearExisting: true) }
        .accessibilityIdentifier("jm.favorites.page")
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = pager.initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "收藏加载失败", message: error.message, systemImage: "heart")
                    Button("重试") { Task { await loadFirstPage() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard { SetuEmptyState(title: "还没有收藏", message: "在本子详情里点收藏，就会出现在这里。", systemImage: "heart") }
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140), spacing: SetuSpacing.md)]
    }

    private var footerState: SetuLoadMoreFooterState {
        if pager.phase == .loadingMore { return .loading }
        if let error = pager.loadMoreError { return .failed(error) }
        if !pager.hasMore { return .complete("已加载全部 \(pager.total) 部") }
        return .idle
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.moduleFavoriteClient.list(module: .jm, page: page, size: pager.pageSize)
            return .init(items: result.items, total: result.total)
        }
    }

    private func loadMore() async {
        await pager.loadMore { page in
            let result = try await environment.moduleFavoriteClient.list(module: .jm, page: page, size: pager.pageSize)
            return .init(items: result.items, total: result.total)
        }
    }
}
