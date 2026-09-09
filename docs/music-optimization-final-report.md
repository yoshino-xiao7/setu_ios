# Music Optimization Final Report

日期：2026-09-02–2026-09-03。范围：完成已确定的 Phase 1–4 后，只执行 Phase 5 架构整理与性能收尾。

执行结论：代码、构建、规定全量回归及自检已完成。完整套件仅保留原 3 项 UI 基线失败；补充的 430pt 检查两次在 XCTest 截图阶段超时，尚不能宣称所有尺寸验收完成。

## 初始问题

音乐页面数据随 View 生命周期反复加载；切歌重复解析地址、创建播放器并等待历史写入；搜索缺少 debounce、会话与可靠分页；封面重复解码；歌词在重绘时解析；多个 Mini Player 与歌单行阴影增加渲染工作。

本轮重新阅读原方案与四个阶段记录，以 Phase 3 最终源码为基线。原行号未作为修改依据。工作区此前已有未提交修改，Phase 5 review 使用 `/tmp/setu-phase5-start` 快照区分本轮变更，没有提交、推送或覆盖前序阶段工作。

## 最终架构

- 页面：`View → MusicStore → MusicRepository → MusicClient → APIClient`。Store 保持 Resource/SWR 与用户生命周期；Repository 负责内存缓存、TTL、共享请求和精确失效。
- 播放器：`View → MusicPlaybackController`；控制器协调 `PlaybackQueue → PlaybackURLResolver → NextItemPreparer → AVPlayer`。这表示协作关系，不是每次点击必经的串行等待链。实际播放只使用一个 AVPlayer。
- 图片：`View → SetuRemoteImageLoader → Memory → URLCache → Network`。图片、API 数据、播放 URL 保持独立缓存职责。
- 搜索：`MusicSearchView → MusicStore.searchSession / MusicSearchSession → PagingController → MusicRepository`。
- Mini Player：Root 的 TabView overlay 只有一个实际条目，GeometryReader 仅在有播放器时存在。页面原有 inset 位置只保留透明空间，保证各页面底部按钮与 Tab Bar 的布局顺序；透明占位不观察播放进度、不创建封面任务。
- 歌单选择：三个薄入口适配到 `PlaylistSelectionSheet`，共用 Store playlists Resource、写入与错误处理；摘要、标题和单首/批量外观保留。
- 歌词：请求完成后，后台生成 `[LyricLine]` 并写入页面状态；body 使用解析结果，当前行用二分查找。歌曲 ID、Task cancellation 阻止旧响应覆盖新歌曲。

## Phase 1 最终效果

首页、歌单及历史的状态由 Root 持有的 MusicStore 保存。TTL 内返回首页不重复发起六个请求；过期保留旧内容静默刷新。歌单写成功后本地更新并精确失效，用户切换同步清理、替换 Repository 并拒绝旧响应。

本轮没有改变 Store/Resource 的业务行为。Repository 淘汰只影响可复用的 API 条目，不主动清空仍在 Store 中展示的 Resource。

## Phase 2 最终效果

控制器保留单 AVPlayer、共享 URL resolver、只准备下一首、随机目标一致性、过期回退和有界恢复。历史写入不阻塞切歌。普通进度快照节流 15 秒，Sendable snapshot 在 utility task 编码，按用户 revision 校验后写入；pause/seek/queue/后台等关键事件继续即时保存，stop 撤销待写快照。

本轮没有修改 MusicPlaybackController、PlaybackQueue、PlaybackURLResolver 或 NextItemPreparer，也没有调节缓冲、playImmediately 或 seek tolerance。

## Phase 3 最终效果

400ms debounce、取消与 generation、首屏 10 条、视口驱动分页、缓存恢复、预计算行与聚合保持。没有重写 MusicSearchView / MusicSearchSession / PagingController。

首页只移动 Preview，查询入口与搜索面板实现均保持不变。

## Phase 4 最终效果

继续使用同步解码内存命中、ImageIO 后台降采样、图片请求去重和共享主色/Now Playing 图片。64 MiB、200 items、有限尺寸档位及 URLCache 参数均未改变。

## Phase 5 最终效果

### 实施项目与实际收益

| 项目 | 最终行为 | 验证方式 |
| --- | --- | --- |
| Mini Player | 一个实际 View 状态实例，跨 Tab/导航/切歌保持身份；各页面只预留空白 | DEBUG 生命周期计数与 identity，UI 检查布局、队列、Now Playing |
| Lyrics | 每次歌词请求完成解析一次；进度更新不解析，当前行 O(log n) | 解析次数、60 次进度与双向 seek、翻译/空内容测试及歌词 UI |
| MV | MusicMvSheet 加载详情并传清晰度数组；内嵌播放器不再二次请求；独立 MV 入口仍可自行获取一次 | URLProtocol 夹具实际请求计数，切换清晰度/重试不重取 detail |
| 歌单行 | 行卡片保留圆角、边框、背景和间距，关闭单行 shadow | 原歌单 UI 与截图；不把该检查当成 GPU/60fps 测量 |
| 歌单弹窗 | 一个选择/写入流程，读取共享 Resource；批量排除源歌单 | 三种入口 UI、原 Store 精确写入/用户切换测试 |
| Repository | 最多 128 个条目；超限先淘汰 expired，再淘汰较久未访问的条目 | 300 个不同 query 最终保留 128；热数据/TTL/SWR/共享请求/失效 |
| 动画与 Preview | 移除整棵 Tab 树针对 currentTrack.id 的隐式动画；首页 Preview 归位 | diff、构建和播放器 UI |

Repository 读取不延长 TTL；没有容量压力时保留过期条目供 SWR 使用，而不是刚过期就丢弃旧 UI。请求 ticket 保留到所有消费者完成，缓存淘汰不会误撤销仍待交付的共享结果；显式 invalidate/reset 仍真正撤销请求。没有合并三种缓存，也没有引入 LRU 框架或生产依赖。

### 未实施项目及原因

