import SetuIOSCore
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif

struct NowPlayingLyricsPane: View {
    let model: NowPlayingLyricsModel
    @Bindable var player: MusicPlaybackController
    let onShowCover: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .idle, .loading:
                empty(title: "正在加载歌词", loading: true)
            case .failed(let error):
                empty(title: "歌词加载失败", message: error.message)
            case .loaded(let lines):
                if lines.isEmpty {
                    empty(title: "暂无歌词", message: "这首歌暂时没有可用歌词")
                } else {
                    LyricScrollView(lines: lines, currentTime: player.currentTimeSeconds, expands: true,
                                    isPlaying: player.isPlaying && !player.isBuffering, sampleTime: playbackTime,
                                    onBackgroundTap: showCover) { time in
                        PlayerHaptics.light()
                        player.seek(to: time)
                    }
                    .id(model.identity)
                    .accessibilityIdentifier("music.lyrics")
                    #if DEBUG
                    .accessibilityValue("parses=\(MusicPerformanceProbe.shared.parseCount)")
                    #endif
                    .padding(.horizontal, SetuSpacing.sm)
                }
            }
        }
    }

    private func empty(title: String, message: String? = nil, loading: Bool = false) -> some View {
        VStack {
            Spacer()
            SetuEmptyState(title: title, message: message, systemImage: "text.quote", isLoading: loading)
                .contentShape(Rectangle()).onTapGesture(perform: showCover)
            Spacer()
        }
    }

    private func playbackTime() -> TimeInterval {
        #if canImport(AVFoundation)
        if !player.isSeeking, let time = player.player?.currentTime().seconds, time.isFinite { return time }
        #endif
        return player.currentTimeSeconds
    }

    private func showCover() {
        PlayerHaptics.light()
        onShowCover()
    }
}
