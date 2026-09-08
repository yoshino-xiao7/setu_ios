import SetuIOSCore
import SwiftUI
#if os(iOS)
import WebKit

struct PixivAuthorizationView: View {
    let authorization: PixivAuthorization
    let client: ArtworkClient
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var exchanging = false
    @State private var error: String?
    @State private var enhancedConnection = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let url = URL(string: authorization.loginUrl), url.scheme == "https", url.host == "app-api.pixiv.net" {
                PixivLoginWebView(url: url, enhancedConnection: enhancedConnection, failed: { error = $0 }) { code in
                    guard !exchanging else { return }
                    exchanging = true
                    Task {
                        do {
                            _ = try await client.complete(sessionID: authorization.sessionId, code: code)
                            completed(); dismiss()
                        } catch { self.error = "网页授权已返回，绑定未完成：" + error.localizedDescription }
                    }
                }.id(enhancedConnection)
                } else { Text("授权地址无效，请关闭后重新开始").padding() }
                if exchanging { Color.black.opacity(0.15).ignoresSafeArea(); ProgressView("正在完成绑定").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }
            .navigationTitle("登录 Pixiv").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(exchanging)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(exchanging) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("标准连接", systemImage: enhancedConnection ? "circle" : "checkmark.circle") { enhancedConnection = false }
                        Button("增强连接", systemImage: enhancedConnection ? "checkmark.circle" : "circle") { enhancedConnection = true }
                    } label: { Label("连接方式", systemImage: "network") }.disabled(exchanging)
                }
            }
            .alert("绑定未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                if !exchanging {
                    Button(enhancedConnection ? "使用标准连接" : "尝试增强连接") { enhancedConnection.toggle() }
                }
                Button("关闭并重新开始") { dismiss() }
            } message: { Text(error ?? "请重新登录") }
        }
    }
}

struct PixivLoginWebView: UIViewRepresentable {
    let url: URL
    var enhancedConnection = false
    let failed: (String) -> Void
    let codeReceived: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(codeReceived: codeReceived, failed: failed) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if enhancedConnection {
        do {
            let tunnel = try PixivLoginTunnel()
            context.coordinator.tunnel = tunnel
            configuration.websiteDataStore.proxyConfigurations = [tunnel.configuration]
        } catch {
            DispatchQueue.main.async { failed(error.localizedDescription) }
        }
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        if !enhancedConnection || context.coordinator.tunnel != nil {
            // ATS exceptions permit our exact in-process anchor; plaintext web loads remain forbidden.
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "pixiv-login-https-only",
                encodedContentRuleList: #"[{"trigger":{"url-filter":"^http://"},"action":{"type":"block"}}]"#) { [weak view] rules, _ in
                DispatchQueue.main.async {
                    guard let view, let rules else { failed("无法准备安全登录页面，请关闭后重试"); return }
                    view.configuration.userContentController.add(rules)
                    view.load(URLRequest(url: url))
                }
            }
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading(); coordinator.tunnel?.close(); coordinator.tunnel = nil
        uiView.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let codeReceived: (String) -> Void
        private var delivered = false
        var tunnel: PixivLoginTunnel?
        let failed: (String) -> Void
        init(codeReceived: @escaping (String) -> Void, failed: @escaping (String) -> Void) { self.codeReceived = codeReceived; self.failed = failed }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled && !delivered { report(error) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled && !delivered { report(error) }
        }
        private func record(_ value: String) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-pixiv-login-probe") {
                let url = URL.documentsDirectory.appending(path: "pixiv-login-probe.txt")
                let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try? (previous + "\n" + value).write(to: url, atomically: true, encoding: .utf8)
            }
            #endif
        }
        private func report(_ error: Error) {
            let code = (error as NSError).code
            let stage = tunnel?.connectionStage ?? 0
            record("failed code=\(code) underlying=\(((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? 0) stage=\(stage)")
            failed("无法连接 Pixiv 登录页面（\(code)/\(stage)），请关闭后重试")
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Count fields only; never read input values, page text or credentials.
            webView.evaluateJavaScript("document.querySelectorAll('input').length") { [weak self] count, _ in
                self?.record("loaded inputs=\(count as? Int ?? 0) stage=\(self?.tunnel?.connectionStage ?? 0)")
            }
        }
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            record("challenge \(challenge.protectionSpace.authenticationMethod) host=\(challenge.protectionSpace.host)")
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust,
               tunnel?.accepts(trust, host: challenge.protectionSpace.host) == true {
                record("pinned stage=\(tunnel?.connectionStage ?? 0)")
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                      tunnel?.handles(host: challenge.protectionSpace.host) == true {
                completionHandler(.cancelAuthenticationChallenge, nil)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "pixiv", url.host == "account", url.path == "/login" {
                if !delivered, let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                    delivered = true; codeReceived(code)
                }
                decisionHandler(.cancel)
            } else { decisionHandler(["https", "about"].contains(url.scheme ?? "") ? .allow : .cancel) }
        }
    }
}
#endif
