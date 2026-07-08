# 雪涼云 iOS 樱云（Soft Pink）UI 设计方案

本文档面向 `setu_ios` 原生 App，提出一套「柔和粉」（Soft Pink）视觉系统，并给出每个功能页面的结构重构规划与落地步骤。目标是把当前「像设置页的系统 List」升级为「有品牌感、以内容为中心的创作型 App」。

- 适用范围：`Sources/SetuIOSApp` 全部界面；管理后台采用同一套 token 但保持信息密度。
- 不改动：后端契约、认证语义（`SID` Cookie + `signSecret` HMAC）、功能行为与路由结构。本方案只重构视觉与页面结构。
- 设计代号：**樱云 / Sakura Cloud**。

---

## 1. 现状诊断

| 问题 | 现状 | 影响 |
| --- | --- | --- |
| 无设计系统 | 颜色散落硬编码（`.pink` / `.purple` / `.blue` / `.green` / `.red`），仅 `RootAppView` 设了 `.tint(.pink)` | 品牌不统一，粉色只体现在 tint 上 |
| 全站默认 List | 所有页面都是 `.insetGrouped` 分组列表 | 观感像系统「设置」，缺乏产品个性 |
| 组件重复 | `HomeActionRow`、`FeatureRow`、`HubHeroRow`、`HubNavigationRow` 四种近似的「图标+标题+副标题+chevron」行 | 间距 / 字重 / 图标尺寸不一致，维护成本高 |
| 内容表现弱 | 图片类内容（AI 作品、收藏、广场）用小图标行或小缩略图 | 图片型 App 却没有以图为主的版式 |
| 缺少层级语言 | 无统一的卡片、渐变、阴影、圆角、间距刻度 | 页面「平」，重点不突出 |

**结论**：先建立 token + 组件库，再自上而下替换页面。视觉统一由「共享组件」保证，而不是逐页手改颜色。

---

## 2. 设计原则

1. **柔和优先**：粉色是氛围色而非警示色。饱和度克制，大面积用浅粉底 + 白卡片，强调处才用玫瑰粉渐变。
2. **内容为王**：图片、作品、歌曲封面是主角，UI 退居其次。缩略图更大、圆角更柔、留白更多。
3. **一处定义，处处复用**：所有颜色 / 字体 / 间距 / 圆角来自 token；页面只组合 `Setu*` 组件，不再写裸 `Color`。
4. **原生手感**：继续用 `NavigationStack` / `TabView` / `List`（`.plain` + 自绘卡片），保留系统手势、Dynamic Type、深色模式、VoiceOver。
5. **深浅双模等价**：每个 token 都提供 light/dark 值，深色为「暖李子」底而非纯黑，保持柔和调性。

---

## 3. 色彩系统

建议用 **Asset Catalog Color Set**（每个色带 Any/Dark 两套）落地，代码里通过 `Color("brand/pink")` 或封装 `SetuColor` 访问。下表为参考值，可微调。

### 3.1 品牌与强调

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `brandPink` | `#E45C8C` | `#F58EB4` | 主强调 / 可交互元素 / tint |
| `brandInk` | `#C42B66` | `#F7A9C6` | 粉色系正文强调、需要对比的小字 |
| `brandSoft` | `#F9B5CE` | `#5A2A3E` | 浅粉填充（chip、进度槽、选中态底） |
| `brandGradientTop` | `#FFB6CE` | `#7A3355` | Hero 渐变起点 |
| `brandGradientBottom` | `#F27CA6` | `#B24C7C` | Hero 渐变终点 |

Hero 渐变：`LinearGradient(top→bottom, .brandGradientTop → .brandGradientBottom)`，用于首页问候卡、各 Tab 顶部主入口、主要 CTA。

### 3.2 背景与表面

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `bgBase` | `#FFF6F9`（樱花白） | `#171013`（暖李子黑） | 页面根背景（渐变到 `#FFFFFF` / `#1E1418`） |
| `surface` | `#FFFFFF` | `#211519` | 卡片 / 行背景 |
| `surfaceMuted` | `#FDEEF4` | `#2B1D23` | 次级卡片、分组底、输入框 |
| `separator` | `#F2DBE4` | `#3A2A31` | 分隔线、卡片描边 |

