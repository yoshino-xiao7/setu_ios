import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct JmReaderView: View {
    @Bindable var environment: AppEnvironment
    let albumID: String
    let chapterID: String
    @State private var pagesState: LoadState<[JmPageImage]> = .idle
    @State private var pageIndex = 0
    @State private var syncsFavorite = false
    @State private var chapterTitle: String?
    @State private var favoriteSyncTask: Task<Void, Never>?
    @State private var restorePageIndex: Int?
    @State private var acceptsPageChanges = false

    var body: some View {
        Group {
            switch pagesState {
            case .idle, .loading:
                SetuEmptyState(title: "正在打开阅读器", systemImage: "book", isLoading: true)
            case .failed(let error):
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "章节加载失败", message: error.message, systemImage: "book")
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(SetuSpacing.lg)
            case .loaded(let pages):
                if pages.isEmpty {
                    SetuEmptyState(title: "这一话没有页面", systemImage: "book")
                } else {
                    TabView(selection: $pageIndex) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            JmPageImageView(page: page)
                                .tag(index)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    #endif
                    .overlay(alignment: .bottom) {
                        Text("\(pageIndex + 1) / \(pages.count)")
                            .font(SetuTypography.caption)
                            .padding(.horizontal, SetuSpacing.md)
                            .padding(.vertical, SetuSpacing.sm)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, SetuSpacing.lg)
                    }
                    .task {
                        let target = restorePageIndex ?? pageIndex
                        pageIndex = target
                        try? await Task.sleep(for: .milliseconds(50))
                        pageIndex = target
                        restorePageIndex = nil
                        acceptsPageChanges = true
                        persist(scheduleFavoriteSync: false)
                    }
                    .onChange(of: pageIndex) { _, _ in
                        guard acceptsPageChanges else { return }
                        persist(scheduleFavoriteSync: true)
                    }
                }
            }
        }
        .setuBackground()
        .navigationTitle("阅读")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ModuleFavoriteButton(
                    environment: environment,
                    snapshot: favoriteSnapshot,
                    showsTitle: false,
                    onChanged: { syncsFavorite = $0 }
                )
            }
        }
        .task { await load() }
        .onDisappear {
            favoriteSyncTask?.cancel()
            persist(scheduleFavoriteSync: false)
            Task { await flushFavoriteProgress() }
        }
        .accessibilityIdentifier("jm.reader.page")
    }

    private func load() async {
        pagesState = .loading
        do {
            let pages = try await environment.jmCatalogClient.pages(chapterID: chapterID)
            if let progress = environment.jmReadingProgressStore.progress(albumID: albumID), progress.chapterID == chapterID {
                pageIndex = min(max(progress.pageIndex, 0), max(pages.count - 1, 0))
                chapterTitle = progress.chapterTitle
            } else {
                pageIndex = 0
            }
            restorePageIndex = pageIndex
            acceptsPageChanges = false
            if environment.authSession.isSignedIn, !environment.authSession.requiresReauthentication {
                syncsFavorite = (try? await environment.moduleFavoriteClient.exists(module: .jm, externalId: albumID)) ?? false
            }
            pagesState = .loaded(pages)
            persist(scheduleFavoriteSync: false)
        } catch {
            pagesState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func persist(scheduleFavoriteSync: Bool) {
        guard case .loaded(let pages) = pagesState, !pages.isEmpty else { return }
        let progress = currentProgress(pageCount: pages.count)
        environment.jmReadingProgressStore.save(progress)
        if var record = environment.moduleWatchHistoryStore.records(module: .jm).first(where: { $0.externalId == albumID }) {
            record.subtitle = progress.pageProgressText
            record.viewedAt = Date()
            environment.moduleWatchHistoryStore.record(record)
        }
        if scheduleFavoriteSync {
            favoriteSyncTask?.cancel()
            favoriteSyncTask = Task { [syncsFavorite] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled, syncsFavorite else { return }
                await flushFavoriteProgress()
            }
        }
    }

    private var favoriteSnapshot: ModuleFavoriteSnapshot {
        let record = environment.moduleWatchHistoryStore.records(module: .jm).first(where: { $0.externalId == albumID })
        let extra: String?
        if case .loaded(let pages) = pagesState, !pages.isEmpty {
            extra = currentProgress(pageCount: pages.count).extraJSONString
        } else {
            extra = environment.jmReadingProgressStore.progress(albumID: albumID)?.extraJSONString
        }
        return ModuleFavoriteSnapshot(
            module: .jm,
            externalId: albumID,
            title: record?.title ?? chapterTitle ?? "JM \(albumID)",
            coverUrl: record?.coverUrl,
            subtitle: record?.subtitle,
            extraJson: extra
        )
    }

    private func currentProgress(pageCount: Int) -> JmReadingProgress {
        JmReadingProgress(
            albumID: albumID,
            chapterID: chapterID,
            pageIndex: pageIndex,
            pageCount: pageCount,
            chapterTitle: chapterTitle
        )
    }

    private func flushFavoriteProgress() async {
        guard syncsFavorite, environment.authSession.isSignedIn else { return }
        guard case .loaded(let pages) = pagesState, !pages.isEmpty else { return }
        let progress = currentProgress(pageCount: pages.count)
        guard let record = environment.moduleWatchHistoryStore.records(module: .jm).first(where: { $0.externalId == albumID }) else { return }
        let snapshot = ModuleFavoriteSnapshot(
            module: .jm,
            externalId: albumID,
            title: record.title,
            coverUrl: record.coverUrl,
            subtitle: record.subtitle,
            extraJson: progress.extraJSONString
        )
        _ = try? await environment.moduleFavoriteClient.add(snapshot)
    }
}

private struct JmPageImageView: View {
    let page: JmPageImage
    #if canImport(UIKit)
    @State private var image: UIImage?
    #endif
    @State private var failed = false

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            } else if failed {
                SetuEmptyState(title: "这一页加载失败", systemImage: "photo")
            } else {
                ProgressView()
            }
            #else
            if failed {
                SetuEmptyState(title: "这一页加载失败", systemImage: "photo")
            } else {
                ProgressView()
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    private func load() async {
        do {
            let request = JmAppToken.imageRequest(url: page.url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                failed = true
                return
            }
            #if canImport(UIKit)
            image = JmImageDescrambler.descrambleUIImage(data: data, page: page)
            failed = image == nil
            #else
            let restored = JmImageDescrambler.descramble(data: data, page: page)
            failed = restored.isEmpty
            #endif
        } catch {
            failed = true
        }
    }
}
