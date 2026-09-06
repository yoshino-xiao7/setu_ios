# Music development configuration

Debug builds start with the implemented Home, Search, Playback, Lyrics, History, provider playlist detail, FM, likes, saved playlists, word lyrics and AirPlay picker enabled. No devicectl launch arguments are required. Existing `SETU_MUSIC_*` UserDefaults/launch arguments still override each flag, including an explicit false. Release builds and a plain `MusicFeatureFlags()` retain disabled defaults.

The local Home shortcut cards provide History, owned playlists, likes, saved playlists, FM, daily recommendations and recommended playlists independently of the server feed. Home remains a single aggregate request: shortcut destinations load data only on navigation. Saved-playlist server actions use the frozen `savedPlaylists` value. Existing daily recommendations and owned-playlist paths remain legacy where no successful replacement exists.

Use a backend with matching v2 gates and exact admission configuration. The backend `music-development` profile supports the current `ios:1.1:5` build. For a different build, configure its exact observed/admitted identity. This is application routing configuration, not an authentication bypass or a server deployment.

This delivery is implementation/build verification only. Device installation, UI automation, physical audio, AirPlay acceptance, production cutover and post-release deletion were not performed.
