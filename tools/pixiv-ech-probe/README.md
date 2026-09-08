# Pixiv ECH 连接诊断

独立编写的 macOS 开发探针，使用公开 rustls / reqwest API；未嵌入 Flutter 或复制 Pixez 网络库。仅用于验证连接，尚未接入 iOS 应用。Rust 依赖只属于此工具，不是应用生产依赖。

安装 Rust 工具链后运行：

```sh
python3 tools/pixiv-ech-probe/run.py --interface en0
```

`en0` 必须是本机实际物理网络接口。省略 `--interface` 时走系统路由，可能经过 VPN/TUN；`no_proxy` 仅关闭应用 HTTP 代理。工具不会修改系统代理、路由或 VPN。需要访问公共 AliDNS HTTPS 查询和 Pixiv 服务，不读取账号、Cookie、Keychain 或环境中的账号令牌。

检查分为三步：

1. 指定 Pixiv ECH 入口，验证证书链/域名并确认 `EchStatus::Accepted`。
2. 用 HTTP/2 请求公开登录页和无认证 API；推荐接口 400（缺少令牌）、OAuth GET 404 都只证明请求到达服务，不证明账号授权成功。
3. 默认图床指定地址、无 SNI 连接，仍验证证书链与 `i.pximg.net` 域名，只读已知公开图片前四字节。若证书不通过会失败，绝不关闭证书校验。

入口 IP 和 ECH 引导服务依据核实的 Pixez 网络配置；这些值可能变化。工具当前面向 macOS / Apple Silicon，不能把 Mac 的结果当成真机结果。首次网页登录、授权码交换、令牌刷新、真实推荐、收藏/关注写入仍需单独验证。

参考：[Pixez 网络配置](https://github.com/Notsfsssf/pixez-flutter/blob/master/lib/network/pixez_network_settings.dart)、[rustls ECH](https://docs.rs/rustls/0.23.43/rustls/client/struct.EchConfig.html)。