### 3.3 文字

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `textPrimary` | `#2A1E24` | `#F6E9EF` | 标题 / 正文 |
| `textSecondary` | `#7A6A72` | `#C4A9B5` | 副标题 / 说明 |
| `textTertiary` | `#B3A4AC` | `#8A7580` | 占位 / chevron / 次要图标 |

### 3.4 语义色（柔和版）

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `success` | `#3FA986` | `#6FD3A6` | 成功、在线、已通过 |
| `warning` | `#DB9450` | `#EBB06A` | 待处理、审核中 |
| `danger` | `#E06277` | `#F0899A` | 失败、删除、封禁（比系统红更柔） |
| `info` | `#6E97D6` | `#93B4E8` | 提示、次要状态 |

> 原则：状态色仅用于「文字 / 图标 / 小色块 / pill」，不做大面积填充，避免破坏粉色基调。

### 3.5 SwiftUI 访问封装

```swift
// DesignSystem/Theme/SetuColor.swift
import SwiftUI

enum SetuColor {
    static let brandPink = Color("brand/pink")
    static let brandInk = Color("brand/ink")
    static let brandSoft = Color("brand/soft")
    static let gradientTop = Color("brand/gradientTop")
    static let gradientBottom = Color("brand/gradientBottom")

    static let bgBase = Color("bg/base")
    static let surface = Color("bg/surface")
    static let surfaceMuted = Color("bg/surfaceMuted")
    static let separator = Color("bg/separator")

    static let textPrimary = Color("text/primary")
    static let textSecondary = Color("text/secondary")
    static let textTertiary = Color("text/tertiary")

    static let success = Color("state/success")
    static let warning = Color("state/warning")
    static let danger = Color("state/danger")
    static let info = Color("state/info")

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [gradientTop, gradientBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
```

---

## 4. 字体、间距、圆角、阴影

全部基于系统字体（SF Pro）与 Dynamic Type，只做语义封装，禁止写死 `.system(size:)`。

### 4.1 字体角色

| 角色 | 基准 | 用途 |
| --- | --- | --- |
| `display` | `.largeTitle.weight(.bold)` | 页面主标题、问候语 |
| `title` | `.title3.weight(.semibold)` | 卡片标题、Section 大标题 |
| `headline` | `.headline` | 行标题 |
| `body` | `.body` | 正文 |
| `caption` | `.footnote` / `.caption` | 副标题、说明 |
| `metric` | `.title2.weight(.semibold).monospacedDigit()` | 数字指标（积分、计数） |

### 4.2 间距刻度（`SetuSpacing`）

`xs=4`、`sm=8`、`md=12`、`lg=16`、`xl=20`、`xxl=28`。卡片内边距默认 `lg`，卡片间距默认 `md`，页面左右安全边距 `lg`。

### 4.3 圆角（`SetuRadius`）

`sm=12`（chip / 小控件）、`md=18`（标准卡片 / 缩略图）、`lg=24`（Hero / 大图）、`pill=Capsule`。

### 4.4 阴影 / 描边

- 卡片默认：`surface` 底 + 1px `separator` 描边 + 极柔粉色投影 `color: brandPink.opacity(0.10), radius: 12, y: 6`。
- 深色模式：去投影，仅保留描边（避免发灰）。
- Hero / CTA：`brandPink.opacity(0.28), radius: 18, y: 10`。

```swift
// DesignSystem/Theme/SetuMetrics.swift
enum SetuSpacing { static let xs=4.0, sm=8.0, md=12.0, lg=16.0, xl=20.0, xxl=28.0 }
enum SetuRadius  { static let sm=12.0, md=18.0, lg=24.0 }
```

---

## 5. 组件库

新增目录 `Sources/SetuIOSApp/DesignSystem/`，页面只用这些组件拼装。以下为核心清单（附关键实现示意）。

