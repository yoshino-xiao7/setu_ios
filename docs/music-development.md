# Music development configuration

Debug builds start with the implemented Home, Search, Playback, Lyrics, History, provider playlist detail, FM, likes, saved playlists, word lyrics and AirPlay picker enabled. No devicectl launch arguments are required. Existing `SETU_MUSIC_*` UserDefaults/launch arguments still override each flag, including an explicit false. Release builds and a plain `MusicFeatureFlags()` retain disabled defaults.

The music dashboard combines a compact FM card and four library shortcuts with the existing horizontal listening-history artwork, five daily tracks and horizontal playlist artwork. Daily and recommended-list headers provide the full-page destinations. Disabled or permanently degraded discovery placeholders do not produce empty cards. Genuine eligible failures retain a retry notice; stale items remain visible.

The dashboard now loads four independent cached sources: the v2 Home feed, canonical history (with existing missing-metadata hydration), retained legacy daily recommendations and retained legacy hot search. If Home has no usable recommended playlists, it makes one normal cached request to the supported v2 recommended-playlists endpoint; an authentication error or owner change prevents this follow-up. This deliberately replaces the old one-request dashboard composition. The v2 Home resource itself remains a single aggregate request, and no unsupported v2 daily/hot/ranking endpoint is substituted. Warm re-entry reuses resource caches. Saved-playlist server actions use the frozen `savedPlaylists` value.

Use a backend with matching v2 gates and exact admission configuration. The backend `music-development` profile supports the current `ios:1.1:5` build. For a different build, configure its exact observed/admitted identity. This is application routing configuration, not an authentication bypass or a server deployment.

This delivery is implementation/build verification only. Device installation, UI automation, physical audio, AirPlay acceptance, production cutover and post-release deletion were not performed.


## 收藏与播放页修复（2026-09-06）

- 喜欢歌曲分页按正式 trackId 批量补全缺失元数据，保留服务端成员顺序与未解析条目；缓存和会话隔离沿用 MusicRepository。历史时间按设备时区显示今天、昨天或具体日期。
- 推荐歌单改为双列封面网格（辅助字号单列），喜欢页增加收藏概览和当前已加载歌曲播放入口；歌单详情可提前显示缓存的推荐封面与标题。
- 播放队列接入完整播放页。喜欢、系统隔空播放和更多操作并列在底部。
- 收藏到本地歌单向现有 POST 接口发送正式 trackId，由服务端解码；旧 songId 调用保持兼容。新写入完成后重新读取歌单，不伪造旧数字 ID。
- 发布顺序：先部署对应后端兼容修复，再安装客户端。后端未发布时不能宣称推荐封面或正式歌曲收藏已经在线修复。
