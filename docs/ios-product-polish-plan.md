# 雪涼云 iOS 产品化体验改版方案

状态：执行基准

日期：2026-07-10

适用范围：`Sources/SetuIOSApp`，必要时联动 `Sources/SetuIOSCore` 与后端契约

目标版本：从“功能完整的开发版”收口为“用户可理解、可信任、可持续使用的原生 iOS App”

---

## 1. 文档定位

本文是后续 iOS 产品化改版的**优先级与验收基准**，负责回答：

- 为什么当前 App 仍有“开发版感”；
- 哪些体验必须先改；
- 每项改造的目标交互、涉及文件与验收标准；
- 后续 PR 应按什么顺序实施与验证。

本文与以下文档共同组成 iOS 体验规范：

- `ios-soft-pink-ui-design.md`：视觉 token、组件外观、页面视觉结构；
- `ios-functional-experience-spec.md`：加载状态、长任务、网络恢复、平台能力；
- **本文**：产品定位、用户旅程、任务优先级与实施路线。

若三份文档出现冲突：

1. 安全、认证和后端契约以仓库 `AGENTS.md` 与契约文档为准；
2. 用户旅程、开发顺序与验收优先级以本文为准；
3. 具体色彩、字体、间距和组件形态以柔粉视觉规范为准。

---

## 2. 当前基线与核心判断

### 2.1 已经完成的基础

当前工程并非“没有设计”：

- 已建立 `SetuColor`、`SetuSpacing`、`SetuRadius`、`SetuTypography`；
- 品牌色、背景色、文字色和状态色均提供 Light/Dark 资源；
- 已有 `SetuCard`、`SetuHeroCard`、`SetuPrimaryButton`、`SetuPill`、`SetuEmptyState` 等共享组件；
- 未发现全局固定字号滥用，基础字体支持 Dynamic Type；
- 音乐播放、Live Activity、独立 Tab 导航栈等原生能力已经具备。

因此，下一阶段不再进行一次单纯的“全站换皮”。

### 2.2 “开发版感”的真正来源

当前问题主要来自以下五类：

1. **产品价值没有先于登录出现**：首屏展示 API 宣传海报，而不是用户能做什么；
2. **后台模型直接暴露**：队列、节点、PID、CFG、LoRA、HTTP、Trace ID 等成为主界面内容；
3. **Web 控制台交互残留**：大量 `List + Card`、上一页/下一页、批次与任务编号；
4. **用户闭环未完成**：刷图不能直接收藏，收藏不能打开，公开作品复用所有者详情；
5. **缺少系统性视觉 QA**：浅色对比度、键盘安全区、大字号、深色首屏和无障碍缺少验证层。

代码审计基线：

- 62 个 Feature Swift 文件中有 50 个使用 `List`；
- 至少 13 个普通用户页面使用“上一页 / 下一页”；
- Feature 层约有 163 处直接使用 `error.localizedDescription`，其中非管理页面约 111 处；
- 改版启动时尚无 SwiftUI Preview Gallery、UI snapshot 测试或 accessibility audit；当前运行证据见 8.2、8.3 与 Phase 5；
- 390×844pt 模拟器实测：首屏左右裁切，状态栏压住海报文字，深色模式仍使用同一张高亮位图。

### 2.3 产品化改版原则

后续开发必须遵循：

1. **先讲用户价值，再要求登录**；
2. **先呈现任务，再呈现参数**；
3. **任何扣费都必须可预期、可确认**；
4. **任何内容流都必须能完成查看、收藏、分享或继续操作的闭环**；
5. **普通用户默认不看后台字段、内部 ID 和原始状态字符串**；
6. **错误必须说明发生了什么、用户能做什么**；
7. **优先使用原生 iOS 组件与交互，不复制 Web 控制台**；
8. **Light/Dark、Dynamic Type、VoiceOver 和 Reduce Motion 同等重要**。

---

## 3. 目标用户语言

### 3.1 品牌层级

统一采用：

- 主品牌：**雪涼云**；
- 一级功能：AI 绘画、图片、音乐、广场、我的；
- “扣扣图片”“扣扣音乐”仅在明确作为子品牌时保留，否则改为功能名；
- 首屏、导航栏、关于页不得混用“雪凉云 API”“SETU CLOUD”“本站”等不同叙事。

### 3.2 术语替换

| 当前术语 | 用户语言 | 说明 |
| --- | --- | --- |
| 生成队列 / 可用节点 | 当前可创作 / 预计等待时间 | 健康时隐藏，繁忙时才显示 |
| 创建生成任务 | 开始生成 | 同时展示预计积分 |
| 生成后的提示词 | AI 整理后的画面描述 | 专家字段放高级设置 |
| 反向提示词 | 不希望画面中出现 | 保留专业名称作为辅助说明 |
| CFG | 画面遵循描述程度 | 高级设置内展示 |
| Steps / 步数 | 细节质量 | 高级设置内展示 |
| Checkpoint | 基础模型 | 高级设置内展示 |
| PID 模式 | 这些图片属于 | 选项改为独立作品 / 同一作品多页 |
| 积分调用 | 批量找图 | “调用”仅用于开发者工具 |
| 积分流水 | 积分明细 | 面向普通用户 |
| AI 任务 #123 | 作品详情 | ID 移入技术信息 |
| 投稿 #123 / 批次 #123 | 投稿详情 | ID 不进入主标题 |
| 公开审核 | 发布到广场 | 状态改为用户语言 |
| Request ID / Trace ID | 诊断信息 | 默认折叠，可复制 |

所有未知后端状态必须经过映射；不得以 `default: rawStatus` 直接显示给普通用户。

---

## 4. P0：首轮必须完成的改造

P0 解决首次印象、信任和主任务阻塞。P0 未完成前，不继续扩展新的普通用户功能。

### P0-1 首次打开与认证页

#### 目标

让用户在登录前理解雪涼云的价值，并以符合 iOS 习惯的方式进入产品。

#### 目标体验

