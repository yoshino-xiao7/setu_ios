# Music development configuration

Debug builds start with the implemented Home, Search, Playback, Lyrics, History, provider playlist detail, FM, likes, saved playlists, word lyrics and AirPlay picker enabled. No devicectl launch arguments are required. Existing `SETU_MUSIC_*` UserDefaults/launch arguments still override each flag, including an explicit false. Release builds and a plain `MusicFeatureFlags()` retain disabled defaults.

The music dashboard combines a compact FM card and four library shortcuts with the existing horizontal listening-history artwork, five daily tracks and horizontal playlist artwork. Daily and recommended-list headers provide the full-page destinations. Disabled or permanently degraded discovery placeholders do not produce empty cards. Genuine eligible failures retain a retry notice; stale items remain visible.

The dashboard now loads four independent cached sources: the v2 Home feed, canonical history (with existing missing-metadata hydration), retained legacy daily recommendations and retained legacy hot search. If Home has no usable recommended playlists, it makes one normal cached request to the supported v2 recommended-playlists endpoint; an authentication error or owner change prevents this follow-up. This deliberately replaces the old one-request dashboard composition. The v2 Home resource itself remains a single aggregate request, and no unsupported v2 daily/hot/ranking endpoint is substituted. Warm re-entry reuses resource caches. Saved-playlist server actions use the frozen `savedPlaylists` value.

Use a backend with matching v2 gates and exact admission configuration. The backend `music-development` profile supports the current `ios:1.1:5` build. For a different build, configure its exact observed/admitted identity. This is application routing configuration, not an authentication bypass or a server deployment.

This delivery is implementation/build verification only. Device installation, UI automation, physical audio, AirPlay acceptance, production cutover and post-release deletion were not performed.
