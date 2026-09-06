import XCTest
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class NowPlayingLyricsModelTests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }

    func testCanonicalUsesP9CacheAndSheetReturnDoesNotReparse() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            return .init(body: Data(p13WordJSON.utf8))
        }
        let model = NowPlayingLyricsModel(), environment = p13Environment()
        let identity = MusicPlaybackIdentity.canonical(.init(rawValue: "netease:track:1"))
        let before = MusicPerformanceProbe.shared.parseCount
        await model.load(identity: identity, environment: environment)
        await model.load(identity: identity, environment: environment)
        XCTAssertEqual(capture.requests.map { $0.url!.path }, ["/user/music/v2/tracks/netease:track:1/lyrics"])
        XCTAssertEqual(MusicPerformanceProbe.shared.parseCount - before, 1)
        guard case .loaded(let lines) = model.state else { return XCTFail("Expected structured lyrics") }
        XCTAssertEqual(lines.first?.words.count, 2)
    }

    func testFlagOffMakesNoCanonicalRequestAndDoesNotInferLegacyID() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in capture.append(request); return .init(body: Data(p13WordJSON.utf8)) }
        let model = NowPlayingLyricsModel()
        await model.load(identity: .canonical(.init(rawValue: "netease:track:1")), environment: p13Environment(word: false, transport: false))
        XCTAssertTrue(capture.requests.isEmpty)
        guard case .failed = model.state else { return XCTFail("Disabled entry must be explicit") }
    }

    func testFailureIsNotEmptyLyricsAndRetryWorks() async {
        let model = NowPlayingLyricsModel(), environment = p13Environment()
        MusicV2URLProtocol.handler = { _ in .init(status: 503, body: Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"暂不可用","retryable":true,"traceId":null}"#.utf8)) }
        let id = MusicPlaybackIdentity.canonical(.init(rawValue: "netease:track:1"))
        await model.load(identity: id, environment: environment)
        guard case .failed = model.state else { return XCTFail("503 is not none") }
        MusicV2URLProtocol.handler = { _ in .init(body: Data(p13WordJSON.utf8)) }
        await model.load(identity: id, environment: environment)
        guard case .loaded = model.state else { return XCTFail("Retry should load") }
    }

    func testInvalidateRejectsInFlightResult() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            Thread.sleep(forTimeInterval: 0.12)
            return .init(body: Data(p13WordJSON.utf8))
        }
        let model = NowPlayingLyricsModel(), environment = p13Environment()
        let task = Task { await model.load(identity: .canonical(.init(rawValue: "netease:track:1")), environment: environment) }
        for _ in 0..<100 where capture.requests.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(capture.requests.isEmpty)
        model.invalidate()
        await task.value
        XCTAssertNil(model.identity)
        guard case .idle = model.state else { return XCTFail("Old owner flight must not publish") }
    }
}

let p13WordJSON = #"{"trackId":"netease:track:1","kind":"word","lines":[{"text":"你好世界","words":[{"text":"你好","startMs":1000,"durationMs":200},{"text":"世界","startMs":1300,"durationMs":400}],"startMs":1000,"durationMs":700,"translation":"Hello world"}],"hasTranslation":true,"contributors":[]}"#

@MainActor
func p13Environment(word: Bool = true, transport: Bool = true, airPlay: Bool = false) -> AppEnvironment {
    let base = SetuPreviewEnvironment.make()
    var flags = MusicFeatureFlags()
    flags.wordByWordLyricsEnabled = word
    flags.usesV2Lyrics = transport
    flags.airPlayPickerEnabled = airPlay
    return AppEnvironment(config: AppConfig(apiBaseURL: base.config.apiBaseURL, siteBaseURL: base.config.siteBaseURL, musicFeatureFlags: flags),
        keychain: base.keychain,
        apiClient: base.apiClient,
        mobileAppClient: base.mobileAppClient,
        publicBlogClient: base.publicBlogClient,
        dashboardClient: base.dashboardClient,
        apiKeyClient: base.apiKeyClient,
        pointsClient: base.pointsClient,
        imageFeedClient: base.imageFeedClient,
        notificationClient: base.notificationClient,
        statusClient: base.statusClient,
        userProfileClient: base.userProfileClient,
        passkeyClient: base.passkeyClient,
        appleAuthClient: base.appleAuthClient,
        collectionClient: base.collectionClient,
        aiGenerationClient: base.aiGenerationClient,
        favoriteClient: base.favoriteClient,
        imageDeleteRequestClient: base.imageDeleteRequestClient,
        musicClient: base.musicClient,
        musicV2Client: makeMusicV2Client(),
        downloadClient: base.downloadClient,
        galleryUploadClient: base.galleryUploadClient,
        adminClient: base.adminClient,
        authSession: base.authSession)
}
