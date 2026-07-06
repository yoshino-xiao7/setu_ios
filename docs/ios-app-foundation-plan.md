# Setu iOS 基础框架方案

## 背景

雪涼云现有产品由 `setu_cloud` Vue 控制台和 `setu_api_full` Spring Boot 后端组成。iOS App 需要覆盖已有前端功能，但不能直接迁移 Vue 页面，也不能做纯 WebView 套壳。

## 基础决策

1. 使用 SwiftUI 原生实现 UI、导航和状态。
2. 使用 `URLSession`、`Codable`、`async/await` 对接后端。
3. 使用系统 Cookie 存储保存后端 `SID`，使用 Keychain 保存 `signSecret`。
4. 使用 CryptoKit 生成与 Web 端一致的 HMAC：`timestamp:nonce:method:path`。
5. 使用 Tab + 每 Tab 独立 `NavigationStack`，后续功能按模块落地。
6. iOS 27 新能力作为增强层：Liquid Glass、App Intents、Live Activities、Widgets、Apple Intelligence；基础功能不得依赖未稳定 API。

## 第一阶段范围

- App shell：TabView + NavigationStack。
- 基础依赖：配置、Keychain、APIClient、AuthSession。
- 认证入口：邮箱密码登录占位、刷新签名、登出。
- 功能地图：仪表盘、API Key、积分、收藏/广场、AI、音乐、通知、管理。
- 后端移动端契约文档。
- 后端移动端基础接口：capabilities、APNs token、Live Activity push token。

## 后续模块顺序

1. Auth：登录、注册、验证码、找回密码、Passkey。
2. Dashboard：用户信息、系统状态、通知。
3. Points/API Key：积分调用、流水、Key 管理。
4. Collections：收藏夹、公开收藏夹、广场、用户主页。
5. AI：绘图、历史、广场、资产选择、Live Activities。
6. Music：播放器、歌单、播放历史、后台播放。
7. Gallery/Admin：投稿、删除申请、审核与操作日志。

## 风险

- Cookie `SameSite=Lax` 在原生 App 中通常由 `URLSession` 管理，但必须用真机/模拟器验证生产域名行为。
- 当前音乐接口返回上游播放 URL，后台音频和 Range 行为需要真机验证；若改为后端媒体代理，必须实现 Range。
- AI 长任务第一版可轮询，体验增强应接入 Live Activities/APNs 推送。
- App Store 审核需要准备图片、音乐代理、AI 生成、用户内容审核相关说明。
