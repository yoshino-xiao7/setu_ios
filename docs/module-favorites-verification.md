# 模块收藏验证记录（2026-09-10）

本次在用户现有未提交实现上修改通用收藏能力。没有提交、推送、应用数据库迁移或安装设备。

## 本次修改

- `ModuleFavoriteClient`：外部 ID 作为单个 URL 路径片段编码，拒绝路径分隔符、控制字符和点路径；批量查询去重并按 100 个 ID 拆分。
- `ModuleFavoriteButton`：未登录或需要重新认证时进入现有账号入口；收藏状态未知时先查询，再决定增加或删除；按账号、模块、外部 ID 刷新状态，忽略旧账号和过期刷新请求的结果。
- 新增 `ModuleFavoriteContractTests`，XcodeGen 已将其加入测试目标。
- 后端修正与接口说明见内部 API 仓库的模块收藏契约文档。

## 验证结果

| 检查 | 结果与边界 |
| --- | --- |
| iOS Git 基线 | `setu_ios` 主目录，`main`，HEAD `24d2db254f08442e85b912dfec18276ee200b2a9`；已 fetch `origin main`，基线脚本通过；产物输入包含未提交代码 |
| 后端针对性测试 | 41 项通过，含实际 MVC 拦截器注册和 MyBatis SQL 解析 |
| 后端全套 `mvn -o test` | 总计 562 项，530 项通过、32 项跳过，无失败；跳过项为已有音乐契约骨架 31 项、Pixiv 动画 1 项 |
| 收藏客户端独立测试 | 8 项通过；把当前 `ModuleFavoriteClient`、模型、真实 `APIClient`、`AuthSigner` 及其依赖原样复制到临时 Swift 包，HTTP 响应由 URLProtocol fixture 提供 |
| 收藏按钮语法 | `swiftc -frontend -parse` 通过；没有据此声称 SwiftUI 类型检查或交互验收通过 |
| 完整 `swift test` / Simulator App 构建 | 均被已有 `JmCatalogClient.swift:176` 的 Swift 排他访问编译错误阻断；该文件未修改 |
| UI / 真机 / 数据库 | 未完成；没有实际登录隔离、音频出声或阅读翻页证据；没有连接部署数据库 |

独立测试使用原始源码文件，记录在临时目录 `/tmp/setu-favorite-check-0mo41kaz/source-sha256.json`。日志为 `/tmp/setu-favorite-isolated-tests.log`、`/tmp/setu-more-backend-suite.log`、`/tmp/setu-more-build.log`；临时文件可能被系统清理。长期保留的回归测试在 `Tests/SetuIOSAppTests/ModuleFavoriteContractTests.swift`。

## 方案仍未完成的部分

- 原有 AppShell 在未登录时显示账号页，尚未实现方案中的匿名浏览入口；本次没有改变整个 App 的登录门槛。
- 现有“更多”导航及产品上下文/ADR 文件保留，导航仅作静态检查，尚未通过模拟器和 375pt / 430pt 视觉验收。
- 外部目录、媒体播放及阅读链路没有因本次通用收藏检查获得验收结论。JM 内容接入、解密和阅读链路未修改或验证。

不能把以上结果标记为“更多 + ASMR/JM 整体完成”。