- **History → PagingController**：保留现有 Store 实现。历史首屏需要 records/count 两个资源的共同 SWR 时间，写入还会前插、去重、协调服务端 offset 与 historyRevision。套用 page 编号状态机需要新增适配/双状态，不能明显减少代码，当前生命周期问题已解决。
- **APIClient 单次 decode**：未修改。注入计数 decoder 实测 raw search、URL、playlists 各 2 次 decode 尝试，标准 envelope 为 1 次。两次顶层尝试不等于所有歌曲字段完整解码两遍；通用 raw/envelope 自动兼容覆盖全项目，没有足够 CPU profiling 证据支持本轮切换响应策略。
- **AuthSigner 内存缓存**：未实施，重复 Keychain 读取仍存在。请求级探针实测每个已持有 secret 的 signed request 读取 2 次。新增缓存需要明确多 signer/Keychain 写入的一致性与清理契约；当前工作区还缺少 AGENTS.md 指定的 workspace auth-contract/system-context/frontend-backend-contract 文档。按本轮允许公共基础设施风险大于收益时不实施的要求，保留 Keychain 实时读取与既有清理语义。
- **MusicSong 领域模型重写**：未实施。Search Row 已预计算；History/PlaylistSong 和 Queue/Mini Player 的 MusicPlaybackTrack 已使用存储的展示字段。首页数量有限且不再受多个进度观察者影响，没有证据支持重写双字段 decoder。
- **Snapshot / resolveTrackURL**：Phase 2 已解决运行时问题。Root 注入 resolver 对象；可选 closure 只作为兼容测试入口保留，当前没有 Root→closure→player 引用环。没有为了删 API 重做测试依赖。

### 并发与生命周期自检

- MainActor 保留 UI/Store 所有权；Repository 为 actor，网络仍使用原异步客户端。歌词后台任务只捕获 Sendable 响应。
- 搜索消费者取消不会伤害其他共享消费者；容量淘汰与 invalidation 分别处理。
- 旧用户响应、旧歌曲歌词回写与取消检查保留；没有存储或输出凭据。
- 生命周期诊断只在 DEBUG 编译，只有数量与随机身份，不含账户、歌曲、URL 或凭据。
- 未新增强制 unwrap、第三方依赖、公共 API 破坏或播放器/图片参数改动。

## Phase 5 修改文件

以下清单以本轮开始快照为界，前序阶段文件不计入本轮修改。共 21 个文件；其中 20 个代码、测试及工程文件在最终构建后保持冻结。

| 文件 | 目的 |
| --- | --- |
| [`SetuIOSApp.xcodeproj/project.pbxproj`](../SetuIOSApp.xcodeproj/project.pbxproj) | XcodeGen 注册新增组件、探针与测试文件 |
| [`Sources/SetuIOSApp/DesignSystem/Components/SetuCard.swift`](../Sources/SetuIOSApp/DesignSystem/Components/SetuCard.swift) | 增加默认开启的阴影开关，仅歌单行关闭 |
| [`Sources/SetuIOSApp/DesignSystem/Preview/SetuFeaturePreviewSupport.swift`](../Sources/SetuIOSApp/DesignSystem/Preview/SetuFeaturePreviewSupport.swift) | 仅 DEBUG 的 MV 计数与 opt-in 本地歌词音频夹具 |
| [`Sources/SetuIOSApp/Features/AppShell/MusicMiniPlayerBar.swift`](../Sources/SetuIOSApp/Features/AppShell/MusicMiniPlayerBar.swift) | 缓存解析歌词、接入单实例诊断及统一收藏弹窗 |
| [`Sources/SetuIOSApp/Features/AppShell/RootAppView.swift`](../Sources/SetuIOSApp/Features/AppShell/RootAppView.swift) | 单实例 overlay、原位置留白、收窄几何测量、移除切歌全局动画 |
| [`Sources/SetuIOSApp/Features/Music/AddSongToPlaylistSheet.swift`](../Sources/SetuIOSApp/Features/Music/AddSongToPlaylistSheet.swift) | 保留单首摘要与回调，适配共享组件 |
| [`Sources/SetuIOSApp/Features/Music/LyricParser.swift`](../Sources/SetuIOSApp/Features/Music/LyricParser.swift) | 二分定位 active line 与 DEBUG 解析计数 |
| [`Sources/SetuIOSApp/Features/Music/LyricScrollView.swift`](../Sources/SetuIOSApp/Features/Music/LyricScrollView.swift) | 每次 body 只求一次 active index |
| [`Sources/SetuIOSApp/Features/Music/MusicHomeView.swift`](../Sources/SetuIOSApp/Features/Music/MusicHomeView.swift) | 只接回属于首页的 Preview |
| [`Sources/SetuIOSApp/Features/Music/MusicMvSheet.swift`](../Sources/SetuIOSApp/Features/Music/MusicMvSheet.swift) | 父层独占 detail 请求并传递清晰度 |
| [`Sources/SetuIOSApp/Features/Music/MusicPerformanceProbe.swift`](../Sources/SetuIOSApp/Features/Music/MusicPerformanceProbe.swift) | 仅 DEBUG 的线程安全计数与 Mini Player 生命周期诊断 |
| [`Sources/SetuIOSApp/Features/Music/MusicPlaylistDetailView.swift`](../Sources/SetuIOSApp/Features/Music/MusicPlaylistDetailView.swift) | 关闭歌曲行独立阴影，适配批量弹窗 |
| [`Sources/SetuIOSApp/Features/Music/MvPlaybackView.swift`](../Sources/SetuIOSApp/Features/Music/MvPlaybackView.swift) | 接受父级清晰度，独立入口仍可自行加载 |
| [`Sources/SetuIOSApp/Features/Music/PlaylistSelectionSheet.swift`](../Sources/SetuIOSApp/Features/Music/PlaylistSelectionSheet.swift) | 统一列表 Resource、选择、写入、错误与去重提交 |
| [`Sources/SetuIOSCore/Core/Music/MusicRepository.swift`](../Sources/SetuIOSCore/Core/Music/MusicRepository.swift) | 128 条容量与过期优先淘汰，区分共享响应 ticket 和缓存条目 |
| [`Tests/SetuIOSAppTests/AppleAuthClientTests.swift`](../Tests/SetuIOSAppTests/AppleAuthClientTests.swift) | 等待异步请求探针完成，保持原认证断言 |
| [`Tests/SetuIOSAppTests/LyricParserTests.swift`](../Tests/SetuIOSAppTests/LyricParserTests.swift) | 解析计数、60 次时间变化、seek、翻译和边界语义 |
| [`Tests/SetuIOSAppTests/MusicNetworkAuditTests.swift`](../Tests/SetuIOSAppTests/MusicNetworkAuditTests.swift) | 测量既有 API decode 尝试和 Keychain 读取 |
| [`Tests/SetuIOSAppTests/MusicRepositoryCapacityTests.swift`](../Tests/SetuIOSAppTests/MusicRepositoryCapacityTests.swift) | 容量、热数据、TTL、SWR、共享请求与失效测试 |
| [`Tests/SetuIOSAppUITests/MusicArchitectureUITests.swift`](../Tests/SetuIOSAppUITests/MusicArchitectureUITests.swift) | 单实例/导航/歌词/MV/三种歌单弹窗 UI 测试 |
| [`docs/music-optimization-final-report.md`](../docs/music-optimization-final-report.md) | 本轮决策、证据、验收与真机检查记录 |

## 最终测试结果