| 组件 | 作用 | 替换现有 |
| --- | --- | --- |
| `SetuBackground` | 页面根渐变背景 modifier（`scrollContentBackground(.hidden)` + `bgBase` 渐变） | 各页 `.systemGroupedBackground` |
| `SetuCard` | 标准卡片容器（圆角+描边+柔影） | 裸 `Section` 视觉 |
| `SetuHeroCard` | 渐变主入口卡（图标+标题+副标题+箭头） | `HubHeroRow` / `HomeActionRow` |
| `SetuNavigationRow` | 统一导航行（粉色图标+标题+副标题+chevron） | `FeatureRow` / `HubNavigationRow` |
| `SetuStatTile` | 指标磁贴（图标+数值+标签），可横向排布 | `DashboardMetricRow` |
| `SetuSectionHeader` | 带小标题+可选「查看全部」的分区头 | 裸 `Section header` |
| `SetuPill` | 状态 / 标签 pill（语义色） | 散落的 `Capsule` 背景 |
| `SetuPrimaryButton` | 渐变主 CTA（生成、登录、播放全部） | `borderedProminent` |
| `SetuImageTile` | 统一圆角缩略图 + 加载/失败占位 + 角标 | `ImageThumbnailView` 包装 |
| `SetuEmptyState` | 品牌化空 / 错 / 加载态 | 散落的 `ContentUnavailableView` |

### 5.1 示例：`SetuCard` 与 `SetuBackground`

```swift
struct SetuCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(SetuSpacing.lg)
            .background(SetuColor.surface, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1))
            .shadow(color: SetuColor.brandPink.opacity(0.10), radius: 12, y: 6)
    }
}

extension View {
    func setuBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(
                LinearGradient(colors: [SetuColor.bgBase, SetuColor.surface],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
    }
}
```

### 5.2 示例：`SetuHeroCard`（渐变主入口）

```swift
struct SetuHeroCard: View {
    let title: String, subtitle: String, systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: SetuSpacing.lg) {
                Image(systemName: systemImage).font(.title).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm))
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.footnote).opacity(0.9)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(SetuSpacing.xl)
            .background(SetuColor.heroGradient, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
            .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }
}
```

> 迁移策略：先让上述组件**在 `List` 里作为无背景 row 使用**（`.listRowBackground(.clear)` + `.listRowSeparator(.hidden)`），即可在不重写页面骨架的前提下换脸；后续再按需改为 `ScrollView` 布局。

---

## 6. 全局外壳（App Shell）

| 元素 | 方案 |
| --- | --- |
| TabBar | 保留 5 个原生 Tab；`.tint(SetuColor.brandPink)`；`UITabBar` 外观设为半透明毛玻璃、选中色粉、未选中 `textTertiary`。 |
| 导航栏 | `UINavigationBar` 大标题用 `textPrimary`；返回 / 按钮 tint 粉色；标题栏透明融入 `bgBase`。 |
| 页面背景 | 统一 `.setuBackground()`，`List` 用 `.plain` + 清空 row 背景，靠 `SetuCard` 分块。 |
| 迷你播放条 `MusicMiniPlayerBar` | 改为浮在 TabBar 上方的圆角玻璃卡：封面圆角、标题跑马灯、播放/暂停粉色圆钮、细进度条。 |
| 加载态（session 确认） | 用品牌化 `SetuEmptyState`（粉色 `ProgressView` + 文案）替换裸 `ProgressView`。 |

---

## 7. 功能页面结构规划

按当前路由（`AppRoute` / `AppTab`）逐区规划。每页给出**版式结构**与**关键组件**。行为、接口、分页逻辑保持不变。

