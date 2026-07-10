# Apple 登录、通行密钥与系统推送上线清单

## Apple Developer

- App ID `icu.yukiryou.setuios` 开启 Sign in with Apple、Associated Domains 与 Push Notifications。
- Xcode 自动签名使用 Team ID `7G6J4S76PN`，确认开发与发布 provisioning profile 都包含上述能力。
- APNs 使用 `.p8` token key；私钥只放部署环境，不提交仓库。

## 域名与通行密钥

在 `https://cloud.yukiryou.icu/.well-known/apple-app-site-association` 无重定向返回 `application/json`：

```json
{
  "webcredentials": {
    "apps": ["7G6J4S76PN.icu.yukiryou.setuios"]
  },
  "applinks": {
    "details": [{
      "appIDs": ["7G6J4S76PN.icu.yukiryou.setuios"],
      "components": [{ "/": "/*" }]
    }]
  }
}
```

后端生产环境保持：

```text
WEBAUTHN_RP_ID=cloud.yukiryou.icu
WEBAUTHN_ALLOWED_ORIGINS=https://cloud.yukiryou.icu
APPLE_CLIENT_IDS=icu.yukiryou.setuios
```

## APNs 后端环境

```text
APNS_ENABLED=true
APNS_TEAM_ID=7G6J4S76PN
APNS_KEY_ID=<Apple Key ID>
APNS_BUNDLE_ID=icu.yukiryou.setuios
APNS_PRIVATE_KEY=<完整 p8 PEM 或 PKCS8 base64>
APNS_ENVIRONMENT=PRODUCTION
```

普通通知按设备记录的 `SANDBOX`/`PRODUCTION` 环境选择 APNs 地址；Live Activity 使用全局 `APNS_ENVIRONMENT`。

## 真机验收

1. 使用真实 Apple ID 完成首次登录；确认同邮箱旧账号得到“先登录再绑定”提示。
2. 密码登录后在“账号安全”绑定 Apple，再退出并用 Apple 登录。
3. 在真机创建、登录和删除通行密钥，验证 iCloud 钥匙串同步。
4. 登录后允许通知，确认设备注册成功；退出登录后设备记录被禁用。
5. 触发 AI 完成、投稿审核和删除申请通知，验证前台横幅、后台通知及点击深链。