修改前基线：App Build PASS；完整 SwiftPM 215/215；完整 iOS Unit 221/221，包含 Music 与 Phase 1 Cache、Phase 2 Playback、Phase 3 Search、Phase 4 Image。证据：`/tmp/setu-phase5-baseline-swift.log`、`/tmp/setu-phase5-baseline-ios.log`、`/tmp/setu-phase5-baseline-ios.xcresult`。

| 验证 | 当前结果 | 最终证据 |
| --- | --- | --- |
| Debug build / build-for-testing | PASS | `/tmp/setu-phase5-final-build.log` |
| 完整 SwiftPM | 223 通过，0 失败 | `/tmp/setu-phase5-final-swift.log` |
| 完整 iOS Unit | 229 通过，0 失败 | `/tmp/setu-phase5-final-all-ios.xcresult` |
| Phase 1 Repository / Store | 14 通过 | 同上 |
| Phase 2 Controller / Queue / URL / Quality | 36 通过 | 同上 |
| Phase 3 Session / Search Repository / Row Layout | 35 通过，通用 PagingController 另 11 通过 | 同上 |
| Phase 4 图片缓存 | 16 通过 | 同上 |
| Phase 5 容量 / 网络计数 / Lyrics | 4 / 1 / 9 通过（歌词包含既有 6 项） | 同上 |
| Phase 5 新 UI | 5 通过 | 同上 |
| 完整 UI | 43 通过，3 个原有失败，0 跳过；无新增失败 | 同上 |
| 375pt Mini Player | 最终普通/AX5 原测试通过；首次失败及初始化停滞记录保留 | `/tmp/setu-phase5-375-final.xcresult` |
| 430pt Mini Player | 两次截图超时；已执行布局断言通过，完整尺寸验收无法自动验证 | `/tmp/setu-phase5-430.xcresult`、`/tmp/setu-phase5-430-final.xcresult` |
| 最终 diff / 源码冻结核验 | PASS：302 文件核验，计划内 21 个变化；20 个冻结文件 hash 一致 | `/tmp/setu-phase5-final-source-hashes.json` |

最终 UI 在 iPhone 17 Pro / iOS 27 上串行运行，启用既有 `SETU_RUN_LIVE_PUBLIC_UI_TESTS=1`，实际公开示例加载通过；未使用 skip、测试重试或放宽断言来改变完整套件结果。Build 使用 Xcode-beta 的 `build build-for-testing`，随后对同一冻结的 xctestrun 执行 `test-without-building -parallel-testing-enabled NO`。

源码自检确认以下文件与 Phase 5 开始快照字节一致：MusicStore、MusicSearchSession、MusicSearchView、PagingController、MusicPlaybackController、PlaybackQueue、PlaybackURLResolver、NextItemPreparer、SetuRemoteImageLoader、MusicModels、APIClient、AuthSigner。

开发中检出并修正的问题也保留证据：

- 初次单实例布局把空白 inset 放在 NavigationStack 外侧，未正确避让 AI/图片页底部操作；现已恢复原页面层级的留白位置，单实例 overlay 保留。最终版本还把 GeometryReader 收窄到有播放器时的 overlay；无播放器时没有透明 inset 或几何回写，避免键盘布局变化触发额外 Root 状态更新。
- 新 UI 用例最初在队列关闭动画结束前点击 Mini Player；改为明确断言队列已消失后再操作，不使用固定 sleep。原先怀疑搜索面板的修改未证明有效，已撤回。歌词 UI 使用播放页既有的准确无障碍标签与歌词容器，避免误点被 sheet 覆盖的底层封面。
- 中途完整 UI 观察到一次搜索输入丢失末字；搜索生产代码与测试保持原样。Phase 3 原始产物 5 次复测通过；收窄 Root 几何测量后的冻结版本连续 5 次及最终完整套件均通过（6/6）。初次结果仍保存在 `/tmp/setu-phase5-all-ios.log`；复测为 `/tmp/setu-phase5-search-baseline.xcresult`、`/tmp/setu-phase5-search-final.xcresult`。
- `AppleAuthClientTests` 在并发构建负载下暴露原有异步探针竞态。与开始快照字节对照一致，本轮仅增加 XCTestExpectation 等待 capture 完成；原断言及认证生产代码不变，没有固定 sleep、跳过或放宽断言。
- 歌词换曲成功路径使用 opt-in 本地 180 秒静音 WAV，经真实 URL resolver / AVPlayer 切歌；原预览 URL 缺失会触发连续错误跳曲，不适合断言“只切换一首”。既有质量失败夹具与三个 UI 基线场景不变，解析计数仍来自实际 parser 调用。

### 辅助尺寸验证与失败记录

- 375pt 第一次：点击 AI Tab 后仍停留首页，未找到生成按钮；同一设备 Phase 3 原始产物的完整普通/AX5 检查通过。一次后续尝试停在 XCTest 初始化，已终止并保留日志。最终相同 Phase 5 产物与原测试全部通过，未改变断言或添加 sleep。最初延迟明显，同时运行过两台模拟器；未将资源争用推断写成已证实根因。
- 430pt 第一次：普通字号五个 Tab 全部通过；AX5 的首页、AI 页及历史页布局断言通过，随后第 269 行 `app.screenshot()` 超时。复核时通过此前失败位置并继续到音乐页，随后第 261 行 `app.screenshot()` 再次超时，未完成 AX5 广场检查。两次已执行的布局断言均通过，但不能将整个用例记为 PASS。证据：`/tmp/setu-phase5-430.xcresult`、`/tmp/setu-phase5-430-final.xcresult`。桌面控制工具亦无法解析 Simulator 应用，因此未补上直接界面验收。
- 主模拟器完整套件和辅助尺寸运行分别报告；没有用反复重跑的结果覆盖原始失败记录。

## 性能计数与测量边界

| 指标 | 实际结果 | 边界 |
| --- | --- | --- |
| Mini Player 实例 | DEBUG 生命周期探针断言 `instances=1`，跨 Tab/push/pop/切歌 identity 不变 | 测量存活状态实例，不把 SwiftUI 临时 View 值计入实例数 |
| Lyrics parse | 60 次时间更新和前后 seek：1 次；切到新歌增加 1 次 | 单测注入 60 个时间点；真实播放器 UI 验证拖动/封面切换/换歌，不等于真机一分钟 Time Profiler |
| MV detail | 打开、切换清晰度、重试 URL 后仍为 1 次 | URLProtocol 实际请求计数；真实 CDN 与全屏视频播放仍需设备验收 |
| API Cache | 300 个不同 query 后 128 条；reset 后 0 条 | entry 数上限，不是整个 App 或 Store 的内存字节预算 |
| Keychain | 每个已持有 secret 的 signed request 2 次读取 | 本轮只测量，未加缓存 |
| API decode | raw search/URL/playlists 2 次顶层 decode 尝试；envelope 1 次 | 未测得所有字段解码两遍，未修改公共解析策略 |
| Search cache A→B→A | 最终 SwiftPM 约 0.283ms；最终 iOS Unit 约 0.791ms | 单次 fixture 会话恢复耗时，不能代替真实页面首帧 ≤100ms |

