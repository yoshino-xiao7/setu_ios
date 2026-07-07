import SetuIOSCore
import SwiftUI

struct MusicMiniPlayerBar: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var showingDetail = false

    var body: some View {
        if let track = player.currentTrack {
            Button {
                showingDetail = true
            } label: {
                HStack(spacing: 12) {
                    MusicArtworkView(urlString: track.coverURLString)
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(player.queueName ?? "当前歌单") · 正在播放")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("停止播放")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDetail) {
                MusicNowPlayingDetailView(environment: environment, player: player)
            }
        }
    }
}

private struct MusicNowPlayingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var lyricState: LoadState<MusicLyricResponse> = .idle

    var body: some View {
        NavigationStack {
            List {
                if let track = player.currentTrack {
                    Section("正在播放") {
                        HStack(spacing: 14) {
                            MusicArtworkView(urlString: track.coverURLString)
                                .frame(width: 72, height: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(track.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(track.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(track.album)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack {
                            Button {
                                player.toggle()
                            } label: {
                                Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(role: .destructive) {
                                player.stop()
                                dismiss()
                            } label: {
                                Label("停止", systemImage: "stop.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    lyricSection
                        .task(id: track.id) {
                            await loadLyric(songID: track.id)
                        }
                } else {
                    ContentUnavailableView("暂无播放", systemImage: "music.note")
                }
            }
            .navigationTitle("歌词")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var lyricSection: some View {
        Section("歌词") {
            switch lyricState {
            case .idle, .loading:
                ProgressView("正在加载歌词")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let lyric):
                let rawLyric = lyric.lrc?.lyric ?? ""
                let translation = lyric.tlyric?.lyric ?? ""
                if rawLyric.isEmpty && translation.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "text.quote")
                } else {
                    if !rawLyric.isEmpty {
                        Text(rawLyric)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    if !translation.isEmpty {
                        DisclosureGroup("翻译歌词") {
                            Text(translation)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func loadLyric(songID: Int) async {
        lyricState = .loading
        do {
            lyricState = .loaded(try await environment.musicClient.lyric(songID: songID))
        } catch {
            lyricState = .failed(error.localizedDescription)
        }
    }
}
