import Foundation

public struct AppConfig: Sendable {
    public var apiBaseURL: URL
    public var siteBaseURL: URL
    public var musicFeatureFlags: MusicFeatureFlags

    public init(apiBaseURL: URL, siteBaseURL: URL, musicFeatureFlags: MusicFeatureFlags = .init()) {
        self.apiBaseURL = apiBaseURL
        self.siteBaseURL = siteBaseURL
        self.musicFeatureFlags = musicFeatureFlags
    }

    public static let production = AppConfig(
        apiBaseURL: URL(string: "https://api.yukiryou.icu")!,
        siteBaseURL: URL(string: "https://cloud.yukiryou.icu")!
    )

    /// 调试 / 本地联调环境：允许通过启动参数或 UserDefaults 覆盖 base URL，
    /// 无需改动编译产物。仅 DEBUG 生效，例如：
    ///   -SETU_API_BASE_URL http://127.0.0.1:9898
    public static func resolved() -> AppConfig {
        #if DEBUG
        let overrides = UserDefaults.standard
        if let api = overrides.string(forKey: "SETU_API_BASE_URL"), let apiURL = URL(string: api) {
            let site = overrides.string(forKey: "SETU_SITE_BASE_URL")
                .flatMap(URL.init(string:)) ?? apiURL
            return AppConfig(apiBaseURL: apiURL, siteBaseURL: site, musicFeatureFlags: .resolved(from: overrides))
        }
        return AppConfig(apiBaseURL: production.apiBaseURL, siteBaseURL: production.siteBaseURL, musicFeatureFlags: .resolved(from: overrides))
        #else
        return .production
        #endif
    }
}

public enum MusicFeatureRoute: Hashable, Sendable {
    case search, playback, lyrics, home, playlistDetail
    case artistDetail, albumDetail, rankings, newReleases, radioFM, likedTracks, favoritePlaylists
    case wordByWordLyrics, airPlayPicker
}

public extension MusicFeatureFlags {
    func isEnabled(_ route: MusicFeatureRoute) -> Bool {
        switch route {
        case .search: usesV2Search
        case .playback: usesV2Playback
        case .lyrics: usesV2Lyrics
        case .home: usesV2Home
        case .playlistDetail: usesV2PlaylistDetail
        case .artistDetail: artistDetailEnabled
        case .albumDetail: albumDetailEnabled
        case .rankings: rankingsEnabled
        case .newReleases: newReleasesEnabled
        case .radioFM: radioFMEnabled
        case .likedTracks: likedTracksEnabled
        case .favoritePlaylists: favoritePlaylistsEnabled
        case .wordByWordLyrics: wordByWordLyricsEnabled
        case .airPlayPicker: airPlayPickerEnabled
        }
    }
}

public struct MusicFeatureFlags: Equatable, Sendable {
    public var usesV2Search = false
    public var usesV2Playback = false
    public var usesV2Lyrics = false
    public var usesV2History = false
    public var usesV2Home = false
    public var usesV2PlaylistDetail = false
    public var artistDetailEnabled = false
    public var albumDetailEnabled = false
    public var rankingsEnabled = false
    public var newReleasesEnabled = false
    public var radioFMEnabled = false
    public var likedTracksEnabled = false
    public var favoritePlaylistsEnabled = false
    public var wordByWordLyricsEnabled = false
    public var airPlayPickerEnabled = false

    public init() {}

    /// Complete supported development experience, independent of transient launch arguments.
    public static var development: Self {
        var flags = Self()
        flags.usesV2Search = true
        flags.usesV2Playback = true
        flags.usesV2Lyrics = true
        flags.usesV2History = true
        flags.usesV2Home = true
        flags.usesV2PlaylistDetail = true
        flags.radioFMEnabled = true
        flags.likedTracksEnabled = true
        flags.favoritePlaylistsEnabled = true
        flags.wordByWordLyricsEnabled = true
        flags.airPlayPickerEnabled = true
        return flags
    }

    #if DEBUG
    static func resolved(from defaults: UserDefaults) -> Self {
        var flags = Self.development
        flags.usesV2Search = defaults.musicFlag("SETU_MUSIC_USES_V2_SEARCH", defaultValue: flags.usesV2Search)
        flags.usesV2Playback = defaults.musicFlag("SETU_MUSIC_USES_V2_PLAYBACK", defaultValue: flags.usesV2Playback)
        flags.usesV2Lyrics = defaults.musicFlag("SETU_MUSIC_USES_V2_LYRICS", defaultValue: flags.usesV2Lyrics)
        flags.usesV2History = defaults.musicFlag("SETU_MUSIC_USES_V2_HISTORY", defaultValue: flags.usesV2History)
        flags.usesV2Home = defaults.musicFlag("SETU_MUSIC_USES_V2_HOME", defaultValue: flags.usesV2Home)
        flags.usesV2PlaylistDetail = defaults.musicFlag("SETU_MUSIC_USES_V2_PLAYLIST_DETAIL", defaultValue: flags.usesV2PlaylistDetail)
        flags.artistDetailEnabled = defaults.musicFlag("SETU_MUSIC_ARTIST_DETAIL_ENABLED", defaultValue: flags.artistDetailEnabled)
        flags.albumDetailEnabled = defaults.musicFlag("SETU_MUSIC_ALBUM_DETAIL_ENABLED", defaultValue: flags.albumDetailEnabled)
        flags.rankingsEnabled = defaults.musicFlag("SETU_MUSIC_RANKINGS_ENABLED", defaultValue: flags.rankingsEnabled)
        flags.newReleasesEnabled = defaults.musicFlag("SETU_MUSIC_NEW_RELEASES_ENABLED", defaultValue: flags.newReleasesEnabled)
        flags.radioFMEnabled = defaults.musicFlag("SETU_MUSIC_RADIO_FM_ENABLED", defaultValue: flags.radioFMEnabled)
        flags.likedTracksEnabled = defaults.musicFlag("SETU_MUSIC_LIKED_TRACKS_ENABLED", defaultValue: flags.likedTracksEnabled)
        flags.favoritePlaylistsEnabled = defaults.musicFlag("SETU_MUSIC_FAVORITE_PLAYLISTS_ENABLED", defaultValue: flags.favoritePlaylistsEnabled)
        flags.wordByWordLyricsEnabled = defaults.musicFlag("SETU_MUSIC_WORD_BY_WORD_LYRICS_ENABLED", defaultValue: flags.wordByWordLyricsEnabled)
        flags.airPlayPickerEnabled = defaults.musicFlag("SETU_MUSIC_AIRPLAY_PICKER_ENABLED", defaultValue: flags.airPlayPickerEnabled)
        return flags
    }
    #endif
}

#if DEBUG
private extension UserDefaults {
    func musicFlag(_ key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else { return defaultValue }
        if let value = string(forKey: key)?.lowercased() {
            return ["1", "true", "yes", "on"].contains(value)
        }
        return bool(forKey: key)
    }
}
#endif
