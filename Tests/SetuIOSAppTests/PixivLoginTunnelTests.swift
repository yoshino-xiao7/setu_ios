import Foundation
import Network
import Security
import XCTest
@testable import SetuIOSCore

final class PixivLoginTunnelTests: XCTestCase {
    func testWebViewTrustRequiresExactSessionCertificateAndPixivHost() throws {
        let first = try PixivLoginTunnel()
        let second = try PixivLoginTunnel()
        defer { first.close(); second.close() }
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, first.certificate as CFData))
        var optionalTrust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "accounts.pixiv.net" as CFString), &optionalTrust), errSecSuccess)
        let trust = try XCTUnwrap(optionalTrust)
        XCTAssertTrue(first.accepts(trust, host: "accounts.pixiv.net"))
        XCTAssertFalse(first.accepts(trust, host: "attacker.invalid"))
        XCTAssertFalse(second.accepts(trust, host: "accounts.pixiv.net"))
        XCTAssertFalse(first.configuration.allowFailover)
        XCTAssertEqual(first.configuration.matchDomains, ["pixiv.net", "pximg.net"])
    }
}

// Opt-in diagnostic: real Apple networking -> authenticated loopback -> verified ECH.
// No Pixiv account, password, authorization code or token is used by this probe.
extension PixivLoginTunnelTests {
    func testLiveLoginTransportWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["SETU_PIXIV_LOGIN_LIVE_TEST"] == "1" else {
            throw XCTSkip("Live public login-page transport probe is opt-in")
        }
        let tunnel = try PixivLoginTunnel()
        defer { tunnel.close() }
        let delegate = LoginProbeDelegate(tunnel: tunnel)
        let config = URLSessionConfiguration.ephemeral
        config.proxyConfigurations = [tunnel.configuration]
        config.timeoutIntervalForRequest = 50
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: URL(string: "https://accounts.pixiv.net/login")!)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue([200, 403].contains(http.statusCode), "Expected login HTML or an explicit upstream network-policy response")
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertTrue(delegate.sawPinnedCertificate)
        print("Pixiv login transport HTTP \(http.statusCode); pinned local TLS and verified upstream TLS")
    }
}

private final class LoginProbeDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let tunnel: PixivLoginTunnel
    private let lock = NSLock()
    private var accepted = false
    var sawPinnedCertificate: Bool { lock.lock(); defer { lock.unlock() }; return accepted }
    init(tunnel: PixivLoginTunnel) { self.tunnel = tunnel }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust, tunnel.accepts(trust, host: challenge.protectionSpace.host) {
            lock.lock(); accepted = true; lock.unlock()
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}
