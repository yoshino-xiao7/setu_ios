# Music Phase 3：搜索优化实施记录

日期：2026-09-02。仅执行 Phase 3；Phase 5 未开始。

## 基线与范围

实施前完整核对工作区 `../docs/music-performance-optimization-plan.md` 和本目录 Phase 1、2、4 实施记录，并重新阅读当前源码。修改前 Music 测试 65 项通过。原搜索页仍存在 View 局部结果状态、无 debounce、直接 API 请求、首屏 footer 自动加载第二页、单个 List cell 内嵌全部歌曲和 body 聚合等问题。

开始时工作树包含此前三个 Phase 的未提交修改。本轮以 `/tmp/setu-phase3-start` 文件快照隔离 review 范围，保留此前修改；没有创建分支、提交或推送。

## 最终架构

旧：`MusicSearchView @State + MusicClient.search + 内嵌 MusicSongList/VStack`。

新：`MusicSearchView → MusicStore.searchSession → PagingController<MusicSongRowModel> + MusicRepository → MusicClient`。

- `MusicStore` 唯一持有 `MusicSearchSession`，与现有 Repository 共用同一实例。页面只保存 sheet、反馈和视口状态，不再保存业务结果副本。
- Session 保存 query、实际执行的 keyword、当前结果 keyword、分类、首搜活动、generation、历史偏好与预计算聚合。原始歌曲只随 pager 的轻量 row model 保存；页码、总数、末页、分页错误由现有 PagingController 保存。
- `MusicSongRowModel` 仅预计算 title、artist、album、cover URL、hasMV，并保留原始 MusicSong。MV、加入歌单、下载、播放入口保持原行为。
- 用户切换同步清空 session，并同步替换 Repository；旧请求的取消与 generation 检查阻止回写。设备级搜索历史继续复用原 UserDefaults key，保持原先的本地历史偏好语义，不把它改造成账户数据。

## 输入、取消与状态恢复

- trim 后的关键词变更启动 session 持有的 400ms debounce；空白不请求，支持单个汉字。逻辑时钟可注入用于确定性测试。
- Submit/搜索按钮立即启动或加入同词进行中的任务，并取消待触发的 debounce。同词已加载且 TTL 未过期时直接保留已有页，不重建结果。
- Session 的工作不由离开 View 取消；查询变化、reset、释放 session 负责取消。后台闭包弱引用 session，不把网络层放到 MainActor。
- Repository 的 search flight 追踪消费者，最后一个消费者取消时才取消底层 Task；一个消费者取消不伤害同 key 的其他消费者。其它 Phase 1 SWR 资源仍可在消费者离开后完成缓存预热。
- Repository ticket、Session generation、PagingController generation 三层分别保护缓存、搜索上下文和页提交，覆盖忽略 cancellation 的旧响应。
- 有结果时新搜索或失败保留结果；只在无结果的实际搜索中显示 Skeleton。过期缓存可先恢复后静默更新。

## 缓存与分页

- 搜索 API key 为 `trim(keywords) + offset + limit`，TTL 600 秒，直接复用 Repository 的缓存、in-flight、force 与精确 invalidation。
- 首页 `limit=10, offset=0`，只请求一页。分页由现有 page 编号映射为 `(page - 1) * 10`，与去重后的 UI 条数无关。
- PagingController 新增可选 `PageResult.hasMore`，用于 raw offset 到末页时结束；默认 nil 保留既有调用者语义。原来的 ID 去重仍在 PagingController 中完成。
- 搜索结果是 `List + Section + ForEach` 独立行。最后三行通过 iOS 16 起可用的 `onGeometryChange` 检查真实视口交集；用户滚动过当前关键词后才触发预取，避免 List 预布局导致首屏自动第二页。
- 视口变化不循环重试失败页；失败后由现有 retry footer 明确重试。提供 44pt「加载更多歌曲」按钮，兼容辅助操作与聚合分类继续分页。
- 相同页的并发触发由 session task 与既有 pager phase 去重。旧关键词分页不会追加到新结果。