欢迎页由原生 SwiftUI 内容与无文字品牌插画组成：

- 标题：`把灵感变成作品`；
- 副标题：`AI 绘画、高清图片与音乐，都在雪涼云`；
- 主操作：系统 `SignInWithAppleButton`；
- 次操作：`使用邮箱登录`；
- 新用户入口：`第一次来？创建账号`；
- 信任说明：`你的创作、收藏和歌单会安全同步`；
- 底部提供《隐私政策》《服务条款》入口。

`AuthBackground.png` 不再作为全屏首屏。可复用其中角色形象，但必须去掉 API、GET、JSON、URL 与嵌入式说明文字。

#### 访客体验

目标是允许未登录用户浏览公开示例或公开广场，受保护操作再引导登录：

- 可浏览：产品介绍、公开示例、公开广场；
- 需登录：生成、积分消费、收藏、投稿、歌单、个人内容；
- 若当前后端公共接口仍依赖会话，先完成契约审计，再决定增加匿名接口或本地示例；不得在未确认契约前绕过认证。

#### 布局要求

- 只有背景可 `.ignoresSafeArea()`；
- 表单必须置于 `ScrollView`；
- 使用 `safeAreaPadding` / `safeAreaInset`，不得写死 Home Indicator 间距；
- 使用 `FocusState` 管理输入焦点；
- 不得 `.ignoresSafeArea(.keyboard)`；
- 注册、登录、找回密码必须在 375pt 宽度与辅助功能字号下可滚动完成。

#### 涉及文件

- `Features/Auth/AccountView.swift`
- `Features/AppShell/RootAppView.swift`
- `Features/Auth/AppleAuthorizationService.swift`
- `Resources/Assets.xcassets/AuthBackground.imageset`
- `Resources/Assets.xcassets/AuthHeader.imageset`
- `Features/System/StaticInfoView.swift`

#### 验收标准

- [x] 390×844pt 首屏没有裁切文字或状态栏冲突；
- [x] 首屏不再出现 API、GET、JSON、接口服务等开发者文案；
- [x] Apple 登录使用系统提供的按钮样式；
- [x] 登录前可分别打开隐私政策与服务条款；
- [x] 375pt + 键盘 + AX5 字号下，注册表单仍可完成填写并触达提交按钮；
- [ ] VoiceOver 能读出品牌价值、主操作和次操作（自动化语义顺序与系统 accessibility audit 已通过，真实 VoiceOver 手势走查仍待完成）；
- [x] Light/Dark 有等价视觉，深色模式不继续显示高亮白底海报。

### P0-2 积分消费与通知权限

#### 目标

消除“暗扣积分”和“刚登录就索权”的信任风险。

#### 积分消费决策

随机刷图不得再因停留 650ms 自动消费积分。目标规则：

- 低清预览免费；
- 用户主动点击 `查看高清图 · 20 积分` 后才调用 consume；
- 消费前明确显示单次成本与当前余额；
- 消费成功后立即更新余额，并显示一次性明确反馈；
- 同一图片重复打开不得重复扣费；
- 余额不足时提供去查看积分明细或获取积分的下一步。

若未来重新引入自动解锁，必须满足：用户显式开启、可见倒计时、可取消、设置中可关闭；默认仍为显式消费。

#### 通知权限决策

- 登录完成时不得直接弹系统授权；
- 首次创建 AI 作品后出现上下文预提示：`生成完成时通知我，即使离开 App 也不会错过结果`；
- 用户确认后再调用系统授权；
- 通知中心或“我的”展示当前授权状态；
- 拒绝后提供 `前往系统设置`。

#### 涉及文件

- `Features/Developer/RandomImageSwipeView.swift`
- `Features/AppShell/UserHubViews.swift`
- `Features/AppShell/RootAppView.swift`
- `SystemPushCoordinator.swift`
- `Features/System/NotificationsView.swift`
- `Features/Auth/AccountView.swift`

#### 验收标准

- [x] 任何图片消费都由明确用户操作触发；
- [x] 消费前后余额与成本均可见；
- [x] 快速滑动、停留、切后台均不会意外扣费；
- [x] 首次登录不弹通知权限；
- [x] AI 任务完成通知的价值在系统授权前得到解释；
- [x] 拒绝通知后有恢复入口。

### P0-3 AI 快捷创作模式

#### 目标

普通用户可以只描述画面并快速开始生成；专家参数仍然可用，但不阻塞主任务。

#### 默认页面结构

1. `想画什么？`：多行自然语言输入；
2. `画幅`：竖图、方图、横图等可视化选项；
3. `风格与角色`：已选项缩略图或 pill；
4. `高级设置`：折叠区域；
5. 底部固定 CTA：`开始生成 · 预计 20 积分`。

默认不展示：

- Worker 数量、可用节点、节点阶段；
- 精确宽高 Stepper；
- CFG、步数、Checkpoint、LoRA 强度；
- 正向/反向提示词原始字段；
- 后端翻译服务名称或轮询状态。

高级设置中可保留上述能力，但必须使用用户语言，并提供“恢复推荐设置”。

服务状态规则：

- 服务健康：不显示状态卡；
- 繁忙：显示 `当前繁忙，预计等待约 X 分钟`；
- 不可用：显示原因、重试和稍后再试；
- 不显示 Worker、节点数量等运维信息。

草稿规则：

- 普通离开页面不得清空草稿；
- 进入历史、删除记录或切换 Tab 后返回，输入仍然存在；
- 仅用户明确清空或成功提交后清理草稿；
- 会话过期重新登录后尽量恢复未提交草稿。

#### 涉及文件

- `Features/AI/AiDrawView.swift`
- `Features/AI/AiDrawDraftStore.swift`
- `Features/AI/AiAssetBrowserView.swift`
- `Features/AI/AiGenerationLiveActivityCenter.swift`
- `DesignSystem/Components/SetuPrimaryButton.swift`

#### 验收标准