### 7.1 首页 · 仪表盘（`DashboardView`）
- **问候 Hero**：顶部渐变卡（`SetuHeroCard` 变体）——按时段问候 + 头像 + 「积分」chip + 未读铃铛角标。替换现在纯文字标题区。
- **今日状态**：3 个 `SetuStatTile` 横排（积分余额 / 未读通知 / 今日刷图），数字用 `metric` 字体。替换 `DashboardMetricRow`。
- **主要功能**：2×2 `SetuHeroCard` 网格（AI 绘画 / 随机图片 / 音乐 / 广场），每格独立小渐变或语义色。替换 `HomeActionRow` 列表。
- **继续使用 / 我的内容**：`SetuCard` 分组内用 `SetuNavigationRow`。
- **最近刷图记录**：`SetuCard` 内时间线样式行 + 状态 `SetuPill`（成功=success / 失败=danger），保留分页控件但按钮改胶囊。

### 7.2 AI 绘画 Tab
- **AiHubView**：顶部 `SetuHeroCard`「开始绘画」；「我的创作」「公开内容」用 `SetuNavigationRow` 卡组。
- **AiDrawView（创作页，重点）**：改为分区卡片表单——① 提示词卡（多行输入 + 翻译按钮 + 字数）；② 参数卡（尺寸 / 模型用 `SetuPill` 选择器、Seed）；③ 资产卡（LoRA / 角色 / 风格入口，选中项以缩略图 chip 呈现）；④ 底部固定 `SetuPrimaryButton`「生成」+ 消耗提示；⑤ 生成中用进度卡 / Live Activity 呼应。
- **AiHistoryView / AiSquareView**：从列表改为**两列图片网格**（`LazyVGrid` + `SetuImageTile`），状态 pill 叠在图角，点击进详情；保留状态筛选为顶部 `SetuPill` 横向条。
- **AiGenerationDetailView**：大图 Hero + 参数信息 `SetuCard`（Seed / 模式 / 尺寸 / Checkpoint）+ 底部操作条（复用参数 / 下载 / 公开 / 删除申请）。

### 7.3 图片 Tab
- **ImageHubView**：`SetuHeroCard`「随机图片」；积分概览改 `SetuStatTile` + 进度环（当前积分 / 单次消耗）；工具区 `SetuNavigationRow` 卡组。
- **RandomImageSwipeView（刷图，重点）**：全屏沉浸卡片流，图片圆角大图；右下浮层三枚粉色玻璃圆钮（收藏 / 信息 / 下一张）；顶部轻量参数入口。强化「刷」的爽感。
- **PointsCallView / PointsLogsView / GalleryUpload***：表单与列表用 `SetuCard` 承载；投稿进度、批次状态用 `SetuPill`；上传选图预览用 `SetuImageTile` 网格。

### 7.4 音乐 Tab
- **MusicHomeView**：顶部固定搜索框（圆角、粉色光标）；热门搜索 / 搜索历史用 `SetuPill` 流式标签；歌单预览横向卡片。
- **播放态 / 迷你条**：见 §6，粉色渐变 Now Playing，封面大圆角、歌词卡。
- **MusicPlaylists / History / PlaylistDetail**：歌单封面网格 + 曲目 `SetuNavigationRow`（封面缩略 + 标题 + 时长），破坏性操作（删除 / 清空）确认弹窗用 `danger`。

### 7.5 广场 Tab
- **SquareHubView**：顶部渐变 `SquareLandingHeader`（两枚入口按钮，主按钮用 `SetuPrimaryButton`）；「收藏夹广场 / AI 广场」横向预览用 `SetuImageTile` 卡片（现有卡片升级圆角+柔影）；分区头用 `SetuSectionHeader`（带「查看全部」）。
- **CollectionSquare / AiSquare / 详情 / 公开主页**：统一两列图片网格 + `SetuPill`（点赞 / 收藏计数），公开用户主页加头像 Hero。

### 7.6 账号与设置区
- **AccountView（登录/注册/找回）**：品牌化认证页——顶部 Logo + 樱云渐变背景，输入卡片，`SetuPrimaryButton` 主操作，次操作文字链粉色。
- **ProfileView**：头像 Hero 卡（可点更换）+ 昵称 / 资料编辑 `SetuCard`。
- **UserHub / 设置类（Passkey、QQ 绑定、安全、文档、关于、隐私）**：`SetuNavigationRow` 卡组，图标统一粉色；静态阅读页用 `body` 排版 + 舒适行距。
- **NotificationsView**：列表卡，未读粉点 + 类型 `SetuPill`，已读态降饱和。
- **SystemStatusView**：状态卡按健康度着语义色（success / warning / danger），指标用 `SetuStatTile`。

