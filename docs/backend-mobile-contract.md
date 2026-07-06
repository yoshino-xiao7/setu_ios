# 后端移动端契约

## 认证

移动端沿用现有浏览器会话模型：

- 登录接口设置 HttpOnly `SID` Cookie。
- 登录响应返回 `signSecret` 与 `expireAt`。
- 移动端将 `signSecret` 存入 Keychain。
- 受保护请求携带：
  - `X-Timestamp`
  - `X-Nonce`
  - `X-Signature`

签名消息格式：

```text
{timestamp}:{nonce}:{METHOD}:{path}
```

示例：

```text
1710000000000:9a0b1c2d3e4f5061:GET:/user/info
```

## 已存在后端能力

当前后端已存在以下关键能力，可直接作为 iOS 第一阶段依赖：

- `POST /auth/login`
- `POST /auth/logout`
- `POST /auth/refresh-signature`
- `GET /user/info`
- `SignatureService` 会话签名校验
- `LoginSessionIssuer` 写入 `SID` Cookie

## 本次新增移动端能力

所有 `/mobile/**` 接口都纳入登录用户拦截器与 HMAC 签名拦截器。
iOS core 已提供 `MobileAppClient` 对应封装。

### 读取移动端能力

```http
GET /mobile/capabilities
```

返回：

- `refreshSignatureSupported`: 支持 `/auth/refresh-signature`。
- `apnsDeviceRegistrationSupported`: 支持 APNs token 绑定。
- `liveActivityPushTokenSupported`: 支持 Live Activity push token 保存。
- `liveActivityBroadcastChannelSupported`: 后端具备 Live Activity broadcast channel 登记表，供后续服务端广播推送配置使用。
- `galleryDirectUploadSupported`: 投稿流程支持直传。
- `galleryMultipartUploadSupported`: 当前未提供移动端 multipart 后端中转上传。
- `galleryUploadRecoverySupported`: 支持通过批次详情恢复投稿状态。
- `musicPlaybackMode`: 当前为 `REMOTE_URL`。
- `musicRangeRequestPolicy`: 当前为 `UPSTREAM_MEDIA_URL`，即 iOS 播放器直接访问上游播放 URL，Range 能力由上游媒体地址决定；如果后续改为后端媒体代理，必须补齐 Range/Content-Range/Accept-Ranges。

### 注册 APNs 设备

```http
POST /mobile/devices/apns
```

请求：

```json
{
  "deviceId": "vendor-or-installation-id",
  "apnsToken": "token",
  "apnsEnvironment": "SANDBOX",
  "appVersion": "1.0.0",
  "osVersion": "iOS 27.0",
  "model": "iPhone"
}
```

`apnsEnvironment` 只能是 `SANDBOX` 或 `PRODUCTION`，默认 `PRODUCTION`。

### 注销设备

```http
DELETE /mobile/devices/{deviceId}
```

将设备标记为不可推送，不删除历史记录。

### 注册 Live Activity Push Token

```http
POST /mobile/live-activities
```

请求：

```json
{
  "deviceId": "vendor-or-installation-id",
  "activityId": "local-activity-id",
  "activityType": "AI_GENERATION",
  "pushToken": "activity-push-token",
  "staleAt": "2026-07-06T18:30:00"
}
```

### 结束 Live Activity

```http
POST /mobile/live-activities/{activityId}/end
```

服务端标记 `ended_at`，后续推送任务应跳过已结束活动。

## APNs 服务端推送

后端提供 `ApnsPushService` 供业务服务调用：

- `sendAlertToUser(...)`: 向用户已启用 iOS 设备发送普通 APNs alert。
- `updateLiveActivity(...)`: 使用保存的 Live Activity push token 发送 `liveactivity` 更新。
- `hasBroadcastChannel(...)`: 检查指定 Live Activity 类型是否已登记可用 broadcast channel。

后端已新增 `apns_live_activity_broadcast_channel` 表，用于登记 APNs Live Activity broadcast channel。当前实现先完成 channel 管理和可用性查询；具体 channel 创建/轮换仍应在接入 Apple APNs broadcast 流程时配置，避免在未完成证书和 bundle 能力验证前发送错误请求。

配置项：

- `APNS_ENABLED`
- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY`
- `APNS_ENVIRONMENT`

未配置或未启用时，推送服务会安全跳过，不影响主业务流程。真实 APNs 私钥不得提交到仓库。

## 已确认接口形态

- `/auth/login` 已返回 `signSecret`、`expireAt`，并继续设置 `SID` Cookie。
- `/auth/refresh-signature` 已支持使用有效 `SID` 刷新签名密钥。
- 投稿上传已采用批次初始化、直传凭证、状态回写和批次详情查询，适合 iOS 做弱网恢复。
- 登录用户音乐接口应优先使用 `/user/music/**`；程序化 API Key 音乐接口仍是 `/music/**`。

## 仍需真机/联调验证

1. `SID` Cookie 的域名、`Secure`、`SameSite=Lax` 在生产域名和 `URLSession` 下的行为。
2. APNs token 的 sandbox/production 环境切换与失效重绑。
3. Live Activities 服务端推送发送器尚未实现，本次只保存 push token 和生命周期状态。
4. 音乐播放当前返回上游播放 URL，iOS 后台播放的 Range 表现需要用真实 URL 验证。
5. 若需要后端媒体代理流，必须新增支持 Range 请求的 streaming endpoint。

## 不做的事

- 不把 API Key 权限和浏览器/移动端用户会话权限混用。
- 不在移动端保存账号密码。
- 不在日志中打印 `SID`、`signSecret`、API Key 或任何密钥。
