import SetuIOSCore
import SwiftUI

struct HanimeHomeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<HanimeWork>(pageSize: 24)
    @State private var searchText = ""
    @State private var keyword = ""
    @State private var selectedGenre = HanimeGenre.latest
    @State private var history: [ModuleWatchRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                ModuleCatalogSearchField(text: $searchText, prompt: "搜索作品", identifier: "hanime.search.field") {
                    submitSearch()
                }
                genreStrip
                ModuleWatchHistoryStrip(
                    title: "观看历史",
                    records: history,
                    aspectRatio: 16 / 9
                ) {
                    router.navigate(to: .hanimeHistory)
                } onOpen: { record in
                    router.navigate(to: .hanimeWork(record.externalId))
                }
                if pager.phase == .loadingInitial {
                    SetuCard {
                        SetuEmptyState(title: "正在加载 H 动漫", message: "正在从 hanime1.me 读取目录。", systemImage: "play.rectangle", isLoading: true)
                    }
                } else if pager.items.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: selectedGenre.title, subtitle: "共 \(pager.total) 部", actionTitle: "我的收藏") {
                        router.navigate(to: .hanimeFavorites)
                    }
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(pager.items) { work in
                            Button {
                                router.navigate(to: .hanimeWork(work.id))
                            } label: {
                                catalogCard(work)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if work.id == pager.items.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    SetuLoadMoreFooter(state: footerState) {
                        Task { await loadMore() }
                    }
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("H 动漫")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("我的收藏") { router.navigate(to: .hanimeFavorites) }
            }
        }
        .task { reloadHistory(); await loadFirstPage() }
        .refreshable { reloadHistory(); await loadFirstPage(clearExisting: true) }
        .onAppear { reloadHistory() }
        .accessibilityIdentifier("hanime.home.page")
    }

    private func catalogCard(_ work: HanimeWork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SetuImageTile(urlString: work.coverURL, accessibilityLabel: work.displayTitle, aspectRatio: 16 / 9)
            Text(work.displayTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(2)
            if !work.subtitle.isEmpty {
                Text(work.subtitle)
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = pager.initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "H 动漫加载失败", message: error.message, systemImage: "play.rectangle")
                    Button("重试") { Task { await loadFirstPage() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无作品", message: "换个关键词或分类再试试。", systemImage: "play.rectangle")
            }
        }
    }

    private var genreStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(HanimeGenre.catalog) { genre in
                    let selected = genre.id == selectedGenre.id
                    Button(genre.title) {
                        guard selectedGenre.id != genre.id else { return }
                        selectedGenre = genre
                        Task { await loadFirstPage(clearExisting: true) }
                    }
                    .font(.subheadline.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? SetuColor.textPrimary : SetuColor.textSecondary)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanime.genre.\(genre.id)")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
        .accessibilityIdentifier("hanime.genre.strip")
    }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 156), spacing: SetuSpacing.md)]
    }

    private var footerState: SetuLoadMoreFooterState {
        if pager.phase == .loadingMore { return .loading }
        if let error = pager.loadMoreError { return .failed(error) }
        if !pager.hasMore { return .complete("已加载全部 \(pager.total) 部") }
        return .idle
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.hanimeCatalogClient.works(page: page, keyword: keyword, genre: selectedGenre)
            return .init(items: result.works, total: result.total, hasMore: result.hasMore)
        }
    }

    private func loadMore() async {
        await pager.loadMore { page in
            let result = try await environment.hanimeCatalogClient.works(page: page, keyword: keyword, genre: selectedGenre)
            return .init(items: result.works, total: result.total, hasMore: result.hasMore)
        }
    }

    private func submitSearch() {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await loadFirstPage(clearExisting: true) }
    }

    private func reloadHistory() {
        history = environment.moduleWatchHistoryStore.records(module: .hanime)
    }
}
