# 图片模块验证记录（2026-09-08）

## 架构与真实边界

- iOS 使用本机 Keychain 管理每个雪涼云用户的 Pixiv 账号，Rust/C 适配层直接复用 Pixez 独立 MIT 许可的 rhttp 网络组件支持图片传输和可选增强登录连接；令牌交换/刷新及作品 API 自动探测本机 ECH 与不保存 cookie 的系统 URLSession，选择当前网络可用路径；图片传输仍验证上游证书链和域名。没有嵌入 Flutter 或复制 GPL 应用层代码，组件来源及修改说明保存在 Native/PixivTransport/vendor/rhttp-native/UPSTREAM.md。
- Web 的 Pixiv 在线暂未开放，本站图库沿用现有主题。全量类型检查有与干净基线相同的 177 条错误；本次新增诊断 0。Vite 构建、修改范围 ESLint 与 390/1440px 图库流程通过，不等于全量 npm build 通过。
- 主后端及爬虫已通过 GitHub Actions 部署。V33 已落库，新增账号绑定表为空，用户个人凭据没有配置到服务器。

## 登录排障

- Mac 物理 en0 探针曾得到 ECH Accepted、登录 HTML HTTP 200、已知图片 JPEG HTTP 200；走 utun4 时上游返回 HTTP 403。这只验证相应网络路径。
- 本机登录桥采用非持久 WKWebView、带随机凭据的 127.0.0.1 CONNECT 服务和每次登录生成的证书。Swift 只接受本次证书及固定域名；原生连接保持上游证书校验。不会安装系统证书。
- 13:14 用户实测新桥仍失败。真机独立公开页面探针复现：`failed code=-1200 underlying=-9880 stage=5`，两次精确证书校验通过，上游 TLS 已完成，本机 TLS 未完成。Apple SDK 将 -9880 定义为 `errSSLATSViolation`。
- 用户明确授权为 app-api.pixiv.net、accounts.pixiv.net、oauth.secure.pixiv.net、www.pixiv.net、i.pximg.net、s.pximg.net、i-cf.pximg.net 添加 ATS 域名例外。实现保持 TLS 最低版本/PFS 默认值；不启用全局例外，不匹配子域名；WebKit 规则禁止 HTTP 资源，导航只允许 HTTPS/about 及单次 OAuth 回调。App Store 需解释该域名例外用途。
- Apple 文档：[手动服务器信任](https://developer.apple.com/documentation/Foundation/performing-manual-server-trust-authentication)、[域名例外](https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionallowsinsecurehttploads)。
- 加入精确域名 ATS 例外后，真机达到 stage=6、页面完成加载，但输入框为0；用户截图确认是 Pixiv 的“使用环境已被阻止”页面。没有将此计为登录成功。
- 用户指出最初标准登录页曾可打开，因此恢复标准 WebKit 为每次登录默认值；增强连接只允许在登录页菜单手动选择。此阶段授权码交换/API 仍使用本机原生传输；下文真机对照后将授权码交换及刷新改为系统标准连接。公开物理网络对照中，HTTP/1.1 和 HTTP/2 均得到入口302、accounts登录200，不能将手机拦截归因于 HTTP 版本。
- 真实账号登录、令牌交换/刷新和长时间刷图仍需要分别记录，不能由公开表单探针或编译成功替代。

## 复用 Pixez 网络实现

- 上游固定版本 `0750c38b0c8aaf200e992ec9b4303f5cd6abba87`。直接复用 MIT `client.rs` 的 ECH、TLS、DNS、连接缓存及其 vendored reqwest/h3/quinn，移除 Flutter 绑定、公开 Swift 适配层所需入口。源许可证和依赖声明随构建保留。
- 13:42 用户截图已明确“网页授权已返回”，失败在令牌交换 HTTP 403。用户确认近期 Pixez 完成过新的登录，不能假定账号或整个网络不可用。
- 授权请求改用与 Pixez iOS 分支一致的客户端协议标识；没有改用密码登录，没有读取 Pixez 凭据，标准 WebKit 保持默认。
- 新增令牌拒绝回归先失败后通过，验证不持久化失败凭据、不重试单次授权码、不在错误中泄漏响应。原生六项边界测试通过。
- Mac 公开无效 grant 探针返回 403 HTML；该探针未携带完整 OAuth 请求参数，且 Mac 网络路径与手机不同，不能代替真机令牌验证。真机 DEBUG token probe 使用实际 Swift 授权请求构造，发送一个明确无效的测试 code，只记录状态码/是否 JSON，不访问 Keychain。

- 手机已安装 Pixez 1.9.86+511，与参考源码版本一致。首次复用版本构建/280项 Swift 测试通过并安装，但手机实际完整格式的合成 code 请求仍返回 `HTTP 403, JSON false`，未计作登录修复。
- 发现首次构建依赖被自动升级（rustls 0.23.43 / aws-lc-rs 1.18.1 / h2 0.4.19 / hyper 1.11.1）。随后从上游 Cargo.lock 对齐至 0.23.40 / 1.17.0 / 0.4.14 / 1.10.1，重新构建验证。此时仍是排查假设，不宣称根因。

### 同机对照与最终路由

- 同一台 iPhone、同一份合成 OAuth 请求，在上游锁定的 rhttp 依赖下仍返回 `HTTP 403, JSON false, challenge false, blocked true`；系统 URLSession 返回 `HTTP 400, JSON true, challenge false, blocked false`。400 是合成无效 code 的预期校验错误，不是账号登录成功。证据：`/tmp/setu-rhttp-upstream-phone-token-probe.txt`。
- 因此撤销对 OAuth 的强制增强连接：`PixivDirectHTTPTransport` 将 `/auth/token` 的交换/刷新路由到独立 ephemeral URLSession，其余 API/图片继续复用 rhttp。禁止重定向，限定精确 HTTPS 令牌地址/POST/协议请求头，不共享 Cookie 或系统凭据，限制请求及流式响应大小，保留系统证书校验。
- 新增四项回归覆盖交换和刷新路由、请求隔离、JSON 状态、重定向及未知长度响应上限，全部通过。网页登录依旧标准 WebKit 默认。本轮没有读取或复用用户 Pixez 的凭据。
- 尚未确认上游具体为何拦截 rhttp 路径；依赖版本对齐未消除该差异。随后用户已确认真实绑定成功；真实令牌刷新仍未经过用户账号验证。

- 最终正式路由重新安装到同一 iPhone 后，公开探针得到 `selected public OAuth HTTP 400, JSON true, challenge false, blocked false`（`/tmp/setu-pixiv-system-final-phone-probe.txt`）。这是生产传输代码的无账号连通性验证，仍不计为实际账号绑定。
- 最终 Xcode 真机构建通过，Swift 284 项、1 项联网测试跳过、0 失败；安装及 app/Core 二进制 SHA-256 见 `docs/evidence/images-2026-09-08/device-install-receipt.json`。已恢复正常应用入口，等待用户本人登录。

## 本站图库 401 与误封

- 13:03:38 服务端拒绝 `/user/images/works/pixiv%2D138658877` 的签名。iOS 使用解码后的 URL.path 签名，与 Servlet 的实际编码 URI 不同；随后客户端清除了会话，匿名请求在 13:04 触发了临时 IP 封禁。
- APIClient 普通请求和上传统一改为 `url.path(percentEncoded: true)` 签名。编码路径回归先失败后通过，连同登录会话/签名共 15 项通过。
- 用户自行解封，未执行服务器会话凭据读取或解封脚本。
- 后端 0806ad3：正常频率超限仅返回 429 和 Retry-After:60，不累计自动 IP 封禁；登录用户按账号预算（30次/秒，600次/分钟），API Key 原有预算/计费及人工黑名单保持。工作流成功：https://github.com/yoshino-xiao7/setu_api_full/actions/runs/34190867426 。

## 已有验证

- Swift 核心测试最新 284 项、1 项显式联网测试跳过、0 失败；原生测试 6 项通过。
- 本地动画编码 37/83ms 两帧验证 MP4 时长及时间戳；多页和账号隔离测试通过。
- 430pt 图片页面 UI 两项通过。最近物理设备 XCTest 在 runner 初始化前断线，不算应用通过或失败。随后通过公开页面诊断参数直接启动真实 WebKit，并仅读取错误码/阶段及输入框数量。
- 爬虫工作流：https://github.com/yoshino-xiao7/pixiv-api/actions/runs/34188992721 。生产 PID 130412285 实际5页重复导入跳过5页；149278461 导入后数据库实际新增1页。缺页补齐有单元测试，未通过破坏生产数据做验证。

探针参数 `-ui-testing-pixiv-login-probe` 仅 DEBUG 可用；只打开公开登录表单，不读取、填写或提交用户密码。诊断文件只含固定阶段、错误码、主机和输入框数量。

## 作品接口 403 修复（真实绑定成功后）

- 用户确认真实 Pixiv 绑定成功，但作品列表报 HTTP 403。此时 OAuth 已走系统连接，作品仍被强制路由到 rhttp。
- 无账号公开接口复现：`SETU_PIXIV_API_LIVE_TEST=1 swift test --filter PixivDirectHTTPTransportTests/testLivePublicWorksTransport` 在原路由返回 HTTP 403 非 JSON，两个断言失败（`/tmp/setu-pixiv-api-live-before.log`）。相同作品推荐地址标准连接返回 HTTP 400 JSON。公开探针不携带用户令牌；400 是预期的未认证 API 校验响应。
- `PixivDirectHTTPTransport` 将 app-api.pixiv.net 的作品 API 与 OAuth 一起路由到隔离的系统 URLSession。共享端点白名单约束读/写路径与方法，Bearer 只允许发给精确 API 主机，继续拒绝跳转、Cookie、本站 HMAC、HTTP、URL 凭据、额外端口、头注入，限制流式响应为 8 MB（OAuth 1 MB）。不重试 403，不清除现有绑定。图片仍走原有证书验证的 rhttp 路径。
- 同一公开作品探针在修复后通过，初轮路由/OAuth 测试 5 项通过（`/tmp/setu-pixiv-api-live-after.log`）。这证明 API 连接路径可到达，不能代替实际推荐内容、图片及收藏交互验收。
- 最终回归：30 项相关测试（含公开作品探针）通过；完整 `swift test` 288 项、2 项显式网络探针跳过、0 失败。初轮新头注入测试发现 Swift CRLF 组合字符问题，改为 Unicode scalar 控制字符过滤；同时初轮两项既有 URLProtocol 捕获测试未捕获请求，针对复测及完整复测均通过。日志：`/tmp/setu-pixiv-api-targeted-final.log`、`/tmp/setu-pixiv-api-system-final-tests.log`。
- 真机应用构建通过并安装，未卸载应用或清除绑定。真机公开对照结果：`enhanced public API HTTP 403, JSON false`；`selected public API HTTP 400, JSON true`。证据：`/tmp/setu-pixiv-api-system-phone-probe.txt`。验证后已恢复正常启动。安装记录及 App/Core 二进制摘要保存于 `docs/evidence/images-2026-09-08/device-install-receipt.json`。
- 用户在此安装版本上已确认“作品和图片都正常显示”，结合前一轮“绑定成功”，真实登录、列表及图片展示验收通过。收藏、关注、多页保存及真实令牌刷新未因这条反馈而视作已验收。本轮没有修改后端、爬虫或服务器配置。

## 无代理直连补验与自动选路

- 用户随后指出，前一轮“作品和图片正常显示”是在开启代理时验收，不能代表无代理直连已完成。此处更正验收范围。
- 用户确认关闭 iPhone 代理后 Pixez 仍能刷新。对同一台手机重新执行原公开探针：`enhanced public API HTTP 400, JSON true`，`selected public API connection failed`（当时 selected 仍固定系统连接）。证据：`/tmp/setu-pixiv-direct-off-phone-probe.txt`。与开启代理时结果相反，说明固定系统连接造成代理依赖，rhttp 直连接入在此无代理网络下可到达 API。
- Mac 的 Host、HTTP/1.1、默认代理配置对照均为 403（`/tmp/setu-pixiv-ech-comparison.log`），不能用 Mac 的代理环境代替该手机无代理路径验收。
- 自动选路以无凭据公开 GET 探测可用 API JSON，ECH 优先启动，系统路径延后 300 ms；结果缓存 30 秒并合并并发探测。失败或 403 使当前选择失效；只读 GET 至多切换到另一个已探测可用的连接重试一次，OAuth/收藏/关注 POST 不自动重放。所有账号凭据仍仅由本机客户端发送给既定 Pixiv 主机，未改变 TLS 信任或请求白名单。
- 固定系统连接在无代理场景的回归先失败：`/tmp/setu-pixiv-auto-red.log`。
- 自动选路针对性回归 13 项、1 项外网探针跳过、0 失败（`/tmp/setu-pixiv-auto-tests.log`）；完整核心测试 293 项、2 项外网探针跳过、0 失败（`/tmp/setu-pixiv-auto-final-tests.log`）。真机应用构建成功（`/tmp/setu-pixiv-auto-build.log`）。
- 已覆盖安装自动选路版（`/tmp/setu-pixiv-auto-install.log`），无代理真机公开作品探测：enhanced/selected 均返回 HTTP 400 JSON（`/tmp/setu-pixiv-auto-api-phone.txt`）；公开合成令牌请求：HTTP 400 JSON，无 challenge/blocked 页面（`/tmp/setu-pixiv-auto-oauth-phone.txt`）。400 在这两项无真实凭据探针中为预期鉴权校验响应，不作为实际内容验收。验证后已恢复正常应用，现有绑定未清除。
- 用户在自动选路安装版本上明确确认“关闭代理，列表和大图都正常”。无代理真实作品列表与大图验收通过；本轮没有要求重新绑定。真实令牌到期刷新、新建绑定的网页流程、多页保存及收藏/关注互动仍保留各自独立验收边界。

## 首屏图片及信息持续加载：队列隔离

- 用户反馈无代理冷启动/刷新首页时，图片和页面信息持续加载。截图中 Pixez 使用默认 i.pximg.net，不能据此认定必须切换第三方镜像。
- 代码确认原生图片请求与 ECH API 共用 4 槽 OperationQueue，原生 45 秒超时开始于出队执行；取消同样需要等待已排队操作开始，慢图因此可阻塞 API，长队列可超过单请求超时很多倍。
- 复现测试将 4 张模拟慢图阻塞队列，原共享队列的页面 API 及时开始断言失败（`/tmp/setu-pixiv-media-shared-red.log`）。恢复媒体/API 独立 4 槽队列后通过，连同排队取消、排队计时截止、原有直连选路与安全校验 15 项测试、1 项外网探针跳过、0 失败（`/tmp/setu-pixiv-media-queue-green.log`）。
- 新请求从入队起计 45 秒总时限；取消/超时即结束等待者并取消原生操作，迟到的完成不会重复恢复 continuation。没有更换图片域名，没有放宽证书校验。
- DEBUG 可选 `-ui-testing-pixiv-media-audit` 只保留最近 100 条类别、状态码、队列/网络耗时和字节数，无 URL、账号、令牌或响应正文；默认关闭。
- 补充无代理真机原图实测：原固定节点的请求排队 0 ms，但等待 35,004 ms 后失败（`/tmp/setu-pixiv-media-public-timings.txt`），所以队列问题并非全部原因。Pixez 的 Hoster 会通过 Cloudflare DoH 更新图片节点；其默认固定地址与此前实现相同，但此前缺少刷新机制。可信 DoH 本轮返回 10 个官方节点，Mac 对 4 个节点的响应头测试均 200（1.4–4 秒），Mac 结果仍不能代替手机完整下载。
- 原生图片连接增加固定 HTTPS DoH、TTL 缓存、每主机至多 12 个节点的轮换池，拒绝私网/保留地址，保留默认验证和无 SNI 图片模式；DoH 不可用时短暂使用官方节点列表。图片响应头超时可换节点重试一次，整体 45 秒及响应大小限制不变。原生安全/解析测试 8 项通过、3 项显式外网诊断默认跳过（`/tmp/setu-pixiv-image-dns-tests.log`）。
- 真实首屏元数据记录显示，隔离后 API 大多 0.5–1 秒完成、队列等待近 0；固定图片节点部分仅约 40 KB 的图片仍需 8–12 秒，多项 35 秒超时（`/tmp/setu-pixiv-media-initial-real-timings.txt`）。这些耗时记录不含图片地址或账号信息。动态节点版已完成原生全平台构建、Swift 295 项回归（2 项网络探针跳过、0 失败）及 iPhone 应用构建并安装。


## 滚回已加载图片重复下载（15:48 起）

- 用户补充：页面信息正常；图片等待较久能出现，后续图片比首次快，但下滑再上滑会重新加载之前已显示的图片。首屏网络性能仍未验收。
- `testReturningToLoadedImageAndRefreshingFeedDoNotDownloadItAgain` 在修改前复现：同一资源重复查看/刷新产生 5 次媒体下载，期望 1 次（`/tmp/setu-pixiv-scroll-cache-red.log`）。视图离屏释放解码图片，而 `PixivLocalClient.media` 此前每次都发网络请求。
- 增加绑定实例私有、按验证后的来源 URL 复用的 LRU 数据缓存，最多 64 MiB / 256 项；不会将图片或 URL 写入磁盘，进程结束后需要重新下载，超限淘汰最久未查看的数据。刷新产生新的不透明资源标识仍可复用同一来源图片，缩略图与大图的不同 URL 不会混用。
- 相同资源的并发下载合并；离屏的调用者取消不会取消其他调用者的共享下载，传输仍受原有队列并发数及 45 秒截止约束。失败不缓存，可重试；解绑清空缓存并取消在途任务，每次读缓存前仍验证资源所属绑定。未更换图床、未修改证书验证或 API/OAuth 路由。
- 9 项 PixivLocalClient 定向测试通过（`/tmp/setu-pixiv-scroll-cache-green.log`），覆盖重复访问/刷新只下载一次、解绑后重新下载、并发取消、失败重试、容量淘汰及原有账号隔离。真实 iPhone 上的重复滚动体验待安装后验收。
- 全量 Swift 298 项测试（2 项显式联网跳过、0 失败）和 iPhone 构建通过；已覆盖安装到原手机，保留登录数据。构建/安装日志及当前二进制散列更新在安装回执中。滚动缓存的真机体验与首次下载速度仍分别待验收。


## 缓存验收后：直连图片速度对照

- 用户确认来回滚动已不重复下载，直连首次下载慢仍存在。
- 添加显式 DEBUG 公开图片速度探针；原生端只访问硬编码公开图片，忽略调用者 URL/正文/所有请求头，不使用绑定凭据。两轮相同 Range（前 65536 字节），比较原站 .133/.129 两节点的默认协议与强制 HTTP/1.1，以及 i.pixiv.re 的标准 HTTPS；每次最多 20 秒、64 KiB，所有连接保持证书验证，禁止跳转。正式图片图床与协议尚未更改。
- Mac 无代理相同原生实现对照 `/tmp/setu-pixiv-image-speed-mac.log`：两轮 .133 默认 2304/2812ms、HTTP/1.1 2369/2152ms；.129 默认 9457/5819ms、HTTP/1.1 2860/2499ms；镜像 1375/1153ms。全部 206、65536 字节。仅证明当前 Mac 网络的差异，不计作真机改善。
- 对照版原生构建、8 项原生测试和 iPhone 应用构建均通过，并已覆盖安装。启动探针因 iPhone 锁屏被系统拒绝（`/tmp/setu-pixiv-image-speed-probe-launch.log`），已请求用户解锁；没有产生新的手机速度结果。读取的旧 `pixiv-api-probe.txt` 不能用于此次比较。

- 手机解锁后，小段两轮完成（`/tmp/setu-pixiv-speed-phone-1.txt`）：原站与 HTTP/1.1 均无稳定优势，镜像也不是每轮更快。因此没有依据小段测量更改协议。
- 完整 990263 字节同图两轮（`/tmp/setu-pixiv-full-speed-phone-final.txt`）：原站默认协议和 HTTP/1.1 均四次 25 秒超时；i.pixiv.re 分别 3382/1639ms、HTTP 200、完整字节数。由此选择镜像改善持续下载，保留原站选项。
- 用户同时要求自定义图床。新增「图片设置 → 图片图床」：默认 i.pixiv.re、Pixiv 原站、自定义 HTTPS 域名；保持原图片路径，静态 i.pximg.net/i-cf.pximg.net 资源可切换，API/OAuth 不变。非法输入在保存前明确报错。自定义连接仅接受精确配置域名、公共解析地址、有效 HTTPS 证书和同域重定向；拒绝图片请求体及除 Referer/User-Agent/Accept/Range 外的请求头。无需额外 ATS 放宽。
- 缓存沿用，切换图床不重复下载已缓存图片；自定义/镜像 HTTP 错误提示图床返回的真实状态，并引导重试或切换。内置及自定义图床均复用媒体队列，页面 API 不受慢图片占用。
- 11 项客户端定向测试通过；原生 10 项通过、4 项显式外网诊断跳过；Swift 全量 300 项、2 项联网探针跳过、0 失败；真机构建通过。设置页与生产路径的真机下载验证另行记录。
- 正式连接真机公开原图验证 `/tmp/setu-pixiv-custom-production-phone.txt`：内置镜像 2617/1446ms，自定义域名连接分支（使用同一公开镜像域名）2730/1519ms，均 HTTP 200、990263 字节。证明此次正式传输代码改善同机完整下载；任意用户自有图床是否支持图片路径需依其实际服务验证。已恢复正常应用，首页和未缓存大图的可见体验等待用户反馈。
- 用户最终真机反馈（关闭代理，刷新首页并打开未看过的大图）：**首页和新大图都明显变快**。结合此前确认来回滚动不再重复下载，直连速度与滚动缓存分别通过真实可见体验验收。
- 图片图床设置页自动化：375pt 浅色、430pt 深色各 1 项通过；选择自定义、域名输入框、非法 HTTP 输入明确反馈、取消操作通过。截图已保存为 `docs/evidence/images-2026-09-08/image-host-settings-375-light.png` 与 `image-host-settings-430-dark.png`，排版无截断。