- [x] 新用户不打开高级设置即可提交作品；
- [x] 首屏不出现 CFG、LoRA、Worker、节点等术语；
- [x] CTA 无需滚到长列表底部才能触达；
- [x] CTA 明确展示预计积分；
- [x] 离开创作页再返回，草稿不丢失（含普通 `source=form` 草稿恢复测试）；
- [x] 生成成功后进入作品详情并启动正确的进度反馈；
- [x] Reduce Motion 下状态切换不依赖位移动画表达。

### P0-4 用户内容闭环与所有权边界

#### 随机图片与收藏

随机图片主操作统一为：

- 喜欢：一键加入默认收藏；
- 收藏夹：选择分类收藏；
- 查看高清图：明确消费积分；
- 下一张：手势与按钮均可。

默认收藏列表必须：

- 整行或图片可打开详情/原生预览；
- 支持移动到其他收藏夹；
- 移除后提供短时 `撤销`；
- 不以 PID 作为缺省主标题，优先使用作品或作者信息。

#### AI 公开作品与我的作品

拆分两种详情：

- `PublicAiWorkDetail`：作品、作者、喜欢、收藏、分享、复用灵感；
- `MyGenerationDetail`：生成状态、下载、发布到广场、删除管理、技术参数。

公开广场不得进入包含所有者审核和删除操作的详情。所有操作不仅要在 UI 隐藏，还要由后端继续执行权限校验。

#### 原生保存与分享

- 图片：使用系统分享面板，并提供 `保存到照片`；
- 音乐：使用系统分享/下载体验，不以“已打开下载地址”作为完成；
- 在实际保存时再请求照片权限；
- 保存和分享必须有成功、失败、取消三类反馈。

#### 涉及文件

- `Features/Developer/RandomImageSwipeView.swift`
- `Features/Content/FavoriteListView.swift`
- `Features/Content/CollectionDetailView.swift`
- `Features/AI/AiSquareView.swift`
- `Features/AI/AiHistoryView.swift`
- `Features/AI/AiGenerationDetailView.swift`
- `Features/AppShell/AppRoute.swift`
- `Features/AppShell/RootAppView.swift`

#### 验收标准

- [x] 刷到喜欢的图片可在当前页面完成收藏；
- [x] 收藏列表可打开、分类、移除并撤销；
- [x] 他人 AI 作品不展示审核和删除；
- [x] 我的作品仍可完成发布与删除管理；
- [x] 图片保存使用系统能力，不跳到浏览器完成；
- [x] 所有权限制同时通过 UI 与接口权限验证：他人公开作品只展示公开互动，私有详情、预览、下载、投稿审核与删除申请均由后端所有者校验拒绝越权访问；对应 UI 测试场景已加入测试目标，后端权限回归已通过。

当前契约审计与后续工作（2026-07-10）：

- [x] AI 广场、首页推荐和用户广场中的公开 AI 卡片统一进入 `PublicAiWorkDetail` 快照路由，不再调用仅限作品所有者的详情、预览签名、下载、审核或删除接口；
- [x] 公开详情可依据 `userId` 进入创作者公开资料入口；资料页通过公共摘要契约展示昵称、头像与公开内容统计，并同时加载该作者的公开 AI 作品和公开收藏夹；
- [x] 后端已增加专用 `PublicAiWorkDTO` 与 `GET /ai/square/{id}`；列表和详情只使用公共对象 URL，并统一校验任务已完成、审核通过、仍公开、未删除及公共 URL 非空。iOS 详情进入时会重新校验，下架返回后不再继续展示列表快照；Web 与 iOS 均已切换到最小公共类型；
- [x] 后端已提供 `GET /square/users/{id}` 公共作者摘要，并为收藏夹广场与 AI 广场增加 `ownerId` 过滤；仅有公开内容的启用账号可被发现，响应不含邮箱、角色、积分、IP 或认证字段。iOS 已移除从热门收藏夹前 100 条推断资料的临时实现；
- [x] 后端已补齐 AI 作品喜欢/收藏关系表、计数与当前用户状态，并通过 `PUT/DELETE` 提供幂等写接口；公开资格会在每次互动前重校验，所有者不能与自己的作品互动。iOS 公开详情展示真实计数与状态，失败时保留服务端确认前的界面；
- [x] 公开作品在仍公开时允许通过系统分享、保存或下载；管理员下架是资源撤销操作，后端会删除公共 OSS 对象并清空 `publicBucket`、`publicObjectKey` 与 `publicUrl`。OSS 删除失败时接口失败并回滚数据库更新，不向用户返回“已下架”的假成功；
- [ ] 在部署环境执行一次真实下架，确认旧 OSS URL 返回不可访问；若 `publicBaseUrl` 前接 CDN，还必须验证缓存清除或自然失效时间满足运营要求；
- [x] 当前版本不开放匿名 AI 广场：`/ai/square/**` 继续使用 Session + HMAC，避免把 R18 分区与用户互动状态拆成两套匿名契约；未登录用户通过欢迎页“先看看能做什么”浏览本地产品介绍，进入真实广场时再登录。若未来开放匿名浏览，应新增独立公共读取边界，而不是放开同路径下的互动写接口。

### P0-5 明显半成品问题清理

以下问题应随首轮 PR 修复，不单独延期：

- `SecuritySettingsView` 的 `已绑定(appleEmailDescription)` 字面量；
- 通行密钥页面暴露“应用域名配置”“请使用真机测试”等开发说明；
- 普通资料页突出用户 ID、角色等后台字段；
- “关于本站”改为“关于雪涼云”；
- 未知通知类型、目标类型和目标 ID 不直接显示；
- 普通用户操作反馈不得一律使用成功勾号。

---

## 5. P1：核心页面产品化

### P1-1 首页与跨 Tab 导航

#### 首页职责

首页不再重复底部 Tab，而是承担“继续、推荐、提醒”：

- 问候：`早上好，昵称`；
- 继续创作：最近草稿或生成中作品；
- 继续播放：上次歌曲或队列；
- 最近收藏：最近保存的图片；
- 今日推荐：公开作品、图片或音乐推荐；
- 必要提醒：积分不足、未读通知、生成完成。