没有运行真机 Instruments，也没有将模拟器 fixture 的通过结果描述为 60fps、峰值内存下降或切歌 ≤300ms 的证明。

## 仍无法自动验证的项目

- 430pt 完整普通/AX5 尺寸检查：XCTest 两次截图超时；需在可稳定截图的模拟器或真机补验，当前不记为通过。

- 真机已准备下一首从点击到实际播放 ≤300ms、真实自动连播静音间隙。
- 真实弱网、断网恢复、Bluetooth/耳机断开、后台/锁屏/中断恢复。
- 真机 100 首真实封面长列表 60fps、Core Animation 离屏渲染与 Time Profiler 主线程占用。
- 实际峰值内存；128 是 API entry 数上限，不是字节上限，Store 仍会按访问过的歌单/推荐 ID 保留 Resource，图片/播放资源也另占内存。
- 音乐 CDN Cache-Control、跨进程 URLCache 磁盘持久性、真实图片请求数量。
- 真实端到端首页 ≤100ms 首帧。单测的缓存恢复耗时与 fixture UI 不等同于这一设备指标。

歌词缓存当前随 Now Playing 的本次呈现存活。关闭再打开可重新请求、解析；没有声称一首歌曲跨所有呈现永久只解析一次。

## 已知基线问题

Phase 5 最终完整结果为 275 项：272 通过、3 失败、0 跳过（iOS Unit 229/229；UI 43/46）。三项失败与 Phase 3 相同，原测试文件和断言均未修改：

1. `RandomImageConsumptionUITests.testFirstHighResolutionOpenRequiresExplicitPointsConfirmation`：第 22 行旧高清确认文案与当前文案不同（期待“同一张图片重复查看不会再次扣分”，当前为“已解锁图片在本次浏览中再次查看不扣分”）。
2. `UXFlowUITests.testTwoAssetsApplyAndReturnWithNames`：第 113/215 行：AI 资产入口未进入选择页，找不到“使用 电影感光影”。
3. `UXFlowUITests.testUnauthorizedMainRoutesReturnAfterLogin`：第 284/113/286 行：未授权音乐入口找不到“重新登录”。

不修改上述断言或无关业务来获得全绿。对照证据：`/tmp/setu-phase3-all-ios.xcresult`、`/tmp/setu-phase4-baseline-ui.xcresult`。

## 最终验收表

| 项目 | 结果 |
| --- | --- |
| Mini Player 单实例 | PASS：生命周期数量与跨 Tab/导航/切歌 identity |
| 歌词每次加载只解析一次 | PASS：时间变化不解析，换歌重新解析 |
| Active lyric 查找 | PASS：二分查找，保留边界与重复时间戳语义 |
| 播放快照后台编码 | Phase 2 已解决，本轮回归 PASS |
| MV Detail 单请求 | PASS：打开、切清晰度、重试 URL 均为 1 次 |
| 长歌单 Row 阴影优化 | PASS：关闭单行 shadow；GPU/60fps 仍需真机 |
| Playlist Sheet 去重 | PASS：三入口使用同一组件与 Store |
| History PagingController | 保留原实现，迁移收益不足 |
| APIClient 单次 decode | 未实施：公共兼容风险大于现有证据支持的收益 |
| AuthSigner 内存缓存 | 未实施：需要一致性与清理契约，按请求实时读取保留 |
| MusicRepository 容量 | PASS：默认 128 条，TTL/SWR/去重/失效回归通过 |
| resolveTrackURL 引用环 | PASS：Root 已用 Phase 2 resolver；旧 closure 仅保留兼容测试入口 |
| Root currentTrack 全局动画 | PASS：已移除 |
| Phase 1 / Phase 2 / Phase 3 / Phase 4 | 自动回归均 PASS |
| 完整 UI 新增失败 | 0；原 3 项基线失败保留 |
| 补充尺寸验收 | 375pt PASS；430pt 无法完整自动验证（两次 XCTest 截图超时） |

## 后续真机验收 Checklist

1. 用真实账户登录，首页→搜索→返回，抓包确认 TTL 内首页 0 次重复请求；TTL 外保留内容后台更新。切换两个账户，确认歌单/历史/搜索不串用户。
2. 我的歌单→详情→返回→再进；创建/删除歌单、单首/批量加歌、移歌、历史清空，确认不整页 Loading。
3. 播放 A 后等 B 准备完成，使用现有 TrackTransition / PreparedItemHit / TrackPlaying signpost 测量下一首；同时确认 B 无新 URL 请求。切换随机/单曲、编辑队列、改变音质后重复。
4. 真机连续播放一分钟并打开歌词；Time Profiler 确认进度更新不调用 parse，拖动歌词、前后 seek、暂停恢复、换曲后验证高亮与自动滚动。
5. 五个 Tab 与多层 push/pop、键盘显示/收起、普通/辅助字号、375/430pt、横竖屏检查 Mini Player、底部动作、Tab Bar 和 Home Indicator；打开队列、Now Playing、分享和全屏 MV。
6. 打开一个 MV，抓包确认 detail 最多一次，清晰度切换与 URL 重试只请求 URL；测试无 MV、详情失败、URL 失败。
7. 用 100 首真实封面搜索结果/歌单滚动，记录 Core Animation 帧率、主线程耗时、Allocations 峰值；不要依据模拟器 fixture 调整缓冲或图片预算。
8. 封面首页→歌单→返回，再冷启动应用，分别验证解码内存命中和 CDN/URLCache 行为。
9. Wi-Fi/蜂窝弱网/断网、锁屏/后台、来电中断、Bluetooth 切换后检查播放、暂停与恢复；记录设备、系统、网络和失败步骤。

## Final Device Validation

验证日期：2026-09-03（Asia/Shanghai）。本节是架构冻结后的验证记录，不是新的优化 Phase。生产代码、测试、工程和参数均未修改；此前章节的结果保留为历史记录，以本节说明新增证据和未完成项。**本轮不能签署全量验收通过。**

### Device

| 项目 | 实际环境 |
| --- | --- |
| 真机 | iPhone 17，型号标识 iPhone18,3 |
| 系统 | iOS 27.0，24A5430a |
| 显示 | 402 × 874pt；1206 × 2622px。此真机不是 430pt 设备 |
| 网络 | 用户确认与 Mac 同一 Wi-Fi，同时 USB 连接；未施加弱网限制 |
| 音频 | 用户确认声音来自连接 iPhone 的蓝牙耳机；耳机型号未提供 |
| App | 雪涼云，Debug 1.1 (4)，`icu.yukiryou.setuios` |
| 工具 | Xcode-beta / Instruments 27A5194q；iPhone Mirroring |
| 430pt 环境 | Setu QA 430，iPhone 16 Plus 模拟器，iOS 27.0 / 24A5355p，430 × 932pt |

