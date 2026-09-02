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
