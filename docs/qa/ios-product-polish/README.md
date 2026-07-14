# iOS 产品化视觉与运行验收记录

日期：2026-07-11

## 欢迎页尺寸与外观基线

| 宽度 | Light | Dark |
| --- | --- | --- |
| 375pt | [截图](welcome-375-light.png) | [截图](welcome-375-dark.png) |
| 390pt | [截图](welcome-390-light.png) | [截图](welcome-390-dark.png) |
| 430pt | [截图](welcome-430-light.png) | [截图](welcome-430-dark.png) |

检查结果：

- 三种宽度均未出现水平溢出、标题裁切或状态栏冲突；
- Light/Dark 均使用原生无文字品牌图形，不再展示 API、GET、JSON 或高亮白底旧海报；
- 375pt 首屏底部内容需要向下滚动，隐私与条款入口仍保留在可滚动内容中；
- 主要按钮、注册、通行密钥、访客预览和法律入口均使用至少 44pt 的实际按钮命中区。

## 自动化运行证据

执行环境：iOS 27.0 Simulator。

Xcode 27 beta 不再提供独立 `Simulator.app`。先用 `xcrun simctl boot <UDID>` 启动设备，再执行 `open /Applications/Xcode-beta.app/Contents/Applications/DeviceHub.app` 打开设备界面；`open -a Simulator` 在此版本会失败。

| 设备 | 结果 | 说明 |
| --- | --- | --- |
| `Setu QA 375` | 12/12 完整基线 + 页面矩阵当前 2/2 | 本轮完整回归曾通过；最新页面语义与滚动锚点调整后，另行复核 Light 默认与 Dark AX5 两项矩阵 |
| `Setu QA 390` | 10/10 通过 | 既有完整回归基线；尚未执行新增的隔离登录后页面矩阵 |
| `Setu QA 430` | 10/10 基线 + 新增矩阵 2/2 | 既有完整回归通过；新增的 Light 默认与 Dark AX5 登录后页面矩阵另行通过 |

自动化覆盖矩阵：

| 用户流程 | 当前证据 |
| --- | --- |
| 未登录欢迎页 | 价值文案、Apple/邮箱/注册入口、语义阅读顺序、系统 accessibility audit |
| AX5 注册表单 | 邮箱与两次密码可填写，验证码和提交按钮可触达；不包含真实验证码提交 |
| 随机图片 | 首次高清查看明确确认积分；AX5 下喜欢、收藏夹和下一张可触达 |
| 随机图片喜欢状态失败态 | 图片加载成功但 `/favorite/exists/...` 返回 503 时，“喜欢”不会出现，操作改为可点击的“重试状态”；无 URL 时使用独立占位态且不显示遮挡它的元数据叠层。最终 `build-for-testing` 已通过；375pt Dark + AX5 已用最终构建实际启动核验，占位态、重试状态及四个主操作均无裁切重叠；自动断言与“重新应用参数后恢复内容”的 AX5 回归已落地，结果待 runner 恢复补跑 |
| AI 创作 | 离开页面后重新进入，普通创作草稿仍保留 |
| 公开 AI 作品 | 他人作品不出现所有者管理操作；三个滚动视口执行 accessibility audit；新增详情兼容性 404 场景，确认新鲜广场快照不会误报“作品已下架”，并由 3 项状态决策单测封口 |
| 收藏列表 | 点击图片打开原生预览，而不是跳转浏览器 |
| 通知权限 | 系统授权前展示用途说明；拒绝后出现系统设置恢复入口 |
| 隔离首页 Dashboard | 375pt、430pt 的 Light + 默认字号与 Dark + AX5；loaded 收藏和提醒区域执行 viewport audit |
| Dashboard 独立失败态 | 五个 503 离线夹具分别对应生成、收藏、推荐、通知和积分；每项都有稳定的原位重试入口，并断言失败时不出现空态或绿色健康状态。自动用例已提交，本轮 runner 启动崩溃，375pt Dark + AX5 已通过 Device Hub 手动启动核验 |
| 账号安全 Apple 绑定失败态 | `/user/apple` 返回 503 时明确显示状态未知与原位重试，不出现绑定或解绑入口；375pt Dark 的默认字号和 AX5 已通过手动启动核验，自动用例已提交待 runner 恢复补跑 |
| 通知已读与未读计数一致性 | 四项离线 UI 夹具覆盖“全部已读”503、计数未知、迟到旧列表/计数和空当前页 pending；核心对账另由纯逻辑模块 `NotificationReadConsistency` 与 9 项确定性行为测试覆盖跨页单条已读、批量已读后新通知、空页旧计数、重试和 eventual recovery。最终 `build-for-testing` 与 Swift 99/99 已通过；503 写入失败已在 375pt Dark 的 Device Hub 中实际点击核验；UI runner 结果仍待恢复后补跑 |
| 每日图片收藏状态失败态 | 图片加载成功但 `/favorite/exists/...` 返回 503 时，收藏操作显示“暂不可收藏”且不可触发；错误反馈与“重试收藏状态”可达，下载和原图仍可使用。`build-for-testing` 通过，375pt Dark 已在 Device Hub 实际滚动核验 |
| 按条件找图收藏状态失败态 | 离线获取一张图片后让其收藏查询返回 503；结果行显示“收藏状态未知”和单项重试，更多菜单的收藏入口为禁用状态。`build-for-testing` 通过，375pt Dark 已实际执行找图并打开菜单核验 |
| 隔离音乐首页 MusicHome | 同上；覆盖播放历史、歌单与热门搜索等稳定 landmark |
| 隔离收藏夹广场 CollectionSquare | 同上；覆盖 loaded 卡片及下方收藏夹打开入口 |