开始时保存 273 个源码、测试和工程文件的 SHA-256，后续核对无变化。当前版本包含冻结前的真机音频 session 修复；本次没有继续修播放器。没有改断言、添加 skip 或用固定 sleep 掩盖测试竞态。真机切歌之间的等待用于满足“稳定播放至少 5 秒”的验收前提。

### Playback

| 项目 | 实测与结论 |
| --- | --- |
| 首次起播 | 执行一次冷启动，真实搜索 `test` 后播放 TEST ME；随后依次播放 Test Drive、test me、两首 TEST。用户确认蓝牙有声。未逐首采集点击到听音的时间，也未证明五首此前从未播放，不能记为“五首首次起播延迟 PASS” |
| 主观切歌体验 | 用户原话：“有轻微间隙，但是比之前明显要好，几乎做到了无缝切歌”。这是这一组播放的定性反馈，不能转换成毫秒数或无缝播放结论 |
| 下一首功能 | 第一组连续执行 10 次下一首，每次间隔至少 6 秒，观察标题变化和进度推进，包括列表循环回到第一首。该组组合 Instruments 录制崩溃，不能提供该组分位数 |
| Prepared next 测量 | 已从三份成功录制取得 **10 个**完整下一首 `TrackTransition`，全部含 `PreparedItemHit`，且以首个 `TrackPlaying` 结束；median **533.299ms**、P90 **4245.354ms**、worst **4383.872ms**，≤300ms 目标 **FAIL**。逐曲 URL 请求数未独立验证 |
| 自动连播 | 受控后台一轮中 TEST / RAY→stresstest 自动连续播放，用户确认“一直有声，没有明显长静音或卡住”，本次功能与主观听感 PASS。没有连续音频录制或对应 URL/历史请求时间线，静音间隙毫秒数及 URL/历史阻塞尚未量化 |
| 快速操作 | 已在真实 10 首队列执行 next→next→next，以及 previous→next→previous，最后标题和进度符合最后一次意图，观察期间未跳回旧歌。仅覆盖当时已播放/缓存队列；未完成快速点击列表 A→B→C |
| 随机 | 尚未完成 ≥20 首列表、连续 20 次 prepared 目标与实际目标逐项比对；不得用普通列表循环代替 |
| 音质 | Hi-Res→标准后，当前歌曲进度继续，下一首正常起播；随后恢复 Hi-Res。旧 prepared 项失效与新质量准备尚无独立运行时证据，功能观察不等于完整缓存失效验收 |
| 弱网与 URL 失效 | 未完成高延迟、低带宽、短暂断网、恢复网络及真实 URL 失效的有界重试测试。当前 devicectl 未提供可用网络模拟子命令，Mac 未安装 Network Link Conditioner；未以修改代码或播放 URL 的方式伪造真机结果 |

第二组原始耗时（同一 iPhone、Wi-Fi、Hi-Res、10 首队列）：

| 序号 | 目标歌曲 | PreparedItemHit | TrackTransition begin → 首个 TrackPlaying |
| --- | --- | --- | --- |
| 1 | stresstest / yax03 | 是 | 127.216ms |
| 2 | test / FiveY | 是 | 116.917ms |
| 3 | Test Drive / John Powell | 是 | 117.859ms |
| 4 | The Test / Madonna、Lola Leon | 是 | 432.115ms |
| 5 | TEST ME / ちゃんみな，列表回绕 | 是 | 3260.730ms |
| 6 | Test Drive / 木伞 Flywood | 是 | 4383.872ms |
| 7 | test me / siick | 是 | 4245.354ms |

这 7 次的 median = **432.115ms**，P90 = **4383.872ms**（nearest-rank），worst = **4383.872ms**。3/7 ≤300ms，4/7 超过 300ms，其中 3/7 超过 3 秒。这是第一个成功录制窗口的子样本，完整十次统计另列如下。

后续追加样本（相同真机、Wi-Fi、Hi-Res；不同录制窗口，不替换上述慢样本）：

| 序号 | 目标歌曲 | 录制 / transition ID | PreparedItemHit | 耗时 |
| --- | --- | --- | --- | --- |
| 8 | test me / siick，恢复 Hi-Res 后的下一首 | next-v3 / `0x8d` | 是 | 2029.763ms |
| 9 | TEST / DDG | controlled / `0x97` | 是 | 510.386ms |
| 10 | TEST / RAY | controlled / `0x98` | 是 | 556.212ms |

**最终合计 n=10：median 533.299ms，P90 4245.354ms（nearest-rank，第 9 个有序样本），worst 4383.872ms；3/10 ≤300ms，7/10 超过 300ms。** 最后两次是在用户重新戴好耳机并同意保持连接后执行。该集合不是随机抽样，也未覆盖 20 首随机队列，不能推广成所有网络/音源的分布。汇总：`/tmp/music-final-combined-next-metrics.json`；追加证据：`/tmp/music-final-device-controlled.trace`、`/tmp/music-final-controlled-events.json`。

测量起点是 App 内 `beginTransition()`，终点是在 MainActor 处理 `timeControlStatus == .playing` 时写出的 signpost，包含该回调的调度时间；不是物理点击时刻，也不是耳机实际出声时刻。重复的 `TrackPlaying` 不重复计样本。一次镜像点击后没有标题变化，也没有对应 transition，未算进有效样本。该记录未包含逐曲 URL 请求计数；源码的 prepared 分支确实直接使用已解析 source，但不能据此声称本轮网络抓包已验证“B 的 URL 请求为 0”。

证据：`/tmp/music-final-device-next-v2.trace`、`/tmp/music-final-next-v2-toc.xml`、`/tmp/music-final-next-v2-signposts.xml`、`/tmp/music-final-next-v2-events.json`、`/tmp/music-final-next-v2-metrics.json`。

### Background

