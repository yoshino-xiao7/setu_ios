#if os(iOS)
import AVFoundation
import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

/// Explicitly selected development-only probes. Normal app SID/transport, no URLProtocol fixtures.
@MainActor
final class PlaybackContract3LiveTests: XCTestCase {
    private func environment() throws -> AppEnvironment {
        guard ProcessInfo.processInfo.environment["SETU_PLAYBACK3_LIVE"] == "1" else {
            throw XCTSkip("Explicit development live acceptance only")
        }
        let environment = AppEnvironment.live()
        XCTAssertEqual(environment.config.apiBaseURL.absoluteString, "https://api.yukiryou.icu")
        return environment
    }

    func testDevelopmentDualRepresentationSmoke() async throws {
        let env = try environment()
        let batch = try await env.musicV2Client.radioFM(limit: 4)
        let track = try XCTUnwrap(batch.tracks.first)
        guard case .success(let source) = try await env.musicV2Client.playback(trackID: track.id) else {
            return XCTFail("Real development playback must be playable")
        }
        XCTAssertNil(source.sourceExpiresAt)
        XCTAssertTrue(source.url.hasPrefix("https://"))
        XCTAssertFalse(source.refreshAt.isEmpty)
        let path = "/user/music/v2/tracks/" + track.id.rawValue + "/playback"
        do {
            let _: String = try await env.apiClient.get(path, signed: false)
            XCTFail("Unknown provider deadline cannot produce legacy success")
        } catch APIError.httpStatus(let status, _, _, _, let code) {
            XCTAssertEqual(status, 503); XCTAssertEqual(code, "UPSTREAM_UNAVAILABLE")
        }
        do {
            let _: String = try await env.apiClient.get(path, signed: false, headers: ["X-Setu-Playback-Contract": "invalid"])
            XCTFail("Invalid negotiation")
        } catch APIError.httpStatus(let status, _, _, _, let code) {
            XCTAssertEqual(status, 400); XCTAssertEqual(code, "INVALID_REQUEST")
        }
        print("PLAYBACK3_REAL_SMOKE_PASS source=true refresh=true sourceDeadline=null selectedVersion=3.0.0")
    }

    private func player(_ env: AppEnvironment) -> MusicPlaybackController {
        let player = MusicPlaybackController(persistsPlayback: false)
        player.urlResolver = PlaybackURLResolver(client: env.musicClient, v2: env.musicV2Client)
        return player
    }

    private func progressing(_ player: MusicPlaybackController, stage: String) async throws {
        for _ in 0..<60 {
            if (player.player?.currentTime().seconds ?? 0) > 1, player.playbackError == nil { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTFail("Real playback did not progress at \(stage); item=\(player.player?.currentItem?.status.rawValue ?? -1), error=\(player.playbackError ?? "none")")
        throw UserFacingError(message: "真实播放未推进")
    }

    func testRealFMProductionFeederAndControls() async throws {
        let env = try environment()
        let player = player(env)
        defer { player.stop() }
        player.startRadio(client: env.musicV2Client)
        await player.waitForRadioRefill()
        try await progressing(player, stage: "initial")
        XCTAssertTrue(player.context?.isInfinite == true)
        XCTAssertFalse(player.canPlayPrevious)
        XCTAssertEqual(player.playMode, .sequence)
        let first = try XCTUnwrap(player.currentTrack)
        guard case .canonical = first.id else { return XCTFail("Typed identity required") }
        await player.userSkip(by: -1)
        XCTAssertEqual(player.currentTrack?.id, first.id)
        player.cyclePlayMode()
        XCTAssertEqual(player.playMode, .sequence)
        let before = player.queueTracks.count
        player.clearUpcomingTracks()
        XCTAssertEqual(player.queueTracks.count, before)
        await player.blockRadioTrack(first)
        XCTAssertFalse(player.queueTracks.contains { $0.id == first.id })
        try await progressing(player, stage: "after-block")
        // Serial user advances exercise actual supply/refill and the production queue cap.
        for advance in 0..<52 {
            await player.userSkip(by: 1)
            await player.waitForRadioRefill()
            try await progressing(player, stage: "advance-\(advance)")
            XCTAssertLessThanOrEqual(player.queueTracks.count, 50)
            XCTAssertNil(player.playbackError)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertGreaterThanOrEqual(player.queueTracks.count, 45)
        player.resetForUserChange()
        await player.waitForRadioRefill()
        XCTAssertTrue(player.queueTracks.isEmpty)
        player.urlResolver = PlaybackURLResolver(client: env.musicClient, v2: env.musicV2Client)
        player.startRadio(client: env.musicV2Client)
        await player.waitForRadioRefill()
        try await progressing(player, stage: "reenter")
        print("P14_REAL_FM_FLOW_PASS serialAdvance=52 queueBound=50 block=setu userReset=true reenter=true")
    }

    func testRealAuthenticationFailureBackoffIsBounded() async throws {
        let env = try environment()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let client = MusicV2Client(apiClient: APIClient(config: env.config,
            signer: AuthSigner(keychain: env.keychain), session: URLSession(configuration: configuration)))
        var attempts: [TimeInterval] = []
        var failed = false
        let feeder = RadioFMFeeder(fetch: {
            attempts.append(ProcessInfo.processInfo.systemUptime)
            return try await client.radioFM(limit: 4)
        })
        defer { feeder.stop() }
        feeder.refill(remaining: 0, receive: { _ in XCTFail("Unauthenticated actual server must reject") }, failure: { _ in failed = true })
        feeder.refill(remaining: 0, receive: { _ in XCTFail("Duplicate flight") }, failure: { _ in failed = true })
        await feeder.waitForRefill()
        XCTAssertTrue(failed)
        XCTAssertEqual(attempts.count, 4)
        if attempts.count == 4 {
            for i in 1..<4 { XCTAssertGreaterThanOrEqual(attempts[i] - attempts[i - 1], Double(1 << (i - 1))) }
        }
        print("P14_REAL_AUTH_FAILURE_PASS attempts=4 backoff=1/2/4 duplicateFlight=false")
    }
}
#endif