移出首页：

- 积分流水；
- 批量参数；
- 分页调用记录；
- 与底部 Tab 重复的 2×2 功能目录。

#### 跨 Tab 导航

首页跳转音乐、广场、AI 等根模块时，必须切换对应 Tab，而不是把另一个 Tab 的根页面 push 到首页栈。

建议扩展统一 coordinator 表达：

- 切换目标 Tab；
- 可选重置目标 Tab 到根；
- 可选继续 push 目标子路由；
- 推送深链根据目标类型落到正确 Tab。

#### 涉及文件

- `Features/Dashboard/DashboardView.swift`
- `Features/AppShell/RootAppView.swift`
- `Features/AppShell/AppRoute.swift`
- `Features/AppShell/UserHubViews.swift`

#### 验收标准

- [x] 首页不再与 TabBar 重复导航；
- [x] 进入音乐页时音乐 Tab 正确高亮；
- [x] 返回行为不经过首页的重复音乐/广场根页面；
- [x] 推送 AI 任务落到 AI Tab，投稿结果落到图片相关 Tab；
- [x] 首页没有手动分页。

### P1-2 内容页布局与增量加载

按内容类型选择容器：

- 图片广场、AI 广场、收藏：`ScrollView + LazyVGrid`；
- 音乐歌曲、设置、日志：`List`；
- 创作流程：分步表单或 `ScrollView` + 固定 CTA；
- 沉浸刷图：减少卡片层级，让图片成为主角。

普通用户内容流统一改为：

- 下拉刷新第一页；
- 触底增量加载；
- 加载期间保留已显示内容；
- 底部显示加载中或“已加载全部”；
- 请求失败提供原位重试；
- 不再使用“上一页 / 下一页”。

显式分页可保留在管理员高密度列表中。

优先迁移：

1. AI 广场与 AI 历史；
2. 收藏夹广场、收藏夹详情、默认收藏；
3. 通知与音乐历史；
4. 投稿记录与删除申请。

实施进度（2026-07-10）：

- [x] AI 广场改为 `ScrollView + LazyVGrid`、下拉刷新与触底增量加载；
- [x] AI 历史改为 `ScrollView + LazyVGrid`、下拉刷新与触底增量加载；
- [x] 收藏、通知、音乐历史、投稿与删除申请迁移；
- [x] 积分明细与音乐搜索迁移为保留内容的触底增量加载；
- [x] 普通用户内容页已无“上一页 / 下一页”，管理员高密度列表继续保留显式分页。

### P1-3 音乐首页的新用户体验

音乐首页根据用户是否已有历史动态排序：

#### 新用户

1. 固定搜索框；
2. 每日推荐；
3. 推荐新歌；
4. 推荐歌单；
5. 热门搜索；
6. 空歌单引导。

#### 已有历史用户

1. 固定搜索框；
2. 继续听；
3. 我的歌单；
4. 每日推荐；
5. 其他推荐。

空态必须提供业务动作，例如：

- `还没有播放记录` → `去找一首歌`；
- `还没有歌单` → `创建第一个歌单`。

### P1-4 图库投稿三步流

将当前后台式单页表单改为：

1. **选择图片**：缩略图网格、单张删除、拖拽排序；
2. **填写信息**：标题、作者、标签、作品关系、内容级别、AI 来源；
3. **确认提交**：最终预览、图片数量、顺序、审核说明。

术语：

- `多 PID 单页` → `每张都是独立作品`；
- `单 PID 多页` → `多张属于同一作品`；
- `R18` → `包含 18+ 内容`，并提供说明；
- `AI 类型` → `图片来源：非 AI / AI 生成`。

取消投稿必须二次确认；投稿完成展示预计审核流程，不突出批次 ID。

---

## 6. P1：系统性反馈与错误处理

### 6.1 用户错误模型

禁止 View 直接展示 `error.localizedDescription`。建立集中映射层，例如：

```swift
struct UserFacingError: Equatable {
    let title: String
    let message: String
    let action: UserFacingErrorAction?
    let diagnosticCode: String?
}
```

基础映射：

| 类型 | 标题 | 下一步 |
| --- | --- | --- |
| 离线 / 超时 | 网络似乎断开了 | 检查连接、重试 |
| 401 | 登录已过期 | 重新登录并恢复原目标 |
| 403 | 当前账号无法执行此操作 | 返回或了解原因 |
| 404 | 内容不存在或已被移除 | 返回列表 |
| 409 | 当前状态已发生变化 | 刷新后继续 |
| 429 | 操作有点频繁 | 稍后重试 |
| 5xx | 服务暂时开小差 | 重试或稍后再试 |

`Request ID` / `Trace ID` 只进入可展开的“诊断信息”，支持复制，不出现在默认消息中。

### 6.2 类型化反馈

禁止再用 `String?` 加关键词判断成功或失败。建立：

```swift
enum SetuFeedback: Equatable {
    case success(String)
    case error(String)
    case info(String)
    case warning(String)
}
```

由类型决定：

- 图标；
- 颜色；
- 是否自动消失；
- 是否提供重试；
- VoiceOver announcement。

### 6.3 状态页标准

每个数据页面必须覆盖：

- loading：骨架或保留已有内容；
- empty：说明为什么为空，并提供主动作；
- failed：用户语言 + 明确重试；
- unauthorized：登录并恢复目标；
- loaded：内容；
- action feedback：不替换整个页面。

---

## 7. P1：视觉系统修正

### 7.1 对比度

当前浅色模式审计值：

- Hero 白字对渐变约 `1.64:1–2.56:1`；
- success/warning/danger/info Pill 文字约 `2.27:1–2.97:1`；
- `textTertiary` 对白卡约 `2.38:1`。

目标：

- 普通文本至少 `4.5:1`；
- 大文本和必要图标至少 `3:1`；
- 状态不得只依赖颜色表达。

