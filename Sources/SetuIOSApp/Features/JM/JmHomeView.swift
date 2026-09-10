import SetuIOSCore
import SwiftUI

struct JmHomeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<JmAlbum>(pageSize: 20)
    @State private var searchText = ""
    @State private var keyword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                ModuleCatalogSearchField(text: $searchText, prompt: "搜索本子", identifier: "jm.search.field") {
                    submitSearch()
                }
                if pager.phase == .loadingInitial {
                    SetuCard {
                        SetuEmptyState(title: "正在加载本子", message: "正在从禁漫天堂读取目录。", systemImage: "book.closed", isLoading: true)
                    }
                } else if pager.items.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: "JM 本子", subtitle: "共 \(pager.total) 部", actionTitle: "我的收藏") {
                        router.navigate(to: .jmFavorites)
                    }
                    LazyVGrid(columns: columns, spacing: SetuSpacing.md) {
                        ForEach(pager.items) { album in
                            Button { router.navigate(to: .jmAlbum(album.id)) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    SetuImageTile(urlString: album.coverURL, accessibilityLabel: album.title, aspectRatio: 3 / 4)
                                    Text(album.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(SetuColor.textPrimary)
                                        .lineLimit(2)
                                    if !album.subtitle.isEmpty {
                                        Text(album.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(SetuColor.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if album.id == pager.items.last?.id { Task { await loadMore() } }
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
        .navigationTitle("JM 本子")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("我的收藏") { router.navigate(to: .jmFavorites) }
            }
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage(clearExisting: true) }
        .accessibilityIdentifier("jm.home.page")
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = pager.initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "本子加载失败", message: error.message, systemImage: "book.closed")
                    Button("重试") { Task { await loadFirstPage() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard { SetuEmptyState(title: "暂无本子", message: "换个关键词再试试。", systemImage: "book.closed") }
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
            let result = try await environment.jmCatalogClient.albums(page: page, keyword: keyword)
            return .init(items: result.albums, total: result.total)
        }
    }

    private func loadMore() async {
        await pager.loadMore { page in
            let result = try await environment.jmCatalogClient.albums(page: page, keyword: keyword)
            return .init(items: result.albums, total: result.total)
        }
    }

    private func submitSearch() {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await loadFirstPage(clearExisting: true) }
    }
}