| 项目 | 状态与边界 |
| --- | --- |
| 第一轮后台 | 08:43:40 进入 Home；随后验证被中断，设备断开。trace 实际只录到 08:44:51–08:46:38，共 107.032 秒，结束原因为 `Device disconnected`。不能用用户返回后的墙钟间隔冒充五分钟持续观察 |
| 恢复 App | 重连后进程仍为原 PID 4444，播放页显示歌曲与推进后的进度。这不能证明断连期间持续有声 |
| 第二轮后台 | 09:48:00 再次进入 Home，初始为 test me / siick，Hi-Res，10 首队列。09:56 主屏仍可见，随后返回原进程 PID 4444；09:58 画面为 TEST / YeZippo，1:09 / 2:05，显示暂停。用户确认期间取下过耳机，因此这轮包含音频路由/耳机佩戴状态干扰，不能作为不间断五分钟后台验收，也不记为后台缺陷 |
| 第三轮受控后台 | **本次场景 PASS**。用户确认重新戴好耳机并保持连接，10:11:54 进入 Home，起点 TEST / RAY 约 0:52 / 4:56，Hi-Res，10 首队列；10:17 主屏仍可见，之后返回原 PID 4444，10:18 观察到 stresstest / yax03 3:07 / 5:01、正在播放。用户确认后台期间“有声，没有”明显长静音或卡住。10:20 打开 Queue，仍为同一 10 首搜索队列及对应歌曲，Mini Player 与 Now Playing 一致。prepared item 的内部状态未直接读取，锁屏/route interruption 不在此 PASS 范围 |
| 锁屏 | 用户此前完成锁屏、镜像认证。镜像可用时的物理锁屏不等于已验证锁屏封面、标题、歌手及 play/pause/next/previous 控制；这些项目未完成 |
| Bluetooth | 已确认蓝牙耳机有声；用户取下耳机期间后续观察到 UI 为暂停，未出现本次画面仍显示播放的矛盾。但没有系统 route/interruption 时间线，尚不能确定具体暂停原因；受控连接、断开、恢复、route change 未完整执行 |
| 有线 / USB 音频 | USB 数据连接不等于 USB 音频输出验证，未测 |
| Interruption | 未完成电话、Siri 或其他系统音频中断及按系统语义恢复验证，未据此认定 PASS |

### Search

| 项目 | 结果 |
| --- | --- |
| 真实首屏 | `test` 搜索显示 10/329，歌曲、封面和 Mini Player 可见，无搜索历史覆盖结果的现象；未采集首屏毫秒数 |
| 连续中文输入 | 镜像中文输入未成功注入；系统剪贴板传输反复超时/弹窗，已取消。未完成真实“周→周杰→周杰伦、林俊杰、陈奕迅”输入体验；不将工具输入失败认作产品 debounce 缺陷 |
| 分页 | 原有 430pt UI 测试通过首屏 10/100、继续加载和滚动至第 100 首。后续镜像恢复时，真机滚动到首批末尾，点击现有“加载更多歌曲”后出现第二页真实歌曲，原行保留，未出现整页 Loading；之后播放队列显示 20 首，证实已加载至少两页。继续加载再次被系统剪贴板弹窗/输入不同步干扰，未完成 100 首 |
| 100 rows | 430pt 普通字号截图检查了列表末端 94–100 行，未见明显行内重叠。测试使用 fixture，不能代替真实封面列表的滚动性能 |
| 页面缓存 | fixture 的首页→搜索→返回、搜索会话恢复测试通过；真实手机曾返回已有首页及歌单列表，未看到整页 Loading。未完成要求的多轮“首页→搜索→歌单→历史”人工连续体验或 TTL 内 0 请求计数 |
| 歌单 | 真机点击入口文字能够进入歌单列表，但入口空白区域点击无反应，详见 Issue 1。430pt 歌单详情二次进入测试因此未完成，不能将入口失败推断为 Store 缓存失败 |

### Images

| 项目 | 结果 |
| --- | --- |
| Cache | 真机实际封面能够加载和显示；尚无首帧逐帧记录及相同 key 的下载计数，不能签署“第一帧出现 / 不重复下载” |
| Memory | 未完成真实首页→100 首→多个歌单→Now Playing 的 Allocations / Memory Graph 测量；没有验证 64 MiB 附近行为或 memory warning 后清理与播放状态保留 |
| Repository 容量 | 沿用此前 300 query→128 entries 的单测证据；本次未制造 200–300 个真实服务请求，也未完成真机对应压力观察。容量保持 128，未修改 |

### Layout

375pt 沿用前一阶段已接受的结果，本轮未重跑，不能扩展为每个页面所有字号都通过。430pt 本次不再受原来的 XCTest screenshot 超时阻断，但也不能整体记为 PASS。

| 430pt 项目 | 普通字号 | AX5 / 大辅助字号 |
| --- | --- | --- |
| 音乐首页 | 已目视检查已加载画面，未见明显裁切/重叠；歌单入口点击问题另列 | 已检查可见区域及 Mini Player，不代表所有滚动内容和长标题均完成检查 |
| 搜索 | 首屏、切换/恢复结果和 100 行末端截图已检查 | 未完成真实结果列表的完整目视检查 |
| 歌单详情 | 二次进入用例被入口问题阻断；不能签署通过 | 未完成完整目视检查 |
| Mini Player | 五个 Tab 的原布局测试通过；可见画面位于 Tab Bar 上方 | 同一用例五个 Tab 完成，无 screenshot 超时；已检查音乐页安全区和间距 |
| Now Playing | 已检查，未见明显控制项重叠 | **FAIL：底部模式/上一首、下一首/更多图标重叠，3/3 独立启动截图一致** |
| Queue | 原有单实例 UI 用例完成打开/关闭与状态断言，但无独立全布局截图验收 | 未完成完整目视检查 |
| 长标题 / Dynamic Type | 当前歌曲/歌手截断仍可见；未完成各页系统性长标题矩阵 | AX5 控制项问题已确认，其他未覆盖部分不记 PASS |

本轮执行的 Build / Tests（未修改任何测试）：

| 执行 | 结果与证据 |
| --- | --- |
| 430pt `build-for-testing` | PASS，`/tmp/music-final-build.log`，DerivedData `/tmp/music-final-build` |
| MusicArchitecture、MusicCache、MusicSearch、Mini Player 五 Tab、AX5 音质入口，共 12 项 | 11 PASS / 1 FAIL / 0 skipped，`/tmp/music-final-430.xcresult`、`/tmp/music-final-430.log`、`/tmp/music-final-430-summary.json` |
| 歌单详情二次进入原用例，再执行 2 次 | 2/2 FAIL，连同首次共 3/3 同位置失败；`/tmp/music-final-430-playlist-repeat.xcresult`。原始失败保留，不用后续执行覆盖 |
| AX5 音质入口原用例，再执行 2 次 | 2/2 自动断言 PASS，但两次截图均存在同样图标重叠；`/tmp/music-final-430-ax5-repeat.xcresult`。`isHittable` 通过不能替代视觉验收 |
| SwiftPM / 全量 iOS Unit | 本轮没有源码变更，未重复此前完整套件；前述历史单测结果不作为真机 PASS 依据 |