实施：

- 新增 `onHero`；
- 为状态色拆分 `stateForeground` 与 `stateFill`；
- Light Hero 改深色渐变配白字，或浅色背景配深色文字；
- `textTertiary` 只用于非必要装饰；真实 caption 至少使用 `textSecondary`；
- Increase Contrast 下使用更强前景与边框。

### 7.2 Dynamic Type

- AX 字号下，首页三列指标改为单列或两列；
- 使用 `ViewThatFits`、`AnyLayout` 或 size category 分支；
- 关键信息不得依赖 `minimumScaleFactor` 缩小回固定高度；
- 副标题不以固定两行作为唯一布局保护；
- 表单、卡片和底部 CTA 必须允许内容增高。

### 7.3 触控与 VoiceOver

- 所有操作命中区至少 44×44pt；
- icon-only Button 必须提供明确 label；
- 选择项提供 `.isSelected`；
- 共享图片组件强制接收无障碍描述；
- 图片失败状态提供可发现的重试；
- 成功、错误和扣费结果使用 VoiceOver announcement。

### 7.4 Motion 与触觉

- Reduce Motion 时位移/缩放改为淡入淡出或无动画；
- 不为每个普通导航行统一触发触觉；
- 触觉保留给成功、警告、选择确认、刷图切换等有意义事件；
- 所有触觉必须与视觉/语义反馈同时出现。

---

## 8. P2：共享组件与工程守护

### 8.1 建议补充的共享能力

- [x] `SetuRemoteImage`：缓存、骨架、失败、重试、alt text；
- [x] `SetuBottomCTA`：安全区内固定主操作；
- [x] `SetuFeedbackBanner` / Toast：类型化反馈；
- [x] `SetuSkeleton`：列表与网格骨架；
- [x] `SetuLoadMoreFooter`：增量加载与结束状态；
- [x] `UserFacingErrorMapper`：错误映射；
- [x] `SetuPermissionPrompt`：通知、照片等上下文预提示；
- [x] `SetuPreviewFixtures`：稳定的假数据与状态样例。

共享能力应减少真实重复；不得为了“组件化”继续给每个页面套同一种卡片。

### 8.2 Preview Gallery

为 Design System 和关键页面增加 Preview：

- 375pt、390pt、430pt；
- Light / Dark；
- 默认字号、XXL、AX5；
- loading / empty / failed / loaded；
- Increase Contrast；
- Reduce Motion；
- 典型长中文和英文/数字混排。

首批页面：

1. 欢迎与登录；
2. 首页；
3. AI 快捷创作；
4. 随机刷图；
5. AI/收藏广场；
6. 音乐首页与迷你播放器。

当前已为欢迎页、首页、AI 绘画、随机刷图、AI 广场、收藏夹广场、音乐首页与迷你播放器增加页面级 Preview。业务页面 Preview 使用 DEBUG-only 内存 Keychain、内存草稿和离线 URLProtocol 夹具，不依赖公网图片或线上接口；Design System Gallery 继续承担 375/390/430、Light/Dark、AX5、Increase Contrast、Reduce Motion 与通用异步状态组合。Canvas 实际渲染仍属于后续运行验收项。

同时新增 `SetuDashboardUITestScenario`、`SetuMusicHomeUITestScenario` 与 `SetuCollectionSquareUITestScenario` 三个 DEBUG-only 隔离页面夹具，分别为首页、音乐首页和收藏夹广场提供稳定 loaded 数据。夹具直接挂载业务页面并使用离线 URLProtocol，不经过 `RootAppView`、真实登录/session 或 Tab coordinator，因此只作为页面级布局与无障碍证据，不能替代登录和跨 Tab 集成测试。

### 8.3 UI 测试

新增 App/UI test target，至少覆盖：

- 未登录启动与认证入口；
- 键盘下完成登录/注册表单；
- 首次随机图片消费确认；
- AI 创建、离开、返回后的草稿恢复；
- 公共 AI 作品不出现所有者操作；
- 收藏图片并在收藏列表打开；
- 通知预提示与拒绝后的设置入口；
- Dynamic Type 与 accessibility audit；
- Dashboard、MusicHome、CollectionSquare 隔离登录后页面在 Light + 默认字号与 Dark + AX5 下的滚动视口 accessibility audit。

Xcode 27 beta 的滚动视口 audit 只排除两类已确认噪声：`issue.element == nil` 的 `List` 滚动 `textClipped` orphan issue，以及可见面积不足元素自身 90% 的滚动边缘内容。测试 landmark 本身必须可点击且至少 90% 可见；其他 orphan audit 类型与可见面积达到 90% 的元素仍会失败。该测试是多个稳定视口的采样证据，不等同于完整页面穷举或真实 VoiceOver 手势验收。

---

## 9. 实施顺序与 PR 边界

按以下顺序推进，单个 PR 保持可编译、可独立验收。

### Phase 0：质量守护

- [x] 建立 Preview Fixtures 与关键组件 Preview；
- [x] 为首批关键页面增加离线页面级 Preview；
- [x] 增加颜色对比度测试或静态校验；
- [x] 增加基础 UI test target；
- [x] 记录 375/390/430 基线截图（欢迎页 Light/Dark 共 6 张，见 `docs/qa/ios-product-polish/`）。

### Phase 1：首次印象与信任

- [x] P0-1 欢迎/登录页重构；
- [x] 官方 Apple 登录按钮；
- [x] 键盘、安全区、隐私入口；
- [x] P0-2 积分显式消费；
- [x] 通知上下文授权与恢复入口；
- [x] P0-5 半成品问题清理。

### Phase 2：核心任务

- [x] P0-3 AI 快捷创作；
- [x] 草稿生命周期修正；
- [x] 固定生成 CTA 与积分说明；
- [x] P0-4 随机图片与收藏闭环；
- [x] 公共/私有 AI 详情拆分；
- [x] 原生保存与分享。

### Phase 3：首页与内容流

