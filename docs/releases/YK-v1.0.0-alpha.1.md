**已由 [YK-v1.0.0-alpha.2](https://github.com/yoshino-xiao7/setu_ios/releases/tag/YK-v1.0.0-alpha.2) 取代。** 本标签对应的源码 README 误含内部私有仓库地址，请改下 alpha.2。

首次公开源码发布。

**本版本只提供源码**（GitHub 自动附带的 zip / tar.gz）。没有 ipa、没有 TestFlight、没有已经签好名的安装包。要在设备上运行，请自行用 Xcode 编译。

工程内部开发显示版本仍为 **1.1 (5)**。GitHub 发行号从 `YK-v1.0.0-alpha.1` 起算。后续版本必须走仓库里的 [发布流程](../release-process.md)。

## 这是什么

亦可 YK（原雪涼云）的原生 iPhone 客户端。图片、音乐、AI 绘画、收藏和账户都在 SwiftUI 里完成，不是网页套壳。后端是同一套亦可 API。

需要 **iOS 17+**。界面为简体中文。

## 功能一览

### 账户

- 邮箱注册 / 登录 / 找回密码
- Sign in with Apple
- 通行密钥
- 未登录可先浏览「更多」
- 个人资料、修改密码、QQ 绑定（bot QQ `2830323446`）、积分、API Key、通知
- 音乐缓存与图片显示（薄雾、首页推荐）设置

### 五个主界面

1. **首页**：继续听音乐或 AI 绘画、最近收藏、今日推荐、通知和积分提醒。
2. **AI 绘画**：中文描述生成、风格与角色、草稿保存、历史、广场、删除申请；可用 Live Activity、系统通知和 QQ 接收进度。
3. **图片**：滑动刷图、筛选、Pixiv 绑定浏览、收藏夹、公开广场、图库投稿、删除申请、积分取图。
4. **音乐**：搜索、日推、歌单、私人 FM、歌词、后台播放、锁屏控制、AirPlay、本地缓存。
5. **更多**：广场、ASMR（asmr.one）、JM 本子（禁漫天堂）。后两者的收藏和观看历史按登录用户隔离。

### 管理员

管理员可在「我的」打开后台：用户、黑名单、系统监控、音乐 Token、图片任务与审核、AI 审核、操作日志。普通账号看不到这些入口。

## 如何获取源码

本 Release 页面提供 Source code (zip) 和 Source code (tar.gz)。也可以：

```bash
git clone https://github.com/yoshino-xiao7/setu_ios.git
git checkout YK-v1.0.0-alpha.1
```

构建步骤见仓库 [README](../../README.md)。

## 已知边界

- Alpha 只保证源码快照可被检出和按文档编译，不承诺应用商店分发。
- 真机运行依赖你自己的开发者团队、证书、APNs 与 Associated Domains 配置。
- 图片、音乐、ASMR、JM 等内容版权归原作者或原站点；客户端提供浏览与收藏。
- 预发布标签后续若有修复，会使用 `YK-v1.0.0-alpha.2` 等新号，不会改写本标签。
