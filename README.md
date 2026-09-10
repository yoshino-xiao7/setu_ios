# 亦可 YK iOS（原雪涼云）

**亦可 YK（原雪涼云）** 的 SwiftUI 原生客户端，将图片浏览、音乐播放、AI 绘画和收藏分享带到 iPhone。品牌英文标识为 **YIKE**，简称 **YK**，App 显示名称为「亦可 YK」。

仓库目录 `setu_ios`、`SetuIOSApp` 工程名和 Bundle ID 沿用现有命名。客户端复用 `setu_api_full` 后端；`setu_cloud` 作为功能与接口参考，iOS 使用原生界面与交互。

## 功能概览

- **图片与收藏**：作品浏览、收藏夹、公开广场、图库投稿。
- **音乐**：搜索、推荐、歌单与资料库、播放历史、歌词、后台播放与锁屏控制。
- **AI 绘画**：创建生成任务、查看历史、浏览公开作品、管理素材与删除申请。
- **账户与服务**：登录注册、账户安全、通行密钥、积分、API Key、通知与系统状态。
- **管理员功能**：按管理员权限提供用户、内容审核和任务管理入口。

## 技术与认证

- Swift 5.9、SwiftUI、SwiftPM 与 XcodeGen，最低支持 iOS 17。
- 使用现有 `SID` Cookie 会话与 `signSecret` HMAC 请求签名；敏感签名信息保存在 Keychain。
- 使用 AVFoundation 提供音频播放，WidgetKit / ActivityKit 提供 Live Activities。
- 较新系统能力通过可用性判断接入。

## 目录

- `Sources/SetuIOSApp`：原生页面、导航、设计组件与资源。
- `Sources/SetuIOSCore`：网络客户端、认证、数据模型与核心逻辑。
- `Sources/SetuIOSLiveActivityWidget`：Live Activity 扩展。
- `Tests/SetuIOSAppTests`：单元测试与测试资源。
- `Native/PixivTransport`：原生图片网络传输组件。
- `project.yml`：XcodeGen 工程配置；`Package.swift`：SwiftPM 配置。
- `docs`：方案、接口契约、ADR 与验证记录。

## 本地开发与检查

开始修改前，按 [AGENTS.md](AGENTS.md) 核验主线与工作目录：

```bash
git status --short
git worktree list
git fetch origin main
bash scripts/check-baseline.sh
```

准备原生传输依赖的方法见 [PixivTransport 说明](Native/PixivTransport/README.md)。

```bash
# 运行单元测试
swift test

# 从 project.yml 生成 Xcode 工程
xcodegen generate

# 编译 iOS 模拟器版本
xcodebuild -project SetuIOSApp.xcodeproj -scheme SetuIOSApp \
  -destination 'generic/platform=iOS Simulator' build
```

真机运行需要配置开发签名；APNs、关联域名与后台播放等能力应按对应文档完成配置和设备验证。
