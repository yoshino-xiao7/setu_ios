import SetuIOSCore
import SwiftUI

struct JmAlbumDetailView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let albumID: String
    @State private var state: LoadState<JmAlbum> = .idle

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
                            ModuleFavoriteButton(environment: environment, snapshot: album.favoriteSnapshot)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            SetuSectionHeader(title: "章节", subtitle: "\(album.chapters.count) 话")
                            ForEach(album.chapters) { chapter in
                                Button {
                                    router.navigate(to: .jmReader(albumID: album.id, chapterID: chapter.id))
                                } label: {
                                    HStack {
                                        Text(chapter.title)
                                            .foregroundStyle(SetuColor.textPrimary)
                                        Spacer()
                                        Image(systemName: "book")
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
        .task { await load() }
        .accessibilityIdentifier("jm.album.page")
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.jmCatalogClient.album(id: albumID))
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}