UI tests 已通过离线夹具覆盖 Dashboard、MusicHome、CollectionSquare 三个隔离登录后页面，但这些场景直接挂载业务页面，不经过 `RootAppView`、真实登录/session、Tab 切换或深链恢复。仍未覆盖真实注册与图片验证码提交、真实登录后的完整业务路由、真实接口的加载/离线/超时/5xx 组合，以及真机系统能力。

欢迎页与公开作品页运行系统 accessibility audit 的命中区域、元素描述、文字裁切和语义特征检查。iOS 27 beta 在渐变背景上会把近黑色文字误报为低对比度，因此颜色对比度由 `ColorContrastTests` 静态校验和实际 Light/Dark 截图共同验证；待稳定版运行时再恢复系统 contrast audit 复核。

滚动页面的 viewport audit 只忽略 Xcode 27 beta 返回的无 element `List` 滚动 `textClipped` orphan issue，以及可见面积低于 90% 的滚动边缘内容；测试 landmark 自身必须可点击且至少 90% 可见，其他 orphan 类型与可见面积达到 90% 的元素仍参与审计。这里记录的是多个稳定视口采样，不代表完整页面穷举或真实 VoiceOver 手势验收。

iOS 27 beta 在注册输入框获得键盘焦点时还会输出一次无来源的 `Invalid frame dimension (negative or non-finite)` 运行时诊断；当前流程、布局和测试不受影响，且移除安全区或交互式键盘收起均不能消除它。该项暂按 Xcode 27 beta 已知诊断保留观察，不作为“无警告通过”的证据。

当前 Xcode 27 beta 在测试套件已经打印最终结果后，偶尔会停在 `Finalize test log`。此前 430pt 完整套件已明确输出 `Executed 10 tests, with 0 failures` 后出现过日志收尾停滞；本轮 375pt 完整基线正常收尾并输出 `Executed 12 tests, with 0 failures`，此前页面语义调整后又单独复核了两项矩阵。新增 Dashboard 失败态用例的两次尝试则在测试 worker materialize 阶段出现 `target-runner` 崩溃，断言尚未开始、结果包也未封口，因此不能记为通过；相同构建产物以 `simctl launch` 加载离线失败参数后可正常运行，375pt Dark + AX5 首屏的失败文案和 44pt 重试按钮已人工核验。稳定版 Xcode 或 runner 恢复后仍需补跑该自动用例。通知的核心一致性已经由不依赖 runner 的纯逻辑单测封口；通知 UI 夹具与随机图片失败态用例在获得封口的 `.xcresult` 前仍不计入 375/390/430 的 UI 通过数。

## 仍需完成

- 使用真实 VoiceOver 手势按阅读顺序完成欢迎、注册、随机图片和公开作品流程；
- 将隔离页面覆盖扩展到其余主要业务路由，并补齐 `RootAppView`、真实登录/session、Tab 切换与导航恢复集成；390pt 的新增登录后页面矩阵，以及 XXL、Increase Contrast、Reduce Motion 组合仍待补充；
- 在 Xcode UI test runner 恢复后补跑 `testDashboardFailuresRemainExplicitAndRetryable`，形成五个字段失败态的自动断言结果包；
- 同期补跑 `testSecuritySettingsDoesNotTreatUnknownAppleBindingAsUnbound`，确认安全状态未知时不会误开放绑定或解绑操作；
- 补跑 `testMarkAllReadFailurePreservesUnreadState`、`testUnreadCountFailureStaysUnknownWhileRowsRemainUsable` 与 `testMarkAllReadSuccessSurvivesStaleReload`，分别固化写入失败、计数未知和迟到响应不回滚行为；
- 补跑 `testMarkAllReadPendingDoesNotDependOnVisibleRows`，确认当前页没有未读行时全局 mutation pending 仍拒绝旧计数；
- 补跑 `testDailyImageFavoriteFailureDoesNotPretendToBeUnfavorited`，固化每日图片收藏状态未知时的禁用和重试行为；
- 补跑 `testPointsResultsKeepFailedFavoriteStatusUnknown`，固化逐图片收藏状态、单项重试和未知状态菜单禁用行为；
- 补跑 `testRandomImageFavoriteFailureDoesNotPretendToBeUnliked`，确认随机刷图收藏状态未知时只允许重查，不会开放默认收藏写入；
- 补跑扩展后的 `testRandomImagePrimaryActionsRemainReachableAtAX5`，确认重新应用筛选参数后仍能展示图片与主操作；
- 真机重点验证通知第二页单条已读、写入期间切换未读筛选、服务端迟到后的恢复，以及随机筛选取消与旧请求迟到；代码侧已通过统一对账、generation 和 request ID 防护，通知核心路径另有确定性单测；
- 图片验证码的音频或等价挑战需要后端提供可访问挑战接口；当前 iOS 端没有可安全推导答案的本地替代方案，待接口具备后接入；
- 真机验证 Apple 登录、Passkey、APNs、照片权限、后台音乐与 Live Activity；
- 生产 OSS/CDN 的公开作品下架和缓存失效验证。
