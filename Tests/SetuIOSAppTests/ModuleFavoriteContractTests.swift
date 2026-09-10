import Foundation
import XCTest
@testable import SetuIOSCore

final class ModuleFavoriteContractTests: XCTestCase {
    override func tearDown() {
        FavoriteContractURLProtocol.handler = nil
        super.tearDown()
    }

    func testListSignsOnlyThePathAndPreservesPaginationQuery() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://favorites.example/module-favorites?module=ASMR&page=2&size=24")
            self.assertSigned(request, method: "GET", path: "/module-favorites")
            return (200, #"{"page":2,"size":24,"total":25,"items":[{"id":7,"module":"ASMR","externalId":"rain","title":"雨声"}]}"#)
        }
        let result = try await client.list(module: .asmr, page: 2)
        XCTAssertEqual(result.page, 2)
        XCTAssertEqual(result.items.first?.favoriteId, 7)
    }

    func testAddSignsAndSendsSnapshotWithoutAnOwnerId() async throws {
        let client = makeClient { request in
            self.assertSigned(request, method: "POST", path: "/module-favorites")
            let body = try self.body(request)
            XCTAssertEqual(body["externalId"] as? String, "rain")
            XCTAssertEqual(body["title"] as? String, "雨声")
            XCTAssertNil(body["userId"])
            return (200, #"{"id":7,"module":"ASMR","externalId":"rain","title":"雨声","createdAt":"2026-09-10 12:00:00"}"#)
        }
        let result = try await client.add(.init(module: .asmr, externalId: "rain", title: "雨声"))
        XCTAssertEqual(result.favoriteId, 7)
        XCTAssertNotNil(result.createdAt)
    }

    func testDeleteKeepsReservedCharactersInsideOneSignedPathSegment() async throws {
        let client = makeClient { request in
            self.assertSigned(request, method: "DELETE", path: "/module-favorites/ASMR/rain%3Fpart%23one%25")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.url?.fragment)
            return (200, "ok")
        }
        try await client.remove(module: .asmr, externalId: "rain?part#one%")
    }

    func testExistsDecodesBooleanAndSigns() async throws {
        let client = makeClient { request in
            self.assertSigned(request, method: "GET", path: "/module-favorites/ASMR/exists/rain")
            return (200, "true")
        }
        let exists = try await client.exists(module: .asmr, externalId: "rain")
        XCTAssertTrue(exists)
    }

    func testBatchDeduplicatesAndChunksAtServerLimit() async throws {
        let counts = FavoriteContractCounts()
        let client = makeClient { request in
            self.assertSigned(request, method: "POST", path: "/module-favorites/exists-batch")
            let ids = try XCTUnwrap(self.body(request)["externalIds"] as? [String])
            counts.append(ids.count)
            let payload = ["exists": Dictionary(uniqueKeysWithValues: ids.map { ($0, true) })]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (200, String(decoding: data, as: UTF8.self))
        }
        let ids = (0..<101).map { "item-\($0)" }
        let result = try await client.existsBatch(module: .asmr, externalIds: ids + ids)
        XCTAssertEqual(counts.values, [100, 1])
        XCTAssertEqual(result.count, 101)
    }

    func testEmptyBatchDoesNotSendARequest() async throws {
        let client = makeClient { _ in XCTFail("Empty batches must stay local"); return (200, "{}") }
        let result = try await client.existsBatch(module: .asmr, externalIds: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testInvalidPathIdsAreRejectedLocally() async throws {
        let client = makeClient { _ in XCTFail("Invalid IDs must stay local"); return (200, "false") }
        for id in ["", "..", ".", "a/b", "a\\b", "a\nb"] {
            do {
                _ = try await client.exists(module: .asmr, externalId: id)
                XCTFail("Expected invalid ID to fail")
            } catch APIError.invalidURL { }
        }
    }

    func testUnauthorizedDoesNotBecomeNotFavorited() async throws {
        let client = makeClient { _ in (401, #"{"message":"未登录"}"#) }
        do {
            _ = try await client.exists(module: .asmr, externalId: "rain")
            XCTFail("Unauthorized must be surfaced to the login flow")
        } catch APIError.httpStatus(let status, _, _, _, _) {
            XCTAssertEqual(status, 401)
        }
    }

    private func makeClient(handler: @escaping (URLRequest) throws -> (Int, String)) -> ModuleFavoriteClient {
        FavoriteContractURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavoriteContractURLProtocol.self]
        return ModuleFavoriteClient(apiClient: APIClient(
            config: .init(apiBaseURL: URL(string: "https://favorites.example")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: FavoriteContractKeychain()),
            session: URLSession(configuration: configuration)))
    }

    private func assertSigned(_ request: URLRequest, method: String, path: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.httpMethod, method, file: file, line: line)
        XCTAssertEqual(request.url?.host, "favorites.example", file: file, line: line)
        XCTAssertEqual(request.url?.path(percentEncoded: true), path, file: file, line: line)
        let timestamp = request.value(forHTTPHeaderField: "X-Timestamp") ?? ""
        let nonce = request.value(forHTTPHeaderField: "X-Nonce") ?? ""
        XCTAssertFalse(timestamp.isEmpty, file: file, line: line)
        XCTAssertFalse(nonce.isEmpty, file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Signature"),
                       AuthSigner.hmac(message: "\(timestamp):\(nonce):\(method):\(path)", secret: "fixture-secret"), file: file, line: line)
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private struct FavoriteContractKeychain: KeychainStoring {
    func string(for key: String) throws -> String? { key == "signSecret" ? "fixture-secret" : nil }
    func setString(_ value: String, for key: String) throws { }
    func remove(_ key: String) throws { }
}

private final class FavoriteContractCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int] = []
    var values: [Int] { lock.withLock { counts } }
    func append(_ count: Int) { lock.withLock { counts.append(count) } }
}

private final class FavoriteContractURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler?(request) ?? (500, "{}")
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
