import SetuIOSCore
import SwiftUI

struct AiSquareView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<AiPublicWork>(pageSize: 16)
    private var jobs: [AiPublicWork] {
        get { pager.items }
        nonmutating set { pager.replaceItems(newValue) }
    }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    @State private var category = "GENERAL"
    private let pageSize = 16

    var body: some View {
        SetuBoard {
            SetuFilterBar(
                options: [.init(value: "", title: "全部"), .init(value: "GENERAL", title: "全年龄"), .init(value: "R18", title: "成人内容")],
                selection: $category
            )
            .onChange(of: category) {
                Task { await loadFirstPage(clearExisting: true) }
            }

            if isInitialLoading {
                SetuCard {
                    SetuEmptyState(title: "正在加载 AI 绘画广场", systemImage: "photo.on.rectangle", isLoading: true)
                }
            } else if jobs.isEmpty {
                if let loadError {
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "AI 绘画广场加载失败", message: loadError, systemImage: "wifi.exclamationmark")
                            Button("重试") { Task { await loadFirstPage() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    SetuCard {
                        SetuEmptyState(
                            title: "暂无公开 AI 作品",
                            message: "稍后再来看看新的公开创作。",
                            systemImage: "sparkles",
                            actionTitle: "刷新广场",
                            action: { Task { await loadFirstPage() } }
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "广场作品")
                    SetuMosaic(items: jobs, aspectRatio: { CGFloat($0.width) / CGFloat(max($0.height, 1)) }) { job in
                        AiGenerationGridTile(work: job, footerTitle: SetuDateFormatter.string(from: job.createdAt)) {
                            router.navigate(to: .publicAiWork(PublicAiWorkSnapshot(work: job)))
                        }
                        .onAppear {
                            if job.id == jobs.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                    loadMoreFooter
                }
            }
        }
        .setuBackground()
        .navigationTitle("AI 绘画广场")
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        SetuLoadMoreFooter(state: loadMoreFooterState) {
            Task { await loadMore() }
        }
    }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !hasMore { return .complete("已加载全部 \(total) 个作品") }
        return .idle
    }

    private var hasMore: Bool { pager.hasMore }

    private func loadFirstPage(clearExisting: Bool = false) async {
        let filter = category
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.aiGenerationClient.square(category: filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func loadMore() async {
        let filter = category
        await pager.loadMore { page in
            let result = try await environment.aiGenerationClient.square(category: filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }
}

#if DEBUG
#Preview("AI 广场 · 430 · 深色") {
    SetuFeaturePreviewHost { environment, _ in
        AiSquareView(environment: environment)
    }
    .frame(width: 430, height: 932)
    .preferredColorScheme(.dark)
}
#endif