截图导出目录：`/tmp/music-final-430-attachments`、`/tmp/music-final-430-ax5-repeat-attachments`，各自 `manifest.json` 对应测试名称。Device Hub 的原生控制接口未能取得可操作界面，因而未完成剩余 AX5 页面的人工作业；没有为此改代码或降低测试标准。

### Instruments

| 类别 | 实际数据与限制 |
| --- | --- |
| CPU | 成功录制的第二组长度 241.646 秒，Time Profiler 导出 5844 个采样，总 weight 5844ms；含 `UIApplicationMain` 栈的主线程 weight 4575ms，按录制墙钟粗估约单核 1.893%。这是切歌/播放场景的采样估计，不是连续 CPU 仪表值，也不是 100 行滚动 CPU |
| SwiftUI / decode | 主线程栈可见 AttributeGraph、Swift metadata、内存操作等；未形成 100 行滚动的 body 与图片 decode 分解，不据此提出优化 |
| Memory | 本轮无可签署的 Allocations 峰值、图片缓存字节数或 Memory Graph 结论 |
| Frame rate | 首组 Core Animation FPS 随组合 trace 保存失败；没有有效的帧率、>16.7ms frame 或持续 hitch 统计，不能宣称接近稳定 60fps |
| Network | 首组 Network Connections 的 xctrace 自身 SIGTRAP，崩溃栈为 `NetworkConnectionStatsModeling.__receiveRow`；不是 App crash。未获得逐曲 URL 或图片 key 请求计数。后续录制移除此工具以保留可用采样，没有改网络生产代码 |
| Lyrics | 真机歌词打开超过一分钟，观察到高亮/自动滚动和换歌后的歌词变化。Time Profiler 出现 1 个含 parser 的采样，**采样数不等于调用次数**，不能据此写 parse=1；未完成真机 probe 调用计数及精确前后 seek 验证 |
| MV | 原有 fixture UI 的详情一次请求测试通过；真实 MV 清晰度/retry 会话及 detail 请求次数未完成 |
| Mini Player probe | 430pt 原有 DEBUG 探针测试通过 `instances=1` 和跨五 Tab、push/pop、Queue、Now Playing 的 identity；镜像没有暴露手机 AX 值，尚无真机 probe 读数 |

CPU 导出与汇总：`/tmp/music-final-next-v2-cpu.xml`、`/tmp/music-final-next-v2-cpu-summary.json`。第一组失败记录：`/tmp/music-final-device-playback-trace.log`；短后台记录：`/tmp/music-final-device-background.trace`、`/tmp/music-final-device-background-toc.xml`。这些是本机临时证据，可能被系统清理；关键计数、测量值和限制已写入本报告。

补充录制 `/tmp/music-final-device-next-v3.trace` 已成功保存，恢复 Hi-Res 的 transition `0x8c` 为 502.537ms，无 prepared hit；第三份 controlled 录制的恢复慢路径 `0x96` 为 8652.164ms，无 prepared hit。两项均保留为单次观察，不混入 10 次 prepared 下一首统计，也不作为五首首次冷起播数据。补充的三个 prepared 样本见 Playback；原始事件另见 `/tmp/music-final-next-v3-events.json`。第二个窗口仍出现秒级下一首延迟，第三个窗口两次均超过 300ms；尚未完成同曲重复及等待原因归因。

### Remaining Issues

#### Issue 1：歌单管理入口的空白区域点击无响应

**现象**：音乐首页“管理全部歌单”行可见，点击行中央空白区域不进入列表；点击文字可进入。

**复现步骤**：430pt 启动既有音乐首页 fixture，等待首页内容出现，运行原 `testPlaylistDetailReentryKeepsContent`；测试在第一次进入“我的歌单”时失败。真机对同一入口分别点击中央空白和左侧文字作差异检查。

**发生概率**：430pt 原用例 3/3（首次及独立两次复查）；真机差异检查 1 组。未将后续缺失详情行的断言当作独立缓存故障。

**测量数据**：失败 AX 树显示按钮 frame `(32, 764.7, 366, 52)`pt，Tab Bar 从 y=849 开始；按钮可见且未被 Tab Bar 覆盖。失败视频尾帧也显示已加载首页和完整入口。

**日志 / Signpost**：`/tmp/music-final-430-attachments/E8847767-C0CA-4091-AAA5-DA0D07344980.txt`；`/tmp/music-final-430-playlist-failure-end.png`；上述两份失败 xcresult。视频提取尾帧实际时间为 10.163 秒，不将提取请求时间误当实际帧时间。

**涉及模块**：`Sources/SetuIOSApp/Features/Music/MusicHomeView.swift` 的“管理全部歌单” Button（当前约第 277 行）；`SetuPressableButtonStyle`。

**初步根因**：label 内 HStack 包含透明 Spacer，`contentShape(Rectangle())` 位于 Button 外侧。结合点击文字有效，怀疑 label 内透明区域未形成预期命中范围；尚未用代码修复作因果验证，不归因于 Repository/Store。

**最小修复建议**：仅把该入口的矩形命中范围落实到 label 的 frame/padding 之后，保持原视觉与路由；用原失败用例和真机空白/文字两处点击复核。暂不修改共享按钮样式，不重构导航。该建议随后获得用户授权，执行结果见下方续记。

**Issue 1 修复续记（2026-09-03）**：仅将“管理全部歌单” Button 的 `contentShape(Rectangle())` 从 Button 外移入 label，放在已有 frame/padding 之后。生产 diff 为移动这一行；文字、图标、颜色、间距、frame 和 `.playlists` 路由均未修改，共享按钮样式、Store、NavigationStack、Mini Player 与 Root overlay 均不变。

