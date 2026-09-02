import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif


struct AddSongToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let song: MusicSong
    let onFeedback: (SetuFeedback) -> Void
    @State private var state: LoadState<[UserMusicPlaylist]> = .idle
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌曲")
                            MusicSongRow(song: song)
                        }
                    }
                    .setuListRow()
                }

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                        .setuListRow()
                    }
                }

                switch state {
                case .idle, .loading:
                    MusicStateSection(title: "选择歌单", stateTitle: "正在加载歌单", systemImage: "music.note.list", isLoading: true)
                case .failed(let message):
                    MusicStateSection(title: "选择歌单", stateTitle: "歌单加载失败", message: message, systemImage: "exclamationmark.triangle")
                case .loaded(let playlists):
                    if playlists.isEmpty {
                        MusicStateSection(title: "选择歌单", stateTitle: "暂无歌单", systemImage: "music.note.list")
                    } else {
                        Section {
                            SetuCard {
                                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                    SetuSectionHeader(title: "选择歌单")
                                    VStack(spacing: 0) {
                                        ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                                            Button {
                                                Task { await add(to: playlist) }
                                            } label: {
                                                HStack(spacing: SetuSpacing.md) {
                                                    Image(systemName: "music.note.list")
                                                        .foregroundStyle(SetuColor.brandPink)
                                                        .frame(width: 36, height: 36)
                                                        .background(SetuColor.brandSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                                                    Text(playlist.name)
                                                        .font(SetuTypography.body)
                                                        .foregroundStyle(SetuColor.textPrimary)
                                                        .lineLimit(2)
                                                    Spacer()
                                                    Image(systemName: "plus.circle.fill")
                                                        .foregroundStyle(SetuColor.brandInk)
                                                }
                                                .frame(minHeight: 44)
                                                .contentShape(Rectangle())
                                            }
                                            .setuButtonFeedback()

                                            if index < playlists.count - 1 {
                                                Divider().overlay(SetuColor.separator)
                                            }
                                        }
                                    }
                                }
                            }
                            .setuListRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .setuBackground()
        .setuFeedbackPresentation($feedback)
            .navigationTitle("加入歌单")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.musicClient.playlists())
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func add(to playlist: UserMusicPlaylist) async {
        do {
            try await environment.musicClient.add(song: song, toPlaylist: playlist.id)
            onFeedback(.success("已加入 \(playlist.name)"))
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
