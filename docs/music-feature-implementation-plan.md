# 音乐功能优化实施计划

更新时间：2026-07-08
范围：`setu_ios` 音乐区（播放引擎已完成自动连播 / 播放模式 / 锁屏遥控 / 中断处理 / 后台播放能力声明）。本计划覆盖下一阶段：封面显示 Bug 修复、播放页体验升级、歌词、播放列表与搜索打磨。
参考：[Cymusic](https://github.com/gyc-12/Cymusic)（React Native / Expo，1.5k star）。**只借鉴设计风格与交互思路，不复制实现**——其核心可取处：向 Apple Music 看齐的动效细节、滚动歌词与字号调节、睡眠定时、缓存标识、音质回退链、多选批量操作。
关联文档：`ios-soft-pink-ui-design.md`（视觉系统）、`ios-functional-experience-spec.md`（功能体验准则）。

---

## P0 · 封面显示 Bug 修复（已定位根因）

### 根因
1. **ATS 拦截 HTTP 封面**：`MusicModels.swift` 中播放地址已做 `http://` → `https://` 升级（L244），但 `coverURLString`（L69）原样返回 `picUrl ?? album?.picUrl ?? al?.picUrl`。网易云图片地址经常是 `http://pX.music.126.net/...`，App Transport Security 默认静默拦截明文 HTTP —— 这正是「部分封面不显示」的原因：HTTP 的失败、HTTPS 的正常。
2. **`AsyncImage` 无缓存无重试**：全 App 19 处 `AsyncImage`，共享 `URLCache` 默认容量小，列表滚动反复重取，弱网下失败后永远停在占位图。
3. **锁屏无封面**：`MusicPlaybackController` 从未设置 `MPMediaItemPropertyArtwork`。

### 修复任务
| # | 任务 | 位置 |
| --- | --- | --- |
| 0.1 | 新增 `secureURLString(_:)` 工具：`http://` → `https://`；`coverURLString` 与 `PlaylistSong.coverUrl` / `MusicHistoryRecord.coverUrl` / `MusicPlaybackTrack.coverURLString` 读取处统一走它 | `SetuIOSCore/Core/Models/MusicModels.swift` |
| 0.2 | 网易云封面追加尺寸参数 `?param=400y400`（列表 54pt 缩略图用 `?param=200y200`），显著降流量提速 | 同上（计算属性内做，不动存储字段） |
| 0.3 | `MusicArtworkView` 升级：基于 `URLSession` + 放大的共享 `URLCache`（内存 64MB / 磁盘 256MB）自建轻量 `RemoteArtworkLoader`，失败自动重试一次，支持点击重试；淡入过渡 | `Features/Music/MusicHomeView.swift` 抽到独立文件 `Features/Music/MusicArtworkView.swift` |
| 0.4 | 锁屏封面：播放时异步取封面 → `MPMediaItemPropertyArtwork`，取到前先显示无图信息，复用 0.3 的缓存 | `MusicPlaybackController.updateNowPlaying` |

验收：构造含 `http://` 封面的歌单数据，全部正常显示；断网→恢复后可重试加载；锁屏出现封面；`swift test` 通过（`secureURLString` 与 param 拼接加单测）。

---

## P1 · 播放页体验升级（Cymusic 风格启发）

### 1A · 全屏 Now Playing 重构
现状是 `List` + 卡片的「表单感」页面；目标是沉浸式播放页（呼应 `ios-soft-pink-ui-design.md` §7.4）：
- 大封面居中（约 78% 宽），播放中轻微放大、暂停时缩小的弹簧动效（Apple Music 式）。
- 背景用封面主色提取（`UIImage` 平均色/双色渐变）+ 樱云粉叠加，深浅模式各自适配。
- 控制区：模式切换 · 上一首 · 播放/暂停（大圆钮）· 下一首 · 队列入口，一排五控件；进度条含可拖拽把手与缓冲指示。
- 次操作行：收藏到歌单、下载（已有签名下载）、睡眠定时、分享。
- 手势：下滑收起回 mini bar；左右滑切歌。

### 1B · 同步滚动歌词
现状歌词是整段 `Text` 平铺。目标：
- 解析 LRC 时间戳（`[mm:ss.xx]`）为 `[(time, line)]`，随播放进度高亮当前行并自动居中滚动。
- 点击任意行 seek 到对应时间；翻译歌词逐行对照显示。
- 字号三档调节（借鉴 Cymusic）；查看歌词时屏幕常亮开关（`isIdleTimerDisabled`，退出页面必须恢复）。
- 无时间戳歌词降级为整段展示（保留现状为 fallback）。
- 新文件：`Features/Music/LyricParser.swift`（纯函数，进 `swift test`）+ `LyricScrollView.swift`。

### 1C · Mini Bar 强化
- 收起态加「下一首」按钮；左右滑动切歌、上滑展开全屏播放页。
- 缓冲/错误状态沿用现有 `playbackStatusRow` 样式。

---

## P2 · 播放健壮性与工具

| # | 任务 | 说明 |
| --- | --- | --- |
| 2.1 | 音质回退链 | 形式化 `exhigh → standard` 回退（现散在两处调用点各写一遍 level）：`resolveTrackURL` 内先试高音质、失败自动降级，UI 提示「已切换标准音质」。借鉴 Cymusic 的 quality fallback。 |
| 2.2 | 自动连播补记历史 | 目前仅手动点播记录播放历史；`advance(by:isAuto:)` 成功后调用 `musicClient` 记录（Core 补 `addHistory` 轻量接口）。 |
| 2.3 | 睡眠定时 | 15/30/60 分钟与「播完本曲」，到时淡出暂停；控制器内 `Task.sleep` 实现，播放页次操作行入口。 |
| 2.4 | 队列管理 | 队列弹层支持拖拽排序、滑动移除、清空；「下一首播放」（插队）操作。 |

---

## P3 · 音乐首页与搜索打磨

- **首页信息架构**：顶部搜索框 → 「最近播放」横滑卡（新增，取播放历史前 N）→ 我的歌单网格 → 热门搜索标签流（现有能力重排，呼应 UI 文档 §7.4）。
- **搜索**：歌曲/歌手/专辑分段（借鉴 Cymusic 的搜索分离）；分页加载更多保留；搜索历史胶囊可单条删除。
- **歌单页批量操作**：多选模式（批量移除、批量加入其它歌单），选中计数常驻底部操作条（呼应 web 端 guideline 的 batch 模式）。
- **缓存标识**（可选，Cymusic 启发）：已下载歌曲在列表显示小图标；下载管理入口列出本地文件与占用。

---

## 实施顺序与验收

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| P0（先行，半天） | 0.1–0.4 封面修复 | 上文验收项 + `swift test` |
| P1A/1C（1–2 天） | 播放页重构 + mini bar | 390pt 无溢出；深浅模式；Reduce Motion 降级动效 |
| P1B（1 天） | 歌词解析与滚动 | LRC 解析单测（含无时间戳/乱序/毫秒位数变体）；点击 seek 生效 |
| P2（1–2 天） | 2.1–2.4 | 高音质失败自动降级可复现；自动连播产生历史记录；定时器到点暂停 |
| P3（1–2 天） | 首页/搜索/批量 | 分段搜索正确分页；批量操作有确认与撤销路径 |

通用约束：
- 遵守 `AGENTS.md`：先 Core（模型/Client + 单测）后 UI；受保护请求继续走 `SID` + HMAC；用户可见文案中文。
- 视觉全部走 `Setu*` 设计系统组件与 token，不新增裸色值。
- 每阶段 `xcodegen generate`（如项目结构变化）+ 模拟器构建通过；真机验证项（锁屏封面、后台连播、睡眠定时熄屏行为）单独列入手动清单。

## 明确不做（本轮）
- 不做本地完整离线音乐库 / 自定义音源导入（Cymusic 的 JSON 音源机制与本产品后端代理模式冲突）。
- 不改后端音乐接口契约；`REMOTE_URL` 播放模式与上游 Range 行为维持现状。
- 不做跨设备播放同步。
