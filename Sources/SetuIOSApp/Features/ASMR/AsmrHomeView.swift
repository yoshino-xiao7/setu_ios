import SetuIOSCore
import SwiftUI

struct AsmrHomeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<AsmrWork>(pageSize: 20)
    @State private var searchText = ""
    @State private var keyword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                ModuleCatalogSearchField(text: $searchText, prompt: "搜索作品", identifier: "asmr.search.field") {
                    submitSearch()
                }
                if pager.phase == .loadingInitial {
                    SetuCard {
                        SetuEmptyState(title: "正在加载 ASMR", message: "正在从 asmr.one 读取目录。", systemImage: "headphones", isLoading: true)
                    }
                } else if pager.items.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: "音声作品", subtitle: "共 \(pager.total) 部", actionTitle: "我的收藏") {
                        router.navigate(to: .asmrFavorites)
                    }
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(pager.items) { work in
                            Button {
                                router.navigate(to: .asmrWork(String(work.id)))
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
        .navigationTitle("ASMR")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("我的收藏") { router.navigate(to: .asmrFavorites) }
            }
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage(clearExisting: true) }
        .accessibilityIdentifier("asmr.home.page")
    }

    private func catalogCard(_ work: AsmrWork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SetuImageTile(urlString: work.coverURL, accessibilityLabel: work.displayTitle, aspectRatio: 1)
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
                    SetuEmptyState(title: "ASMR 加载失败", message: error.message, systemImage: "headphones")
                    Button("重试") { Task { await loadFirstPage() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无作品", message: "换个关键词再试试。", systemImage: "headphones")
            }
        }
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
            let result = try await environment.asmrCatalogClient.works(page: page, pageSize: pager.pageSize, keyword: keyword)
            return .init(items: result.works, total: result.total)
        }
    }

    private func loadMore() async {
        await pager.loadMore { page in
            let result = try await environment.asmrCatalogClient.works(page: page, pageSize: pager.pageSize, keyword: keyword)
            return .init(items: result.works, total: result.total)
        }
    }

    private func submitSearch() {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await loadFirstPage(clearExisting: true) }
    }
}

struct ModuleCatalogSearchField: View {
    @Binding var text: String
    let prompt: String
    var identifier: String = "module.search.field"
    let onSubmit: () -> Void

    var body: some View {
        SetuCard {
            HStack(spacing: SetuSpacing.sm) {
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier(identifier)
                Button("搜索", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
        }
    }
}