- [x] 首页从功能目录改为继续/推荐；
- [x] 跨 Tab coordinator；
- [x] 普通用户内容页增量加载；
- [x] 图片广场与收藏网格化；
- [x] 音乐首页按用户状态排序；
- [x] 投稿三步流。

### Phase 4：系统性收口

- [x] `UserFacingErrorMapper`；
- [x] `SetuFeedback` 类型化反馈；
- [x] 清理普通用户界面的内部 ID 与原始状态；
- [x] 统一状态页、重试和空态动作；
- [ ] 对比度、Dynamic Type、VoiceOver、Reduce Motion 全量检查。

当前收口进度（2026-07-11）：

- 普通用户 View 已不再直接展示 `error.localizedDescription`；Apple / Passkey 平台服务保留各自的专业错误映射，Live Activity 仅保留诊断日志；
- `Request ID`、`Trace ID` 与 HTTP 状态由 `UserFacingErrorMapper` 隔离到诊断字段，不进入默认消息；
- 普通用户操作反馈已迁移为 `SetuFeedback`，播放器也使用类型化反馈并按成功/信息/警告/错误决定展示时长；
- `SetuRemoteImage`、`SetuSkeleton`、`SetuBottomCTA` 与 `SetuPermissionPrompt` 已分别落到至少两个真实调用场景；远程图片统一缓存、加载、失败、重试与无障碍描述，通知和照片权限均先说明用途再由用户触发；
- 服务端 ISO 时间统一转换为本地短日期或完整日期；平台未知错误不再回显系统原文，通行密钥 transport 等协议字段已映射为用户语言；
- 未知 AI、审核、删除与投稿状态统一使用用户语言兜底，不再回显原始状态；投稿详情、文件名和普通内容卡片不再突出内部 ID；
- AI 模型文件名、任务编号、删除申请编号、上传批次编号、系统健康码与原始服务状态均已从普通用户界面移除或映射为产品语言；系统状态页只展示“服务状态、今日使用、检查时间”等用户可理解的信息；
- 主要数据页已覆盖 loading / empty / failed / loaded、原位重试和业务下一步；MusicHome 的热门搜索、最近播放、我的歌单、歌曲推荐和推荐歌单失败态均可在原区块重试；401 由全局会话失效链路返回登录页，登录后保留原 Tab 导航状态；
- `UserFacingErrorAction` 已开始驱动真实恢复操作：AI 创作和积分调用可执行重试、重新登录、刷新、返回、检查填写内容、稍后再试与查看积分明细，而不是只展示一段错误文字；
- 公开 AI 作品已从所有者详情彻底分流，公开图片只使用广场响应中的展示 URL；作者入口已接入公开资料摘要、公开作品与公开收藏夹，喜欢/收藏也已具备真实计数、当前用户状态和幂等写入闭环。针对线上列表可用但详情路由返回兼容性 404 的情况，刚从广场进入的快照会继续显示并提供重试，不再误报“作品已下架”；已经成功核验过的作品随后明确返回 403/404 时仍会进入真实下架状态。下架会删除公共 OSS 对象并清空定位字段，部署环境的旧 URL 与可选 CDN 缓存失效仍需运行验收；
- AI 绘画与广场主页已接入“扣扣绘画”“扣扣广场”品牌 Logo；广场 Hero 的白色“AI 绘画”按钮使用专门的深色前景语义色，Light/Dark 均保持可读，并由颜色对比度单测保护；
- 首页推荐、每日图片与随机刷图的主内容已统一使用带缓存、骨架、失败和重试语义的 `SetuRemoteImage`；音乐封面默认不自行生成失败重试按钮，嵌入播放或歌单按钮时由父级统一承载交互，避免生产图片失败后形成嵌套按钮；普通用户功能中剩余原生 `AsyncImage` 仅用于与姓名相邻的装饰头像和 AI 资源缩略图，并已隐藏重复的头像朗读；
- 欢迎页次操作与隐私入口、首页区块动作、每日图片操作、API Key 操作和播放器恢复按钮已补足 44pt 命中区；共享空态隐藏装饰图标，并按是否包含恢复按钮组织 VoiceOver 子元素；投稿步骤与每日图片的多操作区域会在宽度不足时改为纵排；
- Dynamic Type 单列降级、长分段选择器的菜单降级、图片无障碍描述、44pt 操作区与 Reduce Motion 静态改造已完成；Hero、方形网格、音乐列表、个人资料、通行密钥、迷你播放器和元数据行均增加 AX 字号布局；欢迎页与公开 AI 作品已在 375pt/390pt/430pt 通过命中区域、元素描述、文字裁切和语义特征系统 audit，三档宽度的欢迎页 Light/Dark 基线已留档；430pt AX5 回归发现的互动按钮与作品元数据横排裁切已修复并通过完整回归；图片验证码仍需要后端提供音频或等价挑战，完整 VoiceOver 手动走查仍需继续。
- Dashboard、MusicHome、CollectionSquare 三个隔离登录后页面已在 375pt 与 430pt 分别通过 Light + 默认字号、Dark + AX5 的多视口 accessibility audit；音乐页在 AX 字号下改用自适应搜索框和纵向统计，收藏夹广场的打开、作者、点赞与收藏语义已拆分。该结果不覆盖 `RootAppView`、真实登录、session 恢复或 Tab 导航集成，Phase 4 的 VoiceOver 与全路由检查仍保持未完成。
- 首页字段级失败语义已收口：收藏、生成进度、推荐、通知与积分拆分为五个独立 `LoadState`，任一请求失败只影响所属区块，并提供原位重试；空态只在对应请求明确成功且为空时出现，绿色“暂时没有需要处理的事项”仅在通知与积分两项都成功、且分别为无未读和余额充足时出现。新增 `-ui-testing-dashboard-failures` 离线 503 场景和五个稳定重试标识，375pt Dark + AX5 已通过 Device Hub 手动启动核验；自动 UI 用例已落地，但本轮 Xcode 27 beta 的 `target-runner` 在断言前崩溃并卡在 `Finalize test log`，需在 runner 恢复后补跑结果证据。
- 账号安全页不再用 `try?` 吞掉 Apple 绑定查询失败：绑定状态改为显式 loading / failed / loaded，状态未知时文案明确说明“暂时无法确认是否已绑定”，同时隐藏绑定与解绑入口，避免把服务故障误呈现为“未绑定”；失败卡片提供原位重试。新增 `-ui-testing-security-failure` 离线 503 场景与 UI 断言，375pt Dark 的默认字号和 AX5 已完成手动启动核验，`build-for-testing` 通过；自动运行结果仍待 Xcode 27 beta runner 恢复后补跑。
- 通知中心已将通知列表、未读总数与已读写入拆分为独立状态：未读计数请求失败时不再回退为 `0` 或把旧值伪装成“已同步”；当前页仍有未读行时显示“有未读通知 · 数量待同步”，列表继续可用。单条与“全部已读”只有在写接口成功后才提交本地已读状态；请求 generation、跨分页保留的已确认 read ID、独立的批量已读 pending 和写入前通知 ID 截止点共同阻止迟到列表或计数回滚操作，同时允许批量操作之后新到的通知保持未读。未读筛选和全部筛选统一进入计数对账，单条写入期间切换筛选后会刷新当前筛选而不是旧筛选。若服务端短暂返回旧状态，页面会从“同步中”转为带“重新同步未读数量”入口的明确待同步状态，不再无限卡住；单条无跳转目标的通知也只触发一次对账刷新。计数对账已收口为纯逻辑模块 `NotificationReadConsistency`，跨页单条已读、批量已读后新通知、空当前页、旧计数重试及服务端最终追平均有确定性单元测试，不再依赖 UI runner 才能证明核心一致性。另有四个离线 UI 场景和对应断言覆盖失败态与可操作性；最终 `build-for-testing` 已通过，503 写入失败路径已完成 Device Hub 手动核验，UI 自动结果待 Xcode runner 恢复后补跑，不计入既有基线。
- 使用帮助的每日示例图不再把收藏状态查询失败解释为“未收藏”：图片内容与收藏关系使用独立 `LoadState`，查询中或失败时禁用收藏操作，失败态显示“暂不可收藏”、产品化错误和单独重试，同时保留下载与原图能力；收藏变更失败会保留上一次已确认状态。新增 `-ui-testing-daily-favorite-failure` 503 场景与 UI 断言，`build-for-testing` 通过，并在 375pt Dark 实际滚动确认失败卡片、禁用态和重试按钮可达。
- 按条件找图不再把每张图片的收藏查询失败折叠成“未收藏”：结果使用按图片 ID 隔离的 `LoadState<Bool>`，发布结果前即进入 loading，最多四路并发并按完成顺序渐进更新；失败项显示“收藏状态未知”和单项重试，更多菜单中的收藏操作保持禁用，旧批次结果通过 revision 丢弃。保存到自定义收藏夹不再误标为默认已收藏，只有实际保存到默认收藏夹才回写 true。新增 `-ui-testing-points-favorite-failure` 离线场景和 UI 断言，`build-for-testing` 通过；375pt Dark 已实际执行找图、检查未知状态卡片与禁用菜单项。
- 随机刷图的“喜欢”状态不再使用缺省 `false`：每张图片按 `pid-p` 保存独立 `LoadState<Bool>`，查询中禁用操作，查询失败显示可点击的“重试状态”，不会误显示“喜欢”；状态查询使用 request ID 丢弃迟到响应，默认收藏写入失败回到未知状态而不是假未收藏。收藏夹回调同时区分默认收藏与自定义收藏，只有实际保存到默认收藏夹才回写“已喜欢”。筛选重载将同一 feed generation 从操作起点贯穿余额、预取、切图、补充队列和喜欢状态查询，旧 continuation 与旧响应均不能覆盖新队列、余额或费用；参数 Sheet 使用本地草稿，取消或下滑关闭不会修改正式筛选，只有通过写入中保护后才原子应用并刷新。解锁或收藏写入期间暂时锁住切图、筛选与刷新，避免可能扣费的旧图请求完成后污染新页面；网络、登录或积分错误也不会再被覆盖为“图片链接无效”。无图片 URL 时不再叠加底部元数据，而是使用包含标题、作者和 VoiceOver 说明的独立空态；极端大字号会降级为紧凑系统标签，从布局结构上消除 AX5 遮挡。已新增 `-ui-testing-random-image-favorite-failure` 503 场景和 `testRandomImageFavoriteFailureDoesNotPretendToBeUnliked`，并扩展 AX5 主操作用例覆盖参数重新应用；最终 `build-for-testing` 已通过，375pt Dark + AX5 已用最终构建实际启动核验，占位态、重试状态和四个主操作均无裁切重叠，自动结果仍待 runner 恢复后补跑。

