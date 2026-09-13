import SetuIOSCore
import SwiftUI

struct CloudVideoHomeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<CloudVideoItem>(pageSize: 24)
    @State private var searchText = ""
    @State private var keyword = ""

    private var signedIn: Bool { environment.authSession.currentUser != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                if signedIn {
                    ModuleCatalogSearchField(text: $searchText, prompt: "搜索云视频", identifier: "cloudVideo.search.field") {
                        submitSearch()
                    }
                }
                if !signedIn {
                    SetuCard {
                        SetuEmptyState(
                            title: "请先登录",
                            message: "云视频需要登录后观看。游客可以先浏览其他功能页，登录后即可搜索播放。",
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                    }
                } else if pager.phase == .loadingInitial {
                    SetuCard {
                        SetuEmptyState(title: "正在加载云视频", systemImage: "cloud", isLoading: true)
                    }
                } else if pager.items.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: keyword.isEmpty ? "全部视频" : "搜索结果", subtitle: "共 \(pager.total) 部")
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(pager.items) { video in
                            Button {
                                router.navigate(to: .cloudVideoDetail(video.id))
                            } label: {
                                catalogCard(video)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("cloudVideo.item.\(video.id)")
                            .onAppear {
                                if video.id == pager.items.last?.id {
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
        .navigationTitle("云视频")
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage(clearExisting: true) }
        .accessibilityIdentifier("cloudVideo.home.page")
    }

    private func catalogCard(_ video: CloudVideoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SetuImageTile(
                urlString: video.coverUrl,
                accessibilityLabel: video.title,
                aspectRatio: 16 / 9,
                allowsTapToRetry: true
            )
                .overlay(alignment: .topLeading) {
                    if video.isR18 {
                        Text("R18")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.red.opacity(0.88), in: Capsule())
                            .padding(6)
                    }
                }
            Text(video.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(2)
            Text("\(video.durationText) · \(video.ratingText)")
                .font(.caption2)
                .foregroundStyle(SetuColor.textSecondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = pager.initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "云视频加载失败", message: error.message, systemImage: "cloud")
                    Button("重试") { Task { await loadFirstPage() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(
                    title: keyword.isEmpty ? "暂无云视频" : "没有匹配的视频",
                    message: keyword.isEmpty ? "管理员发布后会出现在这里。" : "换个关键词再试试。",
                    systemImage: "cloud"
                )
            }
        }
    }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 156), spacing: SetuSpacing.md)]
    }

    private var footerState: SetuLoadMoreFooterState {
        if pager.phase == .loadingMore { return .loading }
        if let error = pager.loadMoreError { return .failed(error) }
        if !pager.hasMore { return .complete("已加载全部 \(pager.total) 部") }
        return .idle
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        guard signedIn else { return }
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let offset = (page - 1) * pager.pageSize
            let result = try await environment.cloudVideoClient.catalog(
                keywords: keyword,
                offset: offset,
                limit: pager.pageSize
            )
            return .init(items: result.items, total: result.total)
        }
    }

    private func loadMore() async {
        guard signedIn else { return }
        await pager.loadMore { page in
            let offset = (page - 1) * pager.pageSize
            let result = try await environment.cloudVideoClient.catalog(
                keywords: keyword,
                offset: offset,
                limit: pager.pageSize
            )
            return .init(items: result.items, total: result.total)
        }
    }

    private func submitSearch() {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await loadFirstPage(clearExisting: true) }
    }
}
