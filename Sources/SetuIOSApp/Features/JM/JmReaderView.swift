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
    @State private var imageLoader = JmPageImageLoader()
    @State private var readerMode = JmReaderSettings.mode()
    @State private var viewportFrame = CGRect.zero
    @State private var pageFrames: [Int: CGRect] = [:]

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
                    reader(pages: pages)
                }
            }
        }
        .setuBackground()
        .navigationTitle("阅读")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ModuleFavoriteButton(
                    environment: environment,
                    snapshot: favoriteSnapshot,
                    showsTitle: false,
                    onChanged: { syncsFavorite = $0 }
                )
                Menu {
                    Section("阅读模式") {
                        Picker("阅读模式", selection: modeBinding) {
                            ForEach(JmReaderMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("更多")
                .accessibilityIdentifier("jm.reader.more")
            }
        }
        .task { await load() }
        .onDisappear {
            favoriteSyncTask?.cancel()
            persist(scheduleFavoriteSync: false)
            imageLoader.cancelAll()
            Task { await flushFavoriteProgress() }
        }
        .accessibilityIdentifier("jm.reader.page")
    }

    @ViewBuilder
    private func reader(pages: [JmPageImage]) -> some View {
        Group {
            switch readerMode {
            case .paged:
                pagedReader(pages: pages)
            case .continuous:
                continuousReader(pages: pages)
            }
        }
        .overlay(alignment: .bottom) {
            Text("\(pageIndex + 1) / \(pages.count)")
                .font(SetuTypography.caption)
                .padding(.horizontal, SetuSpacing.md)
                .padding(.vertical, SetuSpacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, SetuSpacing.lg)
        }
        .onChange(of: pageIndex) { _, index in
            guard acceptsPageChanges else { return }
            persist(scheduleFavoriteSync: true)
            imageLoader.prefetch(pages: pages, currentIndex: index)
        }
    }

    private func pagedReader(pages: [JmPageImage]) -> some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                JmPageImageView(page: page, loader: imageLoader, layout: .paged)
                    .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        #endif
        .task(id: readerMode) {
            let target = restoredPageIndex(count: pages.count)
            pageIndex = target
            try? await Task.sleep(for: .milliseconds(50))
            pageIndex = target
            finishRestore(pages: pages)
        }
    }

    private func continuousReader(pages: [JmPageImage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SetuSpacing.sm) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        JmPageImageView(page: page, loader: imageLoader, layout: .continuous)
                            .id(index)
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: JmPageFrameKey.self,
                                        value: [index: geo.frame(in: .global)]
                                    )
                                }
                            }
                    }
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: JmViewportFrameKey.self, value: geo.frame(in: .global))
                }
            }
            .onPreferenceChange(JmViewportFrameKey.self) { frame in
                viewportFrame = frame
                adoptVisiblePage()
            }
            .onPreferenceChange(JmPageFrameKey.self) { frames in
                pageFrames = frames
                adoptVisiblePage()
            }
            .task(id: readerMode) {
                let target = restoredPageIndex(count: pages.count)
                pageIndex = target
                proxy.scrollTo(target, anchor: .top)
                try? await Task.sleep(for: .milliseconds(80))
                proxy.scrollTo(target, anchor: .top)
                finishRestore(pages: pages)
            }
        }
    }

    private func restoredPageIndex(count: Int) -> Int {
        min(max(restorePageIndex ?? pageIndex, 0), max(count - 1, 0))
    }

    private func finishRestore(pages: [JmPageImage]) {
        restorePageIndex = nil
        acceptsPageChanges = true
        persist(scheduleFavoriteSync: false)
        imageLoader.prefetch(pages: pages, currentIndex: pageIndex)
    }

    private func adoptVisiblePage() {
        guard readerMode == .continuous, acceptsPageChanges else { return }
        guard let index = JmVisiblePageResolver.index(viewport: viewportFrame, frames: pageFrames) else { return }
        if index != pageIndex {
            pageIndex = index
        }
    }

    private var modeBinding: Binding<JmReaderMode> {
        Binding(
            get: { readerMode },
            set: { newValue in
                guard newValue != readerMode else { return }
                acceptsPageChanges = false
                restorePageIndex = pageIndex
                readerMode = newValue
                JmReaderSettings.save(newValue)
            }
        )
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
            imageLoader.prefetch(pages: pages, currentIndex: pageIndex)
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
    enum Layout {
        case paged
        case continuous
    }

    let page: JmPageImage
    @Bindable var loader: JmPageImageLoader
    var layout: Layout = .paged

    var body: some View {
        let _ = loader.revision
        ZStack {
            #if canImport(UIKit)
            if let image = loader.image(for: page) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            } else if loader.isFailed(page) {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "这一页加载失败", systemImage: "photo")
                    Button("重试") { loader.retry(page) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
            #else
            if loader.isFailed(page) {
                SetuEmptyState(title: "这一页加载失败", systemImage: "photo")
            } else {
                ProgressView()
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: layout == .paged ? .infinity : nil)
        .modifier(JmPageAspectRatio(isActive: layout == .continuous, ratio: continuousAspectRatio))
        .task { loader.ensure(page) }
    }

    private var continuousAspectRatio: CGFloat {
        #if canImport(UIKit)
        if let image = loader.image(for: page), image.size.height > 0 {
            return image.size.width / image.size.height
        }
        #endif
        return 2.0 / 3.0
    }
}

private struct JmPageAspectRatio: ViewModifier {
    let isActive: Bool
    let ratio: CGFloat

    func body(content: Content) -> some View {
        if isActive {
            content.aspectRatio(ratio, contentMode: .fit)
        } else {
            content
        }
    }
}

private struct JmPageFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct JmViewportFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
