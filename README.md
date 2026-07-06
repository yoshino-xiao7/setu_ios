# Setu iOS

雪涼云 iOS 原生 App 工程。这个目录用于后续所有 iOS 开发任务，前端 `setu_cloud` 只作为功能清单和交互参考，不做 WebView 套壳。

## 当前定位

- SwiftUI 原生应用骨架。
- 复用现有 Spring Boot 后端 API。
- 保留现有浏览器认证语义：`SID` Cookie + `signSecret` HMAC 签名。
- iOS 27 相关能力采用可用性判断渐进接入，基础运行目标先保持在 iOS 17+，避免把未稳定 API 变成阻塞项。

## 目录

- `Sources/SetuIOSApp`: App 源码。
- `Tests/SetuIOSAppTests`: 基础单元测试。
- `docs`: 方案、契约、ADR 与后续开发文档。

## 本地检查

```bash
swift test
```

后续接入 Xcode 工程、签名、TestFlight、APNs、Widgets、Live Activities 时，在本目录继续演进。
