import Foundation
import Network
import Security
#if canImport(SetuPixivTransport)
import SetuPixivTransport
#endif

/// Owns a short-lived, authenticated loopback proxy for one nonpersistent login WebView.
/// No certificate is installed in the system trust store. Only this instance's exact
/// certificate may be anchored, and upstream TLS still verifies Pixiv's real certificate.
public final class PixivLoginTunnel {
    public let configuration: ProxyConfiguration
    public let certificate: Data
    private static let hosts: Set<String> = ["app-api.pixiv.net", "accounts.pixiv.net", "oauth.secure.pixiv.net", "www.pixiv.net", "i.pximg.net", "s.pximg.net", "i-cf.pximg.net"]
    #if canImport(SetuPixivTransport)
    private var handle: OpaquePointer?
    #endif

    public init() throws {
        #if canImport(SetuPixivTransport)
        let password = UUID().uuidString
        guard let session = password.withCString({ setu_pixiv_login_start($0) }) else {
            throw PixivClientError("无法准备安全登录连接，请关闭登录页后重试")
        }
        handle = session
        let port = setu_pixiv_login_port(session)
        let count = setu_pixiv_login_certificate_length(session)
        guard port > 0, count > 0, count < 16384, let bytes = setu_pixiv_login_certificate(session) else {
            setu_pixiv_login_free(session); handle = nil
            throw PixivClientError("无法准备安全登录连接，请重试")
        }
        certificate = Data(bytes: bytes, count: count)
        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
        proxy.applyCredential(username: "setu", password: password)
        proxy.matchDomains = ["pixiv.net", "pximg.net"]
        proxy.allowFailover = false
        configuration = proxy
        #else
        throw PixivClientError("此构建尚未包含安全登录组件")
        #endif
    }

    public func handles(host: String) -> Bool { Self.hosts.contains(host) }

    public func accepts(_ trust: SecTrust, host: String) -> Bool {
        guard Self.hosts.contains(host), let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, SecCertificateCopyData(leaf) as Data == certificate,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

    public var connectionStage: UInt32 {
        #if canImport(SetuPixivTransport)
        return handle.map { setu_pixiv_login_stage($0) } ?? 0
        #else
        return 0
        #endif
    }

    public func close() {
        #if canImport(SetuPixivTransport)
        if let handle { setu_pixiv_login_free(handle); self.handle = nil }
        #endif
    }
    deinit { close() }
}
