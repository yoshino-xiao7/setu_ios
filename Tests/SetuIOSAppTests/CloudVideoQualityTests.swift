import CoreGraphics
import XCTest
@testable import SetuIOSCore

final class CloudVideoQualityTests: XCTestCase {
    func testDefaultsStoredPreferenceTo720p() {
        let defaults = UserDefaults(suiteName: "cloud-video-quality-\(UUID().uuidString)")!
        XCTAssertEqual(CloudVideoQuality.maxHeight(defaults: defaults), 720)

        CloudVideoQuality.saveMaxHeight(1080, defaults: defaults)
        XCTAssertEqual(CloudVideoQuality.maxHeight(defaults: defaults), 1080)
    }

    func testCapsAt720pWhenTheLadderIncludesIt() {
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 720, available: [240, 360, 480, 720, 1080]), 720)
    }

    func testUsesHighestRungAtOrBelow720pWhen720pIsMissing() {
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 720, available: [240, 480, 1080]), 480)
    }

    func testStaysOnLowestAvailableRungWhenEveryRungIsAboveTheCap() {
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 720, available: [1080, 1440]), 1080)
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 240, available: [240, 720]), 240)
    }

    func testListsOnlyRungsPresentInTheHLSLadder() {
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: [1080, 720, 720, 480]), [480, 720, 1080])
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: []), [])
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: [1080]), [1080])
    }

    func testLabels720pAsTheDefaultOption() {
        XCTAssertEqual(CloudVideoQuality.label(for: 720), "720p（默认）")
        XCTAssertEqual(CloudVideoQuality.label(for: 1080), "1080p")
    }

    func testMaximumResolutionUses16By9AtTheCappedHeight() {
        XCTAssertEqual(CloudVideoQuality.maximumResolution(forMaxHeight: 720), CGSize(width: 1280, height: 720))
        XCTAssertEqual(CloudVideoQuality.maximumResolution(forMaxHeight: 1080), CGSize(width: 1920, height: 1080))
    }
}

final class CloudVideoHLSPlaylistTests: XCTestCase {
    func testReadsOnlyPlayableStreamHeightsFromTheMasterPlaylist() {
        let master = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,FRAME-RATE=30
        360p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480
        480p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        720p/playlist.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        1080p/playlist.m3u8
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100000,RESOLUTION=1920x1080,URI="iframe.m3u8"
        """
        XCTAssertEqual(CloudVideoHLSPlaylist.streamHeights(fromMaster: master), [360, 480, 720, 1080])
    }

    func testIgnoresPlaylistsWithoutStreamInfResolution() {
        XCTAssertEqual(CloudVideoHLSPlaylist.streamHeights(fromMaster: "#EXTM3U\n#EXTINF:10,\nsegment.ts\n"), [])
    }

    func testPlaybackHeadersUseTheSiteOrigin() {
        let headers = CloudVideoHLSPlaylist.playbackHeaders(siteBaseURL: URL(string: "https://cloud.yukiryou.icu")!)
        XCTAssertEqual(headers["Origin"], "https://cloud.yukiryou.icu")
        XCTAssertEqual(headers["Referer"], "https://cloud.yukiryou.icu/")
    }
}

final class CloudVideoCDNTests: XCTestCase {
    func testRecognizesBunnyPullZoneHosts() {
        XCTAssertTrue(CloudVideoCDN.isImageCDN(URL(string: "https://vz-example.b-cdn.net/guid/thumbnail.jpg")!))
        XCTAssertTrue(CloudVideoCDN.isImageCDN(URL(string: "https://iframe.mediadelivery.net/embed/1/guid")!))
        XCTAssertFalse(CloudVideoCDN.isImageCDN(URL(string: "https://cdn.example.com/cover.jpg")!))
        XCTAssertFalse(CloudVideoCDN.isImageCDN(URL(string: "https://not-b-cdn.net.example/cover.jpg")!))
    }

    func testImageRequestKeepsTheSignedThumbnailQuery() {
        let url = URL(string: "https://vz-example.b-cdn.net/guid-123/thumbnail.jpg?token=HS256-abc_def&expires=1700000000")!
        let request = CloudVideoCDN.imageRequest(
            url: url,
            siteBaseURL: URL(string: "https://cloud.yukiryou.icu")!
        )
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), CloudVideoCDN.userAgent)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cloud.yukiryou.icu")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://cloud.yukiryou.icu/")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
    }
}