## 渲染与功能兼容

- 有实际结果时隐藏完整历史列表；无结果/空态仍支持历史点击、删除、清空、最多 10 条及去重。
- Artist / Album 聚合只在成功替换或追加结果时计算；输入和 segment 切换不聚合、不请求网络。
- MusicSongRow 继续使用 MusicArtworkView → Phase 4 统一图片缓存，不新增图片网络请求或缓存基础设施。
- 保留 NavigationStack、播放器、MV、下载与加歌单行为。本轮未修改播放引擎、URL resolver、Mini Player、图片缓存、APIClient、AuthSigner 或后端。

## 与方案的最小适配

1. debounce Task 由 SearchSession 持有，而不是由 `.task(id: query)` 持有，使搜索任务与结果一致地跨 pop/push 保存；页面 `.task` 只负责激活会话。页面实例 UUID 区分同一路由重新出现与新的显式入口，避免 tab 往返覆盖后来输入的关键词。
2. 搜索页直接建立独立 List 行，没有修改首页/推荐弹层仍使用的 MusicSongList，避免扩大到非搜索布局。
3. 未给含动作闭包的 MusicSongRow 强行增加 Equatable，以免比较忽略闭包导致旧播放队列/动作残留；通过稳定 ID 与预计算 model 降低重复计算。
4. 实测 List 单元的 PreferenceKey 跨 hosting 边界未可靠传递可见性，改为直接几何回调；部署目标 iOS 17/macOS 14 均支持该 API。
5. 首页原有空搜索框回车不会触发导航。UI 重入验证使用现有非空提交入口，session 的 nil initialQuery 恢复另由单测覆盖；未更改首页入口行为。

## 测试与证据

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| App Build / build-for-testing | PASS | `/tmp/setu-phase3-reviewed-build.log`、`/tmp/setu-phase3-reviewed-tests-build.log` |
| 完整 SwiftPM | 215 通过，0 失败 | `/tmp/setu-phase3-verified-swift.log` |
| 最终完整 iOS Unit Tests | 221 通过，0 失败 | `/tmp/setu-phase3-final-verified.xcresult` |
| 完整 UI Tests（包括已有公开页面 opt-in） | 41 项：38 通过、3 个既有基线失败、0 跳过 | `/tmp/setu-phase3-all-ios.xcresult` |
| 自检后最终 Music UI 复测 | 5 通过（3 搜索 + 2 缓存导航），0 失败 | `/tmp/setu-phase3-final-verified.xcresult` |
| Phase 1 Repository / Store 回归 | 14 通过 | 最终 iOS 单测 |
| Phase 2 播放控制器 / Queue / URL resolver / Quality 回归 | 36 通过 | 最终 iOS 单测 |
| Phase 4 图片缓存回归 | 16 通过 | 最终 iOS 单测 |
| Row 375/430pt 标准与辅助字号 | 4 张截图人工检视通过，无文字/按钮重叠 | `/tmp/setu-phase3-all-ios-attachments/manifest.json` |
| `git diff --check` | PASS | 本轮自检 |

完整 UI 的 3 个失败与上阶段原始基线 `/tmp/setu-phase4-baseline-ui.xcresult` 的名称、位置和原因一致：

1. `RandomImageConsumptionUITests.testFirstHighResolutionOpenRequiresExplicitPointsConfirmation`：旧高清确认文案断言失败。
2. `UXFlowUITests.testTwoAssetsApplyAndReturnWithNames`：资产入口未进入选择页，找不到“使用 电影感光影”。
3. `UXFlowUITests.testUnauthorizedMainRoutesReturnAfterLogin`：音乐入口找不到“重新登录”。

未删除、skip 或修改这些测试/业务流程。完整套件先执行，之后的路由重现与历史自检修复使用冻结后的最终产物再次运行完整单测及音乐 UI；相关源文件 hash 冻结记录位于 `/tmp/setu-phase3-final-source-hashes.json`。