| 验证 | 结果与证据 |
| --- | --- |
| 修复前回归能力 | 新增普通字号坐标用例：文字点击成功，返回后中央空白点击失败；`/tmp/music-issue1-red.xcresult`。当时 AX5 的文字/中心/右侧检查通过，未将其记作修复前必失败 |
| 原失败用例连续 3 次 | `testPlaylistDetailReentryKeepsContent` 原方法与断言不变，`-test-iterations 3`，**3/3 PASS**；`/tmp/music-issue1-reentry-3.xcresult`、同名 `.log`。xcresult summary 按唯一测试显示 1 项，日志保留完整三次迭代 |
| 430pt 普通字号与 AX5 命中区域 | **PASS**：文字、行中央、实际 Spacer 空白、右侧有效区域、返回后再次点击，都进入“我的歌单”。AX5 的行中央可能落在文字内，因此另按文字与箭头 frame 计算实际空白中点，不以文字点击替代空白验证 |
| 视觉 | 修复前后普通字号和 AX5 截图均已目视检查，入口字体、图标、间距与尺寸未见变化。AX5 截图的滚动位置不同，不宣称整屏逐像素相同 |
| Music 相关回归 | **131/131 单测 PASS**；UI 初次 **10/12 PASS、2/12 FAIL、0 skip**，`/tmp/music-issue1-music.xcresult`。MusicCache 全部 4 项与 MusicSearch 全部 3 项通过；不能把整套初跑写成全绿 |
| 两项旁路失败的对照 | `testSinglePlayerIdentityAcrossTabsPushPopQueueAndNowPlaying` 在换歌后的按钮断言失败；`testSongPlaylistSheetUsesExistingStoreAndPreservesSummary` 未打开加入歌单弹层。用与任务开始时 hash 一致的隔离修复前源码，以及修复后源码，各自仅运行这两项，均 **2/2 PASS**；`/tmp/music-issue1-baseline.xcresult`、`/tmp/music-issue1-comparison-fixed.xcresult`。未发现与本次修复的稳定关联，但初次失败原因仍未确定，未修改这些业务或断言 |
| Build | 430pt 模拟器构建与真机 `generic/platform=iOS` 构建成功；`/tmp/music-issue1-device-build.log`。真机包：`/tmp/music-issue1-device-build/Build/Products/Debug-iphoneos/SetuIOSApp.app` |
| 真机三处点击 | **PASS**：设备重新连接后已安装并启动本次修复包，在 iPhone 17 / iOS 27.0、普通字号、真实数据首页，通过 iPhone 镜像分别点击左侧文字、中央 Spacer 空白、右侧箭头，三处均进入“我的歌单”；返回后再次点击中央空白也成功。安装与启动记录：`/tmp/music-issue1-install.json`、`/tmp/music-issue1-device-launch.json`。真机宽度为 402pt，不替代上述 430pt / AX5 模拟器验收 |

回归测试位于 `Tests/SetuIOSAppUITests/MusicCacheUITests.swift`，使用坐标触发真实 hit testing，不是无障碍直接激活；未加入固定 sleep，未放宽原断言。新增测试还确保入口完整位于导航栏与 Tab Bar 之间，防止把遮挡误判为命中区域缺陷。截图证据：`/tmp/music-issue1-music-attachments/B47E5445-BAC7-4804-B222-52D0CD9CDCF9.png`（普通字号）、`155909DA-0ADA-4E1C-8FB7-B40B3D96EAF3.png`（AX5）。

本轮工具异常单独记录：Music 测试全部结束后，Xcode 收集失败场景的 `simctl diagnose` 停滞超过 8 分钟；进程采样确认等待诊断子进程，仅对该子进程发送 SIGINT，未中断测试用例。最终 xcresult 正常生成，保留 143 项的 141 通过 / 2 失败结果及截图。自检只允许本入口源码、其回归测试和本 Issue 续记变化；未修复 Issue 2、Issue 3 或其他音乐问题。

#### Issue 2：430pt AX5 播放控制图标重叠

**现象**：Now Playing 底部模式图标与上一首、下一首与更多图标发生视觉重叠。音质入口断言通过，但不能说明整行布局正常。

**复现步骤**：430pt 运行原 `testMusicQualityMenuIsReachableAtAX5`，打开 Now Playing，检查底部控制行；独立启动复查两次。

**发生概率**：3/3 独立启动截图相同。尚未证明重叠造成了按钮误触；真机 AX5 未测。

**测量数据**：截图为 1290 × 2796px / 430 × 932pt。源码普通圆按钮固定 50 × 50pt、中心播放按钮 72 × 72pt，符号分别使用随 Dynamic Type 缩放的 headline/title；没有测量触点误差。

**日志 / Signpost**：原截图 `E719E003-379A-4124-BC46-F55F9CA93C31.png`；复查截图 `4725012E-8692-43A8-86A4-224DE66413B3.png`、`4B64B588-F1CD-411F-BEAD-A8100DDF4C1B.png`，位于上述 attachments 目录。

**涉及模块**：`Sources/SetuIOSApp/Features/AppShell/MusicMiniPlayerBar.swift` 的 Now Playing `bottomPanel`、`NowPlayingRoundButton`、more menu。

**初步根因**：随辅助字号放大的符号超出固定按钮几何空间；普通字号截图未出现同样重叠。

**最小修复建议**：只约束播放控制符号在按钮可用区域内的尺寸，或局部适配辅助字号下控制行布局，保留至少 44pt 点击区域和完整无障碍标签；不全局缩小文字、不修改播放器状态。**等待确认，未实施。**

#### Issue 3：prepared 命中后仍存在秒级起播长尾

**现象**：最终 10 次有效记录都命中 prepared，其中 7 次超过 300ms；第二组末尾 3 次连续超过 3 秒才观察到 `.playing`，未达到 300ms 目标。

**复现步骤**：真机 Hi-Res 播放 `test` 搜索的 10 首队列，上一首稳定播放超过 5 秒，逐次点击 next；包含列表回绕。按 `TrackTransition` 配对到首个 `TrackPlaying`，同时确认区间含 `PreparedItemHit`。

**发生概率**：最终三个录制窗口合计 7/10 超过 300ms、3/10 超过 3 秒。尚未完成同一首/同一路由三组独立重现，不扩大为所有歌必现。

**测量数据**：完整十项与 median/P90/worst 见 Playback。录制带有 Time Profiler 开销，镜像期间另有连接/剪贴板异常；这些因素是否影响媒体或 MainActor 回调尚未排除。

**日志 / Signpost**：`music-final-next-v2-events.json` 中 transition IDs `0x6f`–`0x75`，每项均存在 prepared hit；长尾项为 `0x73`–`0x75`。没有把镜像点击等待时间算入内部 transition。

**涉及模块**：`MusicPlaybackController`、`NextItemPreparer`、AVPlayer/媒体源、蓝牙音频路由。

**初步根因**：尚未确定。现有 preparer 在 asset 可播放且 item 未失败时保存 prepared；命中只证明 track/quality/URL 和 item 匹配，未提供已缓冲可立即出声的运行时证据。耗时发生在 prepared 命中之后，需进一步区分媒体就绪、音频 session、缓冲等待和 `.playing` 回调调度，不能凭 hit 就归因于 URL resolver。

**最小修复建议**：已补齐 10 个有效样本，但当前证据仍不足以安全选择代码修复；下一步只做同曲重复，观察等待原因/媒体就绪和音频路由，再提出局部修复。**不调整 buffer、缓存或播放器架构。**

另有一次 UI suite 的 `Modifying state during view update` runtime warning，尚未定位到稳定用户症状，保留线索，不据此实施改动。

完整普通用户流程尚未走完：真实添加/删除歌曲、≥20 首随机、单曲循环、100 首性能、真实 MV、锁屏控制、Bluetooth 断开与系统中断仍有缺口。缺少证据的项目均未记为 PASS。本节记录已经完成的验证和明确阻塞，不代表二十三项验收全部完成。
