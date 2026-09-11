# 亦可 YK iOS

**亦可 YK（原雪涼云）** 的 SwiftUI 原生 iPhone 客户端。品牌英文标识为 **YIKE**，简称 **YK**，主屏幕显示名称为「亦可 YK」。

这不是 Web 套壳。图片、音乐、AI 绘画、收藏、账户和管理后台都是原生界面，连接亦可自己的 API 服务。

当前公开版本：**[YK-v1.0.0-alpha.2](https://github.com/yoshino-xiao7/setu_ios/releases/tag/YK-v1.0.0-alpha.2)**。这是源码发布，**只提供源码**，不附带 ipa、xcarchive 或 TestFlight 包。工程内部开发版本号仍为 `1.1 (5)`。

## 本次 Alpha 说明

- 目标：把现有 iOS 客户端完整功能以源码形式公开，方便核对范围、自行编译和后续按流程发版。
- 形态：GitHub Release 仅含源码压缩包（zip / tar.gz）。
- 使用：需要自己用 Xcode 编译；未提供签名好的安装包。
- 后续版本：必须走 [发布流程](docs/release-process.md)。`alpha` / `beta` / `rc` 一律只发源码。

最低系统：**iOS 17**。界面语言为简体中文。

---

## 应用功能

底部五个 Tab：**首页**、**AI 绘画**、**图片**、**音乐**、**更多**。未登录可以先浏览「更多」里的公开内容；登录后同步收藏、积分、画图历史和个人资料。

### 登录与账户

欢迎页提供：

- 邮箱登录、注册、找回密码（邮件里带网页链接和 iOS 可粘贴重置码）
- Sign in with Apple
- 通行密钥（Face ID / Touch ID / 设备密码）
- 未登录先浏览更多

登录后，「我的」里可以管理：

| 功能 | 说明 |
|---|---|
| 个人资料 | 头像、昵称、账号信息 |
| QQ 绑定 | 邮箱验证码绑定 QQ；AI 绘图队列和完成通知会发到该 QQ。需先添加 bot QQ `2830323446` |
| 修改密码 | 更新登录密码 |
| 通行密钥 | 查看、重命名、删除已绑定的 Passkey |
| 积分 | 查看余额，按积分调用图片 |
| 积分明细 | 获得与消耗记录 |
| API Key | 创建、重命名、禁用、删除，给外部调用使用 |
| 通知中心 | 生成结果、处理进度等站内通知 |
| 音乐缓存 | 缓存占用与自动缓存 |
| 图片显示 | 预览薄雾效果、是否在首页展示推荐 |
| 使用帮助 / 隐私政策 / 服务条款 / 关于亦可 | 产品说明与规则 |

会话使用 HttpOnly `SID` Cookie，请求签名密钥保存在 Keychain，不会在设备上保存账号密码。

### 首页

登录后的起点：

- 问候与账号入口、通知铃铛
- 继续上次未完成的事：正在播放的歌、进行中的 AI 绘画、未提交的绘画草稿
- 最近收藏的图片
- 今日 AI 推荐（可在图片显示设置里关闭）
- 未读通知和积分不足提醒

### AI 绘画

用中文描述想画的内容，可选风格、角色、画幅和高级参数，提交后进入云端队列。

- 自然语言提示词，可翻译成正向 / 反向提示词
- 选择画幅比例、步数、CFG、checkpoint / LoRA / 角色预设
- 单人模式或双人模式
- 草稿会自动保存，离开页面不会丢
- 生成历史、作品详情、删除申请
- AI 绘画广场：浏览、点赞、收藏别人的公开作品
- 素材管理
- 生成过程可用 Live Activity 和系统通知跟踪进度
- 绑定 QQ 后，队列和完成通知也会发到 QQ

生成会消耗积分。取消勾选或停用的画风不会再写进实际生成提示词。

### 图片

面向日常浏览，不是后台控制台。

- **随机刷图**：上下左右滑动换图；可按内容级别、数量、关键词、标签、尺寸、是否排除 AI 图筛选
- **收藏**：一键收藏到默认收藏夹，或选自己的收藏夹
- **Pixiv 作品浏览**：绑定 Pixiv 后浏览、收藏作品；可选择图床
- **收藏夹**：创建多个收藏夹，设公开 / 私有，查看公开用户主页
- **收藏夹广场**：发现别人公开的收藏夹
- **图库投稿**：把图片提交到图库并跟踪审核状态
- **图片删除申请**：对图库内容提交删除并查看进度
- **积分调用**：按积分取图，查看消耗
- 管理员可从图片页导入 PID

图片版权归原作者（来源以 Pixiv 等站点为准），应用提供检索、浏览和收藏。

### 音乐

基于网易云音乐能力的原生播放器。

- 搜索歌曲、歌手、专辑
- 首页推荐：日推、新歌、热搜、推荐歌单
- 排行榜、新碟、私人 FM
- 我喜欢的歌曲、收藏的歌单、自建歌单（创建、删除、加歌、移歌）
- 播放历史
- 歌手 / 专辑 / 歌单详情
- 底部迷你播放器、正在播放页、队列、歌词（含逐字歌词）
- 后台播放、锁屏信息、远程控制、AirPlay
- 音频缓存与自动缓存，暂停后再播可续上已缓存部分
- 部分歌曲支持 MV

音乐版权归网易云音乐及原版权方。

### 更多

「更多」是内部功能页入口，不占用底部主 Tab。

**广场**

- 收藏夹广场预览与全部列表
- AI 绘画广场预览与全部列表
- 我的收藏夹、默认收藏

**ASMR**

- 从 asmr.one 浏览音声作品
- 作品详情、音轨播放
- 按登录用户隔离的收藏
- 观看历史（最多保留最近 100 部）

**JM 本子**

- 从禁漫天堂浏览目录、搜索
- 本子详情与分话阅读
- 按登录用户隔离的收藏
- 观看历史（最多保留最近 100 部）
- 阅读进度会记在模块观看历史上

### 管理员

仅管理员账号在「我的」里能打开管理员模式。普通用户看不到这些入口。

- 后台概览：调用量、用户数、图库与 AI 生成统计
- 用户管理、IP 黑名单
- 系统监控
- 网易云 Token 状态
- Pixiv 抓取 / PID 导入任务
- 图片审核、图库投稿审核、删除申请
- AI 生成记录、Worker、审核队列、AI 删除申请
- 操作日志
- 会话故障排查

---

## 系统要求与权限

| 项目 | 说明 |
|---|---|
| 系统 | iOS 17 或更高 |
| 设备 | iPhone（工程 `TARGETED_DEVICE_FAMILY` 为 1） |
| 登录 | 邮箱、Apple、通行密钥 |
| 通知 | 生成完成等推送；首次画图时会说明用途 |
| 照片 | 保存图片到相册时申请 |
| 后台音频 | 音乐 / ASMR 后台播放 |
| Live Activities | AI 绘画进行中状态 |
| 关联域名 | 通行密钥与 Apple 登录相关能力需正确配置 |

真机运行需要开发者签名。APNs、Associated Domains、后台播放等按对应文档配置后再做设备验证。

## 从源码构建

开始前按 [AGENTS.md](AGENTS.md) 核验 `main`：

```bash
git status --short
git worktree list
git fetch origin main
bash scripts/check-baseline.sh
```

Pixiv 原生传输依赖见 [PixivTransport](Native/PixivTransport/README.md)。

```bash
# 单元测试（不启动模拟器）
swift test

# 由 project.yml 生成 Xcode 工程（不要手改 pbxproj）
xcodegen generate

# 编译 iOS 模拟器版本
xcodebuild -project SetuIOSApp.xcodeproj -scheme SetuIOSApp \
  -destination 'generic/platform=iOS Simulator' build
```

DEBUG 构建可用环境变量 `SETU_API_BASE_URL` / `SETU_SITE_BASE_URL` 指向本地后端；正式地址仍是默认生产配置。

## 仓库结构

| 路径 | 说明 |
|---|---|
| `Sources/SetuIOSApp` | 页面、导航、设计组件、资源 |
| `Sources/SetuIOSCore` | 网络客户端、认证、模型，不含 UI |
| `Sources/SetuIOSLiveActivityWidget` | Live Activity 扩展 |
| `Tests/SetuIOSAppTests` | 单元测试 |
| `Native/PixivTransport` | Pixiv 原生传输（Rust xcframework） |
| `project.yml` | XcodeGen 工程 |
| `Package.swift` | SwiftPM |
| `docs` | 方案、契约、ADR、[发布流程](docs/release-process.md) |
| `docs/releases` | 每个 GitHub Release 的说明原文 |

Bundle ID：应用 `icu.yukiryou.setuios`，Core `.core`，Live Activity `.liveactivity`。

## 发布

新版本不能直接在 GitHub 网页上塞附件。请按 [docs/release-process.md](docs/release-process.md) 操作。

- 标签格式：`YK-v主版本.次版本.修订号`，预发布加 `-alpha.N` / `-beta.N` / `-rc.N`
- **alpha / beta / rc 只发布源码**，禁止附带 ipa、xcarchive、dSYM
- 使用 `bash scripts/create-source-release.sh <tag>` 打标签并创建 Release

## 说明

本应用提供图片浏览、AI 绘画、音乐播放、收藏与公开广场，供学习、研究和个人使用。图片与音乐版权归原作者或原平台。禁止恶意刷接口、批量注册、绕过限制或把服务用于未授权的商业用途。
