# 音乐功能优化完成度审计

更新时间：2026-09-02

对应计划：`docs/music-feature-implementation-plan.md`

## 自动化验证

- `swift test`：51 个 XCTest 通过。
- `xcodebuild -quiet -project SetuIOSApp.xcodeproj -scheme SetuIOSApp -destination 'generic/platform=iOS' -derivedDataPath .derivedData-ios CODE_SIGNING_ALLOWED=NO build`：通过。
- `git diff --check`：通过。

## P0 封面显示 Bug 修复

| 要求 | 当前证据 | 状态 |
| --- | --- | --- |
| HTTP 封面升级 HTTPS | `MusicModels.swift` 的 `secureURLString(_:)`，`MusicSong.coverURLString`、`PlaylistSong.coverUrl`、`MusicHistoryRecord.coverUrl` 均走该方法；`MusicClientTests` 覆盖 HTTP 升级 | 已完成 |
| 网易云封面尺寸参数 | `secureURLString(_:artworkSize:)` 支持 `.thumbnail` / `.lockScreen`；单测覆盖追加与替换 `param` | 已完成 |
| 自建封面加载器 | `MusicArtworkView.swift` 使用 `RemoteArtworkLoader`、放大 `URLCache`、重试一次、点击重试、淡入过渡 | 已完成 |
| 锁屏封面 | `MusicPlaybackController.loadNowPlayingArtwork(for:)` 复用 `RemoteArtworkLoader` 并设置 `MPMediaItemPropertyArtwork` | 需真机确认 |

## P1 播放页体验升级

| 要求 | 当前证据 | 状态 |
| --- | --- | --- |
| 沉浸式 Now Playing | `MusicMiniPlayerBar.swift` 的 `MusicNowPlayingDetailView` 使用大封面、封面主色背景、五控件、进度条、次操作行 | 已完成 |
| Reduce Motion 降级 | `@Environment(\.accessibilityReduceMotion)` 控制封面弹簧动画 | 已完成 |
| 同步滚动歌词 | `LyricParser.swift`、`LyricScrollView.swift`；`LyricParserTests` 覆盖乱序、多时间戳、翻译、无时间戳 fallback、active index | 已完成 |
| 歌词点击 seek / 字号 / 常亮 | `LyricScrollView` 的 `onSeek`、`LyricFontScale`、`keepsScreenAwakeForLyrics` | 需真机确认常亮恢复 |
| Mini Bar 强化 | mini bar 支持下一首、左右滑切歌、上滑展开；播放页下滑收起 | 已完成 |

## P2 播放健壮性与工具

| 要求 | 当前证据 | 状态 |
| --- | --- | --- |
| 音质偏好与回退 | 音乐首页和展开播放器提供标准、较高、极高、无损、Hi-Res；默认保留 `exhigh`，偏好持久化。切歌/自动下一首/恢复播放优先请求所选音质，不可用时回退标准并提示；手动切换失败保留旧音质与播放 | 已完成 |
| 自动连播补历史 | `MusicPlaybackController.advance(by:isAuto:)` 成功自动切歌后调用 `recordPlaybackHistory`；`RootAppView` 接入 `MusicClient.addHistory(_:)` | 需真机/集成环境确认后端记录 |
| 睡眠定时 | `MusicSleepTimerOption` 支持 15/30/60 分钟与播完本曲；`fadeOutAndPauseForSleepTimer()` 渐弱暂停 | 需真机确认后台与熄屏行为 |
| 队列管理 | `MusicQueueManagerSheet` 支持拖拽排序、滑动移除、清空待播、下一首播放 | 已完成 |

## P3 首页与搜索打磨

| 要求 | 当前证据 | 状态 |
| --- | --- | --- |
| 首页信息架构 | `MusicHomeView` 首屏顺序为搜索入口、最近播放横滑、我的歌单网格、热门搜索标签流 | 已完成 |
| 搜索分段 | `MusicSearchSegment` 提供歌曲/歌手/专辑分段；歌曲分页加载更多保留 | 已完成 |
| 搜索历史单条删除 | `removeSearchHistory(_:)` 与删除按钮保留 | 已完成 |
| 歌单批量操作 | `MusicPlaylistDetailView` 多选模式、底部选中计数操作条、批量移除、`BulkAddPlaylistSongsSheet` 批量加入其它歌单 | 已完成 |
| 缓存标识 | 计划标注为可选；当前下载走签名外部 URL，不建立本地离线文件库，因此不显示本地缓存标识 | 不做 |

## 剩余验收

### 2026-09-02 音质选择补充

- 菜单标为「优先音质」，服务端返回其他档位时提示实际返回值，不保证每首歌提供所有档位。
- 手动切换先验证新音源可播放，再替换播放器，保留队列、进度和播放/暂停状态；失败以及切歌/停止后的迟到响应不替换旧播放。
- `swift test`：120 项通过，新增覆盖五档请求参数、偏好恢复、本地音频切换、不可播放音源、接口失败及迟到响应。
- iPhone SE 两项定向 UI 用例通过（五档菜单、页面间偏好保留、失败提示、暂停状态、最大字号入口）。截图复查后调整了最大字号播放器顶部布局；复测按用户要求中止，后续只做真机运行，不再启动本机模拟器。
- 包含最终布局修正的 Debug 真机版本 1.1 (4) 构建和签名验证通过，已安装到已连接的 iPhone 17。
- 自动化音频验证使用本地静音 WAV；线上各档音源、耳听音质、后台与锁屏连续播放仍需真机验收。

真机验收项目记录在 `docs/music-manual-verification-checklist.md`。完成这些硬件/后台相关验证后，音乐优化目标可以关闭。