### Phase 5：回归与发布前验收

- [x] 代码开发范围已完成（2026-07-11）：Phase 1–4 的产品化实现、失败恢复、状态一致性与自动化夹具均已落地；以下未勾选项属于真机、全路由无障碍与发布环境验收，由产品方后续执行，不阻塞本轮代码交付；
- [x] Swift 单元测试（2026-07-11 当前工作树 `swift test --disable-sandbox`：99/99 通过）；
- [x] App 构建（2026-07-11 `generic/platform=iOS Simulator`，App、Core 与 Live Activity Widget 的 arm64/x86_64 双架构构建通过）；
- [x] UI tests 基线（2026-07-11，iOS 27.0：`Setu QA 375` 保留本轮 12/12 完整基线，并在此前页面语义调整后复核新增矩阵 2/2；`Setu QA 390` 保留此前 10/10 完整回归基线；`Setu QA 430` 保留此前 10/10 完整基线，并另行通过新增的 Light 默认与 Dark AX5 两项登录后页面矩阵。本轮后续新增的 Dashboard、账号安全、通知一致性、每日图片、按条件找图与随机刷图失败态用例均不计入上述历史基线；各自的 build、手动核验与待补跑状态以 `docs/qa/ios-product-polish/README.md` 为准，只有 runner 输出完整结果并封口后才更新通过计数）；
- [x] 375/390/430 浅深模式截图对照（欢迎页共 6 张，见 `docs/qa/ios-product-polish/README.md`）；
- [ ] 真机通知、照片权限、Passkey、Apple 登录；
- [ ] 真机后台音乐、耳机中断、Live Activity；
- [x] 积分消费与接口权限自动化回归（后端预览不扣费、主动高清解锁扣费、私有 AI 作品读写越权拒绝、公开作品作者互动限制均已覆盖；真实设备体验仍随 UI tests 与真机项验收）。

