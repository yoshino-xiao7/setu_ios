import SetuIOSCore
import SwiftUI

struct AiSquareView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var category = "GENERAL"
    @State private var jobs: [AiPublicWork] = []
    @State private var total = 0
    @State private var nextPage = 1
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    private let pageSize = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
            Picker("分类", selection: $category) {
                Text("全部").tag("")
                Text("全年龄").tag("GENERAL")
                Text("成人内容").tag("R18")
            }
            .pickerStyle(.segmented)
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
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(jobs) { job in
                            AiGenerationGridTile(work: job, footerTitle: SetuDateFormatter.string(from: job.createdAt)) {
                                router.navigate(to: .publicAiWork(PublicAiWorkSnapshot(work: job)))
                            }
                            .onAppear {
                                if job.id == jobs.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    loadMoreFooter
                }
            }
        }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
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

    private var hasMore: Bool { jobs.count < total }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 148), spacing: SetuSpacing.md)]
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        let requestedCategory = category
        if clearExisting {
            jobs = []
            total = 0
            nextPage = 1
        }
        isInitialLoading = jobs.isEmpty
        isLoadingMore = false
        loadError = nil
        do {
            let result = try await environment.aiGenerationClient.square(category: requestedCategory, page: 1, pageSize: pageSize)
            guard requestedCategory == category else { return }
            jobs = result.list
            total = result.total
            nextPage = 2
        } catch {
            guard requestedCategory == category else { return }
            loadError = UserFacingErrorMapper.map(error).message
        }
        isInitialLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        let requestedCategory = category
        let requestedPage = nextPage
        isLoadingMore = true
        loadError = nil
        defer { isLoadingMore = false }
        do {
            let result = try await environment.aiGenerationClient.square(category: requestedCategory, page: requestedPage, pageSize: pageSize)
            guard requestedCategory == category, requestedPage == nextPage else { return }
            let existingIDs = Set(jobs.map(\.id))
            jobs.append(contentsOf: result.list.filter { !existingIDs.contains($0.id) })
            total = result.total
            nextPage += 1
        } catch {
            guard requestedCategory == category else { return }
            loadError = UserFacingErrorMapper.map(error).message
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