- 基线 Music：65 通过，`/tmp/setu-phase3-baseline-music.log`。
- 搜索 Session 31 项；Repository 搜索 3 项；真实 HTTP 搜索集成 1 项；通用分页新增 2 项。
- UI 覆盖首屏 10 条、无第二页、真实滚动分页、输入自动搜索、历史隐藏、分类切换与 pop/push 恢复；最终套件额外滚动至 100 首，并验证切换 tab 后保留后续关键词。
- Row 布局快照覆盖 375/430pt 与标准/辅助字号，4 张截图已人工检视。
- 确定性逻辑时钟验证 399ms 不请求、400ms 请求；无固定 sleep 掩盖竞态。
- 缓存 A→B→A 的 Store/Repository 层耗时由 ContinuousClock 测量并严格断言 <100ms。最终实测 macOS 0.644ms、iOS 模拟器 1.265ms；不能据此声称真实端到端首帧或真机 60fps。

## 验收结果

| 项目 | 结论 |
| --- | --- |
| 400ms debounce、单汉字、空白不请求 | PASS |
| Submit 立即执行且与 debounce 去重 | PASS |
| 首次仅 offset=0 / limit=10，无自动第二页 | PASS |
| 接近末三行加载、重复触发去重、ID 去重与末页停止 | PASS |
| 旧搜索/旧页/旧用户响应不能回写 | PASS |
| TTL 内同词 0 次新请求，A→B→A 缓存恢复 | PASS |
| 原结果在新搜索/失败时保留 | PASS |
| pop/push 与 tab 往返保留查询、分类和结果 | PASS |
| 历史隐藏、Artist/Album 预计算、独立 Lazy 行 | PASS |
| Phase 4 图片缓存复用 | PASS（调用链与 16 项缓存回归） |
| 100 首夹具列表连续滚动加载 | PASS |
| Store/Repository 层缓存恢复 ≤100ms | PASS（约 0.64ms / 1.26ms） |
| 真机 100 首真实封面滚动 60fps / Instruments | 无法验证 |
| Phase 1 / 2 / 4 回归 | PASS |
| 全部既有 UI 测试全绿 | FAIL（3 个已知基线失败） |

## 自检

以 Phase 3 开始快照逐文件比较，本轮 15 个文件（含生成工程、测试和本记录）。播放器、图片加载实现、首页/歌单数据流、Mini Player、NavigationStack 定义、AuthSigner/APIClient 和后端均未在本轮修改。

- 业务歌曲仅由 pager 保存；View 不保留副本，聚合只保留派生结果。
- 搜索无无条件 `.loading` 赋值，无新的 `AsyncImage` 或图片请求管线；行直接复用 MusicArtworkView。
- 关键词改变/用户 reset 先撤销工作再接收新请求；已取消页不写入、不留下 loading/error。
- 异步工作弱持有 session；debounce 启动搜索后不持有跨网络等待的强引用。
- 同一路由重新出现不覆盖后续输入；用户 reset 后旧路由入口也不会重放旧查询。
- 分页失败的可见性回调不循环重试；缓存命中后的显式提交仍记录原有搜索历史。
- 保留旧结果时的错误继续使用 SetuErrorRecoveryButton，保留重新登录/重试等既有恢复动作。

完整 SwiftPM 在并发构建负载下曾暴露原有 `MusicClientTests.testAddHistoryRequestPostsPlaybackTrackPayload` 的异步探针竞态：响应完成后即断言，但记录请求的 Task 尚未完成。与开始快照对照，该测试此前已有相同写法。本轮只补 `XCTestExpectation` 等待记录完成，原断言、生产代码均未放宽或更改；修正后 215 项完整 SwiftPM 通过。

## 验收边界

真实音乐服务耗时、网络波动下的首帧、100 首真实封面列表的真机 60fps、Instruments CPU/内存仍需要真机 profiling；模拟器、夹具与单测不能替代该结论。API 搜索缓存复用现有进程内字典，当前未新增容量淘汰策略，长期大量不同查询的峰值内存仍需实测。

## 下一阶段

Phase 5。本轮未执行。
