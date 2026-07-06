# ADR 0001: 使用原生 SwiftUI App Shell

## 状态

Accepted

## 决策

`setu_ios` 使用 SwiftUI 原生 App Shell，不使用 WebView 作为主要功能承载方式。Vue 前端仅作为功能覆盖清单、接口调用参考和状态设计参考。

## 原因

- iOS 需要符合系统导航、表单、后台播放、通知、Widget、Live Activities、App Intents 等平台体验。
- 现有前端的 Aurora Glassmorphism 适合 Web 控制台，但 iOS 应采用系统设计语言。
- 后端 API 已经相对完整，原生客户端可以直接复用接口契约。

## 后果

- 初期开发成本高于套壳。
- 需要维护一套 Swift DTO 和 API client。
- 用户体验、性能、系统能力接入空间更大。
