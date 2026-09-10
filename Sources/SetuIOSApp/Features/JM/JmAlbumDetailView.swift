import SetuIOSCore
import SwiftUI

struct JmAlbumDetailView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let albumID: String
    @State private var state: LoadState<JmAlbum> = .idle
    @State private var reading: JmReadingProgress?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                switch state {
                case .idle, .loading:
                    SetuCard { SetuEmptyState(title: "正在加载本子", systemImage: "book.closed", isLoading: true) }
                case .failed(let error):
                    SetuCard {
                        VStack(spacing: SetuSpacing.md) {
                            SetuEmptyState(title: "本子加载失败", message: error.message, systemImage: "book.closed")
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                case .loaded(let album):
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuImageTile(urlString: album.coverURL, accessibilityLabel: album.title, aspectRatio: 3 / 4)
                            Text(album.title)
                                .font(SetuTypography.title)
                            if !album.subtitle.isEmpty {
                                Text(album.subtitle)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            if let description = album.description, !description.isEmpty {
                                Text(description)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            if let reading {
                                Button {
                                    router.navigate(to: .jmReader(albumID: album.id, chapterID: reading.chapterID))
                                } label: {
                                    Label("继续阅读 \(reading.pageProgressText)", systemImage: "bookmark.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .lineLimit(1)
                                .accessibilityIdentifier("jm.continue.reading")
                            }
                        }
                    }
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            SetuSectionHeader(title: "章节", subtitle: "\(album.chapters.count) 话")
                            ForEach(album.chapters) { chapter in
                                Button {
                                    openChapter(chapter, in: album)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(chapter.title)
                                                .foregroundStyle(SetuColor.textPrimary)
                                            if reading?.chapterID == chapter.id {
                                                Text(reading?.pageProgressText ?? "")
                                                    .font(.caption2)
                                                    .foregroundStyle(SetuColor.brandPink)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: reading?.chapterID == chapter.id ? "bookmark.fill" : "book")
                                            .foregroundStyle(SetuColor.brandPink)
                                    }
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .navigationTitle("本子详情")
        .toolbar {
            if case .loaded(let album) = state {
                ToolbarItem(placement: .topBarTrailing) {
                    ModuleFavoriteButton(
                        environment: environment,
                        snapshot: album.favoriteSnapshot.attaching(extraJson: reading?.extraJSONString),
                        showsTitle: false
                    )
                }
            }
        }
        .task { await load() }
        .onAppear { reading = environment.jmReadingProgressStore.progress(albumID: albumID) }
        .accessibilityIdentifier("jm.album.page")
    }

    private func openChapter(_ chapter: JmChapter, in album: JmAlbum) {
        let existing = environment.jmReadingProgressStore.progress(albumID: album.id)
        let sameChapter = existing?.chapterID == chapter.id
        environment.jmReadingProgressStore.save(
            JmReadingProgress(
                albumID: album.id,
                chapterID: chapter.id,
                pageIndex: sameChapter ? existing?.pageIndex ?? 0 : 0,
                pageCount: sameChapter ? existing?.pageCount ?? 0 : 0,
                chapterTitle: chapter.title
            )
        )
        reading = environment.jmReadingProgressStore.progress(albumID: album.id)
        router.navigate(to: .jmReader(albumID: album.id, chapterID: chapter.id))
    }

    private func load() async {
        state = .loading
        do {
            let album = try await environment.jmCatalogClient.album(id: albumID)
            environment.moduleWatchHistoryStore.record(album.watchRecord)
            reading = environment.jmReadingProgressStore.progress(albumID: album.id)
            state = .loaded(album)
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}