开发完成审计（2026-07-11）：

| 范围 | 当前证据 | 结论 |
| --- | --- | --- |
| Phase 1–4 产品化改造 | 各阶段实现清单均已勾选；普通用户错误映射、状态组件、导航闭环、权限预提示、Dynamic Type 与 Reduce Motion 已落到源码 | 代码完成 |
| 异步状态与竞态 | Dashboard 分区状态、收藏显式未知态、随机 feed generation/request ID、通知 `NotificationReadConsistency` 对账均已实现 | 代码完成 |
| 自动化资产 | Swift 99/99；App、Core、Widget、单元测试及 UI 测试目标 `build-for-testing` 成功；离线失败夹具已落地 | 代码完成 |
| 真机与系统能力 | 通知、照片、Apple 登录、Passkey、后台音乐、耳机中断、Live Activity、真实 VoiceOver 手势 | 由产品方后续真机验收 |
| 发布环境 | OSS/CDN 下架和缓存失效 | 需要部署环境验收 |
| 图片验证码等价挑战 | iOS 端无法自行生成安全的等价答案；需要后端先提供音频或其他可访问挑战接口 | 外部接口依赖，不属于本轮 iOS 遗留实现 |

因此“开发工作完成”仅指仓库内可交付的 iOS 实现与测试资产已完成，不代表下方 Definition of Done 的真机、全路由或生产环境验收已经通过。

禁止在一个 PR 中同时重构多个无关业务域；共享组件 PR 必须附至少两个真实调用方，避免提前抽象。

---

## 10. 每项改造的 Definition of Done

一个用户页面只有同时满足以下条件才算完成：

- [ ] 主任务在首屏可理解；
- [ ] 页面最多一个主要 CTA；
- [ ] 普通用户不需要理解后台术语；
- [x] 不显示原始 HTTP、Trace ID、内部状态或数据库 ID；
- [x] 所有消费行为可预期并由用户明确触发；
- [ ] loading、empty、failed、unauthorized、loaded 全覆盖；
- [x] 空态有业务下一步，失败态有恢复动作；
- [ ] 触控目标不小于 44×44pt；
- [ ] Light/Dark 与正常/大字号均无裁切重叠；
- [ ] VoiceOver 能理解主要内容与操作；
- [x] Reduce Motion 下信息仍完整；
- [ ] 375pt 与 430pt 无水平溢出；
- [x] 普通内容流使用增量加载，不使用上一页/下一页；
- [ ] 新增交互有 Preview 或 UI 测试；
- [x] 当前代码的相关 `swift test` / `xcodebuild` 通过（2026-07-11：Swift 99/99、后端 Maven 158/158、Web `typecheck`/`lint` 通过；通用 iOS Simulator App、Core、Live Activity Widget、单元测试与 UI 测试目标的 arm64/x86_64 `build-for-testing` 成功；375pt 保留本轮 12/12 完整基线并在最新页面语义调整后复核新增矩阵 2/2，390pt 保留 10/10 基线，430pt 保留 10/10 基线并通过新增 2/2 页面矩阵）。

---

## 11. 验证矩阵

### 11.1 模拟器

| 维度 | 最低覆盖 |
| --- | --- |
| 尺寸 | 375pt、390pt、430pt |
| 外观 | Light、Dark |
| 字号 | 默认、XXL、AX5 |
| 对比度 | 默认、Increase Contrast |
| 动效 | 默认、Reduce Motion |
| 网络 | 正常、离线、超时、5xx |
| 会话 | 未登录、已登录、401 过期 |
| 内容 | 空、少量、大量、超长文本 |

### 11.2 真机

以下能力不能仅靠模拟器验收：

- Sign in with Apple；
- Passkey 与 Associated Domains；
- APNs 权限、注册和深链；
- Live Activity push token；
- 照片保存权限与有限照片访问；
- 后台音乐、锁屏控制、耳机拔出和系统中断；
- 实际积分消费、防重复扣费；
- 上游图片、音乐 URL 过期与 Range 行为。

### 11.3 基础命令

```bash
swift test

xcodebuild \
  -project SetuIOSApp.xcodeproj \
  -scheme SetuIOSApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build
```

若本机没有指定模拟器，使用 `xcrun simctl list devices available` 选择现有设备，不应为此修改项目配置。

Xcode 27 beta 已移除独立的 `Simulator.app`，因此 `open -a Simulator` 会失败。可在启动目标设备后打开 Xcode beta 内置的 Device Hub：

```bash
xcrun simctl list devices available
xcrun simctl boot <UDID>
open /Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app
```

---

## 12. 后续开发记录规则

每个实现 PR 应在描述中包含：

1. 对应任务 ID，例如 `P0-2`；
2. 改变的用户行为；
3. 未改变的后端契约；
4. Light/Dark 与尺寸验证截图；
5. Dynamic Type / VoiceOver 说明；
6. 已运行的测试；
7. 仍需真机验证的项目。

完成某项后更新本文 checkbox；若设计决策发生变化，应先更新本文，再实现代码，避免文档与行为长期偏离。

---

## 13. 参考

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple/)
- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- `ios-soft-pink-ui-design.md`
- `ios-functional-experience-spec.md`
- `backend-mobile-contract.md`
- `passkey-associated-domains.md`