### 7.7 管理后台（Admin）
- 原则：**沿用同一 token，但保持信息密度**，不追求华丽。
- **AdminOverviewView**：改为指标磁贴网格（`SetuStatTile`）+ 模块入口 `SetuNavigationRow` 卡组。
- 数据型列表（用户 / 黑名单 / 审核 / 日志等）：保留紧凑行，但用 `separator`、状态 `SetuPill`（在线/离线、通过/拒绝、封禁）、粉色主操作；批量操作栏浮底。
- 破坏性操作（封禁、删除、下架）一律 `danger` 色 + 二次确认，避免误触。

---

## 8. 落地实施计划

分阶段推进，每阶段可独立编译、独立验收；靠共享组件保证「改一处、全站生效」。

- **Phase 0 · Tokens**：新建 `DesignSystem/Theme/`（`SetuColor`、`SetuTypography`、`SetuSpacing`、`SetuRadius`）+ Asset Catalog 颜色集（每色 light/dark）。
- **Phase 1 · 组件库**：实现 §5 全部 `Setu*` 组件 + `.setuBackground()`；配置 `UITabBar` / `UINavigationBar` 外观。
- **Phase 2 · 外壳与首页**：`RootAppView` tint/背景、`MusicMiniPlayerBar` 重构、`DashboardView` + 三个 Hub 页迁移（先在 `List` 内换组件，低风险）。
- **Phase 3 · 核心功能页**：`AiDrawView`、`RandomImageSwipeView`、音乐播放态、AI/广场图片网格（此阶段涉及从 `List` 转 `ScrollView`/`LazyVGrid`）。
- **Phase 4 · 账号与系统页**：Account/Profile/设置类、Notifications、SystemStatus、静态页。
- **Phase 5 · 管理后台**：统一 token 与状态 pill，磁贴化 Overview。

建议目录：
```
Sources/SetuIOSApp/DesignSystem/
├── Theme/     SetuColor.swift  SetuTypography.swift  SetuMetrics.swift
└── Components/ SetuCard.swift  SetuHeroCard.swift  SetuNavigationRow.swift
              SetuStatTile.swift  SetuSectionHeader.swift  SetuPill.swift
              SetuPrimaryButton.swift  SetuImageTile.swift  SetuEmptyState.swift
              SetuBackground.swift
Assets.xcassets/  brand/*  bg/*  text/*  state/*  (Color Sets, Any + Dark)
```

---

## 9. 验收与可访问性

- **对比度**：正文 / 图标对背景 ≥ 4.5:1，大字 / 大图标 ≥ 3:1；`brandPink` 作小字时改用 `brandInk`。
- **深浅模式**：逐页对照 light/dark，深色不出现纯黑纯灰、投影不发脏。
- **Dynamic Type**：放大到 XXL 不裁切、不重叠；卡片高度自适应。
- **触控目标** ≥ 44×44pt；`SetuHeroCard` / 圆钮满足。
- **Reduce Motion**：渐变 / 卡片动效在开启时降级为无动画。
- **VoiceOver**：换脸时保留现有 `accessibilityLabel`，图片磁贴补充语义标签。
- **尺寸检查**：iPhone SE(375) 与 Pro Max(430) 两档，检查溢出、空/错/载/未授权态。

---

## 10. 参考

- 现有导航与页面清单：`RootAppView.swift`、`AppRoute.swift`。
- 功能覆盖来源：`docs/frontend-feature-map.md`。
- 基础工程约定：`docs/ios-app-foundation-plan.md`、根 `README.md`。
- 本方案只涉及 `setu_ios` 视觉层，不改动后端契约与认证语义（见工作区 `docs/agents/`）。
