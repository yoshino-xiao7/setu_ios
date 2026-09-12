import CryptoKit
import Foundation
import ImageIO
import CoreGraphics
import XCTest
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(UIKit)
import UIKit
#endif
@testable import SetuIOSApp
@testable import SetuIOSCore

final class ModuleFavoriteClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ModuleFavoriteMockURLProtocol.handler = nil
    }

    func testListUsesModuleQuery() async throws {
        let probe = SyncRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"page":1,"size":24,"total":1,"items":[{"id":9,"module":"ASMR","externalId":"41001","title":"第一夜"}]}"#
        }

        let page = try await client.list(module: .asmr, page: 1, size: 24)

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items.first?.externalId, "41001")
        XCTAssertEqual(page.items.first?.id, "ASMR:41001")
        XCTAssertEqual(probe.lastURL, "https://api.example.com/module-favorites?module=ASMR&page=1&size=24")
    }

    func testAddPostsSnapshot() async throws {
        let probe = SyncRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"id":3,"module":"JM","externalId":"88001","title":"示例本子"}"#
        }

        let item = try await client.add(ModuleFavoriteSnapshot(module: .jm, externalId: "88001", title: "示例本子"))

        XCTAssertEqual(item.module, .jm)
        XCTAssertEqual(item.externalId, "88001")
        XCTAssertEqual(probe.lastURL, "https://api.example.com/module-favorites")
        XCTAssertEqual(probe.lastMethod, "POST")
    }

    func testExistsBatchDecodesMap() async throws {
        let client = makeClient { _ in
            #"{"exists":{"41001":true,"41002":false}}"#
        }

        let map = try await client.existsBatch(module: .asmr, externalIds: ["41001", "41002"])

        XCTAssertEqual(map["41001"], true)
        XCTAssertEqual(map["41002"], false)
    }

    private func makeClient(handler: @escaping (URLRequest) -> String) -> ModuleFavoriteClient {
        ModuleFavoriteMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModuleFavoriteMockURLProtocol.self]
        let keychain = TestKeychain()
        try? keychain.setString("secret", for: "signSecret")
        return ModuleFavoriteClient(
            apiClient: APIClient(
                config: AppConfig(
                    apiBaseURL: URL(string: "https://api.example.com")!,
                    siteBaseURL: URL(string: "https://example.com")!
                ),
                signer: AuthSigner(keychain: keychain),
                session: URLSession(configuration: configuration)
            )
        )
    }
}

final class AsmrCatalogClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ModuleFavoriteMockURLProtocol.handler = nil
    }

    func testWorksDecodesPaginationAndCover() async throws {
        let probe = SyncRequestProbe()
        let client = makeAsmrClient { request in
            probe.capture(request)
            return """
            {"pagination":{"currentPage":1,"pageSize":20,"totalCount":2},"works":[{"id":41001,"title":"第一夜","circle":{"name":"雪社"},"mainCoverUrl":"https://cdn.example.com/a.jpg","duration":3660}]}
            """
        }

        let page = try await client.works(page: 1, pageSize: 20)

        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.works.first?.displayTitle, "第一夜")
        XCTAssertEqual(page.works.first?.circleName, "雪社")
        XCTAssertEqual(page.works.first?.coverURL, "https://cdn.example.com/a.jpg")
        XCTAssertTrue(probe.lastURL?.contains("/api/works") == true)
        XCTAssertFalse(probe.lastURL?.contains("api.example.com") == true)
        XCTAssertEqual(probe.lastOrigin, "https://www.asmr.one")
        XCTAssertEqual(probe.lastReferer, "https://www.asmr.one/")
    }

    func testTracksFlattensAudioFiles() async throws {
        let client = makeAsmrClient { _ in
            """
            [{"type":"folder","title":"CD1","children":[{"type":"audio","title":"01.mp3","mediaStreamUrl":"https://cdn.example.com/01.mp3","hash":"a1","duration":120}]}]
            """
        }

        let tracks = try await client.tracks(workID: "41001")

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.title, "01.mp3")
        XCTAssertEqual(tracks.first?.url.absoluteString, "https://cdn.example.com/01.mp3")
    }

    private func makeAsmrClient(handler: @escaping (URLRequest) -> String) -> AsmrCatalogClient {
        ModuleFavoriteMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModuleFavoriteMockURLProtocol.self]
        return AsmrCatalogClient(
            session: URLSession(configuration: configuration),
            baseURLs: [URL(string: "https://api.asmr.one")!]
        )
    }
}

final class JmCatalogClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ModuleFavoriteMockURLProtocol.handler = nil
    }

    func testAlbumsDecodeListAndFillCover() async throws {
        let probe = SyncRequestProbe()
        let client = makeJmClient { request in
            probe.capture(request)
            return #"{"list":[{"id":88001,"name":"示例本子","author":["画师A"],"tags":["百合"]}],"total":8}"#
        }

        let page = try await client.albums(page: 1)

        XCTAssertEqual(page.total, 8)
        XCTAssertEqual(page.albums.first?.title, "示例本子")
        XCTAssertEqual(page.albums.first?.author, "画师A")
        XCTAssertEqual(page.albums.first?.coverURL, "https://cdn.example.com/media/albums/88001.jpg")
        XCTAssertTrue(probe.lastURL?.contains("/categories/filter?") == true)
        XCTAssertTrue(probe.lastURL?.contains("page=1") == true)
        XCTAssertTrue(probe.lastURL?.contains("c=0") == true)
        XCTAssertFalse(probe.lastURL?.contains("/latest") == true)
        XCTAssertFalse(probe.lastURL?.contains("api.example.com") == true)
        XCTAssertEqual(probe.lastToken, JmAppToken.token(timestamp: "1700000000"))
        XCTAssertEqual(probe.lastUserAgent, JmAppToken.userAgent)
        XCTAssertEqual(probe.lastVersion, JmAppToken.appVersion)
    }

    func testAlbumsDecodePublishedCategoryPayloadWithStringTotal() async throws {
        let client = makeJmClient { _ in
            """
            {"search_query":"","total":"177","content":[{"id":"441923","author":"MANA","description":"","name":"[MANA] 神里绫华5","image":"","category":{"id":"1","title":"同人"},"category_sub":{"id":"1","title":"同人"}}]}
            """
        }

        let page = try await client.albums(page: 1)

        XCTAssertEqual(page.total, 177)
        XCTAssertEqual(page.albums.count, 1)
        XCTAssertEqual(page.albums.first?.id, "441923")
        XCTAssertEqual(page.albums.first?.title, "[MANA] 神里绫华5")
        XCTAssertEqual(page.albums.first?.author, "MANA")
        XCTAssertEqual(page.albums.first?.coverURL, "https://cdn.example.com/media/albums/441923.jpg")
    }

    func testAlbumsDecodeStringTagsWithoutFailingThePage() async throws {
        let client = makeJmClient { _ in
            #"{"list":[{"id":88001,"name":"示例本子","author":"画师A","tags":"百合,纯爱"}],"total":1}"#
        }

        let page = try await client.albums(page: 1)

        XCTAssertEqual(page.albums.first?.author, "画师A")
        XCTAssertEqual(page.albums.first?.tags, ["百合", "纯爱"])
    }

    func testAlbumsDecryptWrappedAesPayload() async throws {
        let plaintext = #"{"list":[{"id":88001,"name":"加密本子","author":["画师A"],"tags":["百合"]}],"total":8}"#
        let envelope = jmEncryptedEnvelope(plaintext, timestamp: "1700000000", secret: "185Hcomic3PAPP7R")
        let client = makeJmClient { _ in envelope }

        let page = try await client.albums(page: 1)

        XCTAssertEqual(page.total, 8)
        XCTAssertEqual(page.albums.first?.title, "加密本子")
        XCTAssertEqual(page.albums.first?.id, "88001")
    }

    func testAlbumsDecryptPublishedCategoryPayloadWithStringTotal() async throws {
        let plaintext = #"{"search_query":"","total":"177","content":[{"id":"441923","author":"MANA","name":"[MANA] 神里绫华5","image":""}]}"#
        let envelope = jmEncryptedEnvelope(plaintext, timestamp: "1700000000", secret: "185Hcomic3PAPP7R")
        let client = makeJmClient { _ in envelope }

        let page = try await client.albums(page: 1)

        XCTAssertEqual(page.total, 177)
        XCTAssertEqual(page.albums.first?.id, "441923")
        XCTAssertEqual(page.albums.first?.coverURL, "https://cdn.example.com/media/albums/441923.jpg")
    }

    func testSearchAlbumIDFetchesAlbumInsteadOfEmptyContent() async throws {
        let probe = SyncRequestProbe()
        let client = makeJmClient { request in
            probe.capture(request)
            let path = request.url?.path ?? ""
            if path == "/album" {
                return #"{"id":310311,"name":"车牌本子","author":["画师A"],"image":""}"#
            }
            return #"{"search_query":"310311","total":1,"redirect_aid":"310311","content":[]}"#
        }

        let page = try await client.albums(page: 1, keyword: "310311")

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.albums.first?.id, "310311")
        XCTAssertEqual(page.albums.first?.title, "车牌本子")
        XCTAssertEqual(page.albums.first?.coverURL, "https://cdn.example.com/media/albums/310311.jpg")
        XCTAssertTrue(probe.lastURL?.contains("/album") == true)
        XCTAssertTrue(probe.lastURL?.contains("id=310311") == true)
    }

    func testSearchPrefixedAlbumIDAndRedirectAidResolveToAlbum() async throws {
        let client = makeJmClient { request in
            let path = request.url?.path ?? ""
            if path == "/album" {
                return #"{"id":"88001","name":"前缀车牌","author":"画师A","image":""}"#
            }
            return #"{"search_query":"not-an-id","total":1,"redirect_aid":"88001","content":[]}"#
        }

        let prefixed = try await client.albums(page: 1, keyword: "JM88001")
        XCTAssertEqual(prefixed.albums.first?.id, "88001")
        XCTAssertEqual(prefixed.albums.first?.title, "前缀车牌")

        let redirected = try await client.albums(page: 1, keyword: "神里")
        XCTAssertEqual(redirected.albums.first?.id, "88001")
        XCTAssertEqual(redirected.albums.first?.title, "前缀车牌")
    }

    func testPagesBuildImageURLs() async throws {
        let client = makeJmClient { _ in
            #"{"id":88001,"images":["00001.webp","00002.webp"],"scramble_id":220980}"#
        }

        let pages = try await client.pages(chapterID: "88001")

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.first?.url.absoluteString, "https://cdn.example.com/media/photos/88001/00001.webp")
        XCTAssertEqual(pages.first?.albumID, 88001)
        XCTAssertEqual(pages.first?.scrambleID, 220980)
    }

    func testImageRequestUsesAppCDNHeaders() {
        let url = URL(string: "https://cdn-msp.jmapiproxy1.cc/media/albums/441923.jpg")!
        XCTAssertTrue(JmAppToken.isImageCDN(url))
        XCTAssertFalse(JmAppToken.isImageCDN(URL(string: "https://cdn.example.com/cover.jpg")!))
        let request = JmAppToken.imageRequest(url: url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.cdnhjk.net/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "com.JMComic3.app")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), JmAppToken.userAgent)
    }

    private func makeJmClient(handler: @escaping (URLRequest) -> String) -> JmCatalogClient {
        ModuleFavoriteMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModuleFavoriteMockURLProtocol.self]
        return JmCatalogClient(
            session: URLSession(configuration: configuration),
            apiHosts: [URL(string: "https://jm.example.com")!],
            imageHosts: [URL(string: "https://cdn.example.com")!],
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }
}

final class HanimeCatalogClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ModuleFavoriteMockURLProtocol.handler = nil
    }

    func testWorksParseCardsWithoutHittingSetu() async throws {
        let probe = SyncRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return """
            <html><body>
            <div class="home-rows-videos-wrapper">
              <a href="https://hanime1.me/watch?v=12345">
                <img src="https://vdownload.hembed.com/image/a.jpg" alt="第一夜">
                <div class="home-rows-videos-title">第一夜 &amp; 续</div>
              </a>
              <a href="/watch?v=12346">
                <img data-src="https://i.hanime1.me/b.jpg" alt="第二夜">
                <div class="card-mobile-title">第二夜</div>
              </a>
            </div>
            <a href="https://hanime1.me/search?query=&page=8">8</a>
            </body></html>
            """
        }

        let page = try await client.works(page: 1)

        XCTAssertEqual(page.works.map(\.id), ["12345", "12346"])
        XCTAssertEqual(page.works.first?.title, "第一夜 & 续")
        XCTAssertEqual(page.works.first?.coverURL, "https://vdownload.hembed.com/image/a.jpg")
        XCTAssertEqual(page.works.last?.coverURL, "https://i.hanime1.me/b.jpg")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(probe.lastURL, "https://hanime1.me/search?page=1")
        XCTAssertEqual(probe.lastOrigin, HanimeSite.origin)
        XCTAssertEqual(probe.lastReferer, HanimeSite.referer)
        XCTAssertFalse(probe.lastURL?.contains("api.example.com") == true)
    }

    func testCatalogGenresMatchSiteNav() {
        XCTAssertEqual(HanimeGenre.catalog.map(\.title), [
            "最新", "里番", "新番预告", "泡面番", "Motion Anime", "3DCG", "2.5D", "2D动画", "AI生成", "MMD", "Cosplay",
        ])
    }

    func testGenreSearchUsesTraditionalQuery() async throws {
        let probe = SyncRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return """
            <a href="/watch?v=9"><img src="https://i.hanime1.me/a.jpg" alt="里番一"></a>
            <a href="/search?genre=%E8%A3%8F%E7%95%AA&page=2">2</a>
            """
        }
        let genre = try XCTUnwrap(HanimeGenre.catalog.first { $0.title == "里番" })
        let page = try await client.works(page: 1, genre: genre)
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(probe.lastURL)))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.path, "/search")
        XCTAssertEqual(items.first(where: { $0.name == "genre" })?.value, "裏番")
        XCTAssertEqual(items.first(where: { $0.name == "page" })?.value, "1")
        XCTAssertTrue(page.hasMore)
        XCTAssertFalse(probe.lastURL?.contains("api.example.com") == true)
    }

    func testPreviewGenreUsesYearMonthPathAndStops() async throws {
        let probe = SyncRequestProbe()
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 12
        let now = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        let client = makeClient(now: { now }) { request in
            probe.capture(request)
            return """
            <a href="/watch?v=88"><img src="https://i.hanime1.me/a.jpg" alt="预告"></a>
            <a href="/search?query=&page=8">8</a>
            """
        }
        let genre = try XCTUnwrap(HanimeGenre.catalog.first { $0.title == "新番预告" })
        let page = try await client.works(page: 1, genre: genre)
        XCTAssertEqual(probe.lastURL, "https://hanime1.me/previews/202609")
        XCTAssertEqual(page.works.map(\.id), ["88"])
        XCTAssertFalse(page.hasMore, "新番预告按月一页，站点页脚的 search page 不应继续翻页")
    }

    func testShortSearchPageWithoutNextStops() async throws {
        let client = makeClient { _ in
            """
            <a href="/watch?v=1"><img src="https://i.hanime1.me/a.jpg" alt="一"></a>
            """
        }
        let page = try await client.works(page: 1)
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.total, 1)
    }

    func testSearchUsesHanimeQueryAndDoesNotProxy() async throws {
        let probe = SyncRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return """
            <a href="/watch?v=777">
              <img src="https://vdownload.hembed.com/c.jpg" alt="雨夜">
            </a>
            """
        }

        let page = try await client.works(page: 2, keyword: " 雨夜 ")

        XCTAssertEqual(page.works.first?.id, "777")
        XCTAssertTrue(probe.lastURL?.contains("/search?") == true)
        XCTAssertTrue(probe.lastURL?.contains("query=") == true)
        XCTAssertTrue(probe.lastURL?.contains("page=2") == true)
        XCTAssertFalse(probe.lastURL?.contains("api.example.com") == true)
    }

    func testWatchPicksHighestMp4AndRelatedPlaylist() async throws {
        let client = makeClient { request in
            if request.url?.path == "/download" {
                return #"<table class="download-table"></table>"#
            }
            return """
            <html><head>
            <meta property="og:title" content="第一夜">
            <meta property="og:image" content="https://vdownload.hembed.com/image/a.jpg">
            <meta property="og:description" content="雪社">
            </head><body>
            <video id="player">
              <source src="https://vdownload.hembed.com/v/a-720p.mp4" type="video/mp4" size="720">
              <source src="https://vdownload.hembed.com/v/a-1080p.mp4" type="video/mp4" size="1080">
              <source src="https://vdownload.hembed.com/v/a.m3u8" type="application/x-mpegURL">
            </video>
            <div id="video-playlist-wrapper">
              <h4>第一夜系列</h4>
              <div id="playlist-scroll">
                <a href="https://hanime1.me/watch?v=12345"><img src="https://vdownload.hembed.com/image/a.jpg" alt="第一夜"></a>
                <a href="https://hanime1.me/watch?v=12347"><img src="https://vdownload.hembed.com/image/c.jpg" alt="第三夜"></a>
              </div>
            </div>
            <div id="footer"></div>
            </body></html>
            """
        }

        let page = try await client.work(id: "12345")

        XCTAssertEqual(page.work.title, "第一夜")
        XCTAssertEqual(page.work.coverURL, "https://vdownload.hembed.com/image/a.jpg")
        XCTAssertEqual(page.preferredStream?.quality, "1080p")
        XCTAssertEqual(page.preferredStream?.url.absoluteString, "https://vdownload.hembed.com/v/a-1080p.mp4")
        XCTAssertEqual(page.streams.map(\.quality), ["1080p", "720p", "HLS"])
        XCTAssertEqual(page.related.map(\.id), ["12347"])
        XCTAssertEqual(page.work.favoriteSnapshot.module, .hanime)
        XCTAssertEqual(page.work.favoriteSnapshot.externalId, "12345")
    }

    func testWatchFallsBackToDownloadLinks() async throws {
        let client = makeClient { request in
            if request.url?.path == "/download" {
                return """
                <table class="download-table">
                  <a href="https://vdownload.hembed.com/v/a-480p.mp4" download="第一夜.mp4">480p</a>
                  <a href="https://vdownload.hembed.com/v/a-1080p.mp4" download="第一夜.mp4">1080p</a>
                </table>
                """
            }
            return """
            <html><head><meta property="og:title" content="第一夜"></head>
            <body><div id="player"></div></body></html>
            """
        }

        let page = try await client.work(id: "12345")
        XCTAssertEqual(page.preferredStream?.quality, "1080p")
        XCTAssertEqual(page.streams.count, 2)
    }

    func testImageRequestUsesHanimeHeaders() {
        let url = URL(string: "https://vdownload.hembed.com/image/a.jpg")!
        XCTAssertTrue(HanimeSite.isImageCDN(url))
        XCTAssertTrue(HanimeSite.isImageCDN(URL(string: "https://i.hanime1.me/b.jpg")!))
        XCTAssertFalse(HanimeSite.isImageCDN(URL(string: "https://cdn.example.com/cover.jpg")!))
        let request = HanimeSite.imageRequest(url: url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), HanimeSite.referer)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), HanimeSite.userAgent)
        XCTAssertEqual(HanimeSite.playbackAssetOptions[HanimeSite.assetHeaderFieldsKey] as? [String: String], HanimeSite.pageHeaders)
    }

    private func makeClient(
        now: @escaping @Sendable () -> Date = { Date() },
        handler: @escaping (URLRequest) -> String
    ) -> HanimeCatalogClient {
        ModuleFavoriteMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModuleFavoriteMockURLProtocol.self]
        return HanimeCatalogClient(
            session: URLSession(configuration: configuration),
            baseURLs: [URL(string: "https://hanime1.me")!],
            now: now
        )
    }
}

final class JmImageDescramblerTests: XCTestCase {
    func testStripCountUsesPublishedThresholdsAndFilenameMD5() {
        XCTAssertEqual(JmImageDescrambler.stripCount(photoID: 100, scrambleID: 220980, fileName: "00001"), 0)
        XCTAssertEqual(JmImageDescrambler.stripCount(photoID: 230000, scrambleID: 220980, fileName: "00001"), 10)
        XCTAssertEqual(JmImageDescrambler.stripCount(photoID: 300000, scrambleID: 220980, fileName: "00001"), 16)
        XCTAssertEqual(JmImageDescrambler.stripCount(photoID: 300000, scrambleID: 220980, fileName: "00004"), 6)
        XCTAssertEqual(JmImageDescrambler.stripCount(photoID: 500000, scrambleID: 220980, fileName: "00001"), 12)
        XCTAssertEqual(JmImageDescrambler.stripCount(photoID: 421926, scrambleID: 220980, fileName: "00001"), 14)
        XCTAssertEqual(JmImageDescrambler.fileName(from: URL(string: "https://cdn.example.com/media/photos/88001/00001.webp")!), "00001")
        XCTAssertEqual(JmImageDescrambler.photoID(from: URL(string: "https://cdn.example.com/media/photos/88001/00001.webp")!), 88001)
    }

    func testDescrambleRestoresOfficialBottomToTopStrips() throws {
        let width = 6
        let height = 23
        let num = 10
        let clean = try jmSolidRowsPNG(width: width, height: height)
        let scrambled = try jmScramblePNG(clean, width: width, height: height, num: num)
        let restored = JmImageDescrambler.descramble(
            data: scrambled,
            photoID: 230000,
            scrambleID: 220980,
            fileName: "00001"
        )
        XCTAssertEqual(try jmRowReds(from: clean, width: width, height: height).first, 0)
        XCTAssertEqual(try jmRowReds(from: restored, width: width, height: height), try jmRowReds(from: clean, width: width, height: height))
        XCTAssertNotEqual(try jmRowReds(from: scrambled, width: width, height: height), try jmRowReds(from: clean, width: width, height: height))
    }

    func testDescrambleKeepsVerticalGradientContinuousAcrossStripJoins() throws {
        let width = 8
        let height = 100
        let num = 10
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                rgba[index] = UInt8(y)
            }
        }
        let clean = try jmPNG(width: width, height: height, rgba: rgba)
        let scrambled = try jmScramblePNG(clean, width: width, height: height, num: num)
        let restored = JmImageDescrambler.descramble(
            data: scrambled,
            photoID: 230000,
            scrambleID: 220980,
            fileName: "00001"
        )
        let reds = try jmRowReds(from: restored, width: width, height: height)
        XCTAssertEqual(reds, (0..<height).map(UInt8.init))
        let jumps = zip(reds, reds.dropFirst()).enumerated().compactMap { index, pair in
            abs(Int(pair.1) - Int(pair.0)) > 1 ? index + 1 : nil
        }
        XCTAssertEqual(jumps, [], "strip joins must not skip or duplicate rows")
    }

    func testStripBlitsCoverEveryDestinationRowWithoutGaps() {
        for height in [10, 11, 23, 100, 421, 1234] {
            for count in [2, 4, 6, 8, 10, 12, 14, 16, 18, 20] where count <= height {
                var covered = Array(repeating: false, count: height)
                for blit in JmImageDescrambler.stripBlits(height: height, count: count) {
                    XCTAssertGreaterThan(blit.height, 0)
                    for y in blit.destinationY..<(blit.destinationY + blit.height) {
                        XCTAssertFalse(covered[y], "overlap h=\(height) n=\(count) y=\(y)")
                        covered[y] = true
                    }
                }
                XCTAssertTrue(covered.allSatisfy { $0 }, "gap h=\(height) n=\(count)")
            }
        }
    }

    #if canImport(UIKit)
    func testCGImageCropYZeroIsVisualTop() throws {
        let image = try jmUIKitRowsImage(width: 6, height: 2, top: .red, bottom: .blue)
        let cgImage = try XCTUnwrap(image.cgImage)
        let top = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 0, y: 0, width: 6, height: 1)))
        let bottom = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 0, y: 1, width: 6, height: 1)))
        XCTAssertGreaterThan(try jmMeanRed(top), 200)
        XCTAssertLessThan(try jmMeanRed(bottom), 40)
    }

    func testDescrambleFromUIKitImageDoesNotInsertWhiteJoinRows() throws {
        let width = 8
        let height = 100
        let num = 10
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let cleanImage = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            for y in 0..<height {
                UIColor(red: CGFloat(y) / 255, green: 0, blue: 0, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
        }
        let clean = try XCTUnwrap(cleanImage.pngData())
        let scrambled = try jmScramblePNG(clean, width: width, height: height, num: num)
        let restored = try XCTUnwrap(
            JmImageDescrambler.descrambleUIImage(
                data: scrambled,
                photoID: 230000,
                scrambleID: 220980,
                fileName: "00001"
            )?.pngData()
        )
        let reds = try jmRowReds(from: restored, width: width, height: height)
        let jumps = zip(reds, reds.dropFirst()).enumerated().compactMap { index, pair in
            abs(Int(pair.1) - Int(pair.0)) > 1 ? index + 1 : nil
        }
        XCTAssertEqual(jumps, [], "UIKit crop-blit must not leave gaps at strip joins")
        let joinRows = Set(JmImageDescrambler.stripBlits(height: height, count: num).dropFirst().map(\.destinationY))
        for row in joinRows {
            XCTAssertLessThan(abs(Int(reds[row]) - row), 2, "join row \(row) should stay on the gradient")
        }
    }
    #endif
}

@MainActor
final class AsmrPlaybackControllerTests: XCTestCase {
    func testQueueMapsDirectStreamURLs() {
        let work = AsmrWork(id: 41, title: "第一夜", circleName: "雪社", coverURL: "https://cdn.example.com/cover.jpg")
        let first = AsmrTrack(id: "1", title: "A", url: URL(string: "https://cdn.example.com/a.mp3")!, durationSeconds: 12)
        let second = AsmrTrack(id: "2", title: "B", url: URL(string: "https://cdn.example.com/b.mp3")!, durationSeconds: 20)

        let queue = AsmrPlayback.queue([first, second], work: work)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue[0].streamURL, first.url)
        XCTAssertEqual(queue[0].album, "第一夜")
        XCTAssertEqual(queue[0].artist, "雪社")
        XCTAssertTrue(queue[0].usesDirectStream)
        XCTAssertEqual(queue[1].streamURL, second.url)
    }

    func testDirectStreamSkipDoesNotResolveProviderURLAndKeepsProgressOnPause() async throws {
        let firstURL = try playbackWave()
        let secondURL = try playbackWave(seconds: 60)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        var resolveCount = 0
        let controller = MusicPlaybackController(persistsPlayback: false)
        controller.urlResolver = PlaybackURLResolver { _, _ in
            resolveCount += 1
            throw UserFacingError(message: "external streams must not resolve a music URL")
        }
        addTeardownBlock { await MainActor.run { controller.stop() } }

        let work = AsmrWork(id: 41, title: "第一夜", circleName: "雪社")
        let first = AsmrTrack(id: "1", title: "A", url: firstURL, durationSeconds: 180)
        let second = AsmrTrack(id: "2", title: "B", url: secondURL, durationSeconds: 60)
        let queue = AsmrPlayback.queue([first, second], work: work)
        controller.play(
            url: firstURL,
            track: queue[0],
            context: .album(id: "asmr:41", label: "第一夜"),
            queueTracks: queue
        )

        let engine = try XCTUnwrap(controller.player)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { engine.currentItem?.status == .readyToPlay }
        }, object: nil)
        await fulfillment(of: [ready], timeout: 5)
        controller.pause()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.currentTrack?.streamURL, firstURL)

        await controller.userSkip(by: 1)
        XCTAssertEqual(resolveCount, 0)
        XCTAssertEqual(controller.currentTrack?.streamURL, secondURL)
        XCTAssertEqual(controller.currentTimeSeconds, 0, accuracy: 0.5)
        XCTAssertNil(controller.playbackError)
    }
}

private final class SyncRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var url: String?
    private var method: String?
    private var token: String?
    private var origin: String?
    private var referer: String?
    private var userAgent: String?
    private var version: String?

    var lastURL: String? { lock.withLock { url } }
    var lastMethod: String? { lock.withLock { method } }
    var lastToken: String? { lock.withLock { token } }
    var lastOrigin: String? { lock.withLock { origin } }
    var lastReferer: String? { lock.withLock { referer } }
    var lastUserAgent: String? { lock.withLock { userAgent } }
    var lastVersion: String? { lock.withLock { version } }

    func capture(_ request: URLRequest) {
        lock.lock()
        url = request.url?.absoluteString
        method = request.httpMethod
        token = request.value(forHTTPHeaderField: "token")
        origin = request.value(forHTTPHeaderField: "Origin")
        referer = request.value(forHTTPHeaderField: "Referer")
        userAgent = request.value(forHTTPHeaderField: "User-Agent")
        version = request.value(forHTTPHeaderField: "version")
        lock.unlock()
    }
}

private actor RequestProbe {
    private(set) var lastURL: String?
    private(set) var lastMethod: String?
    private(set) var lastToken: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
        lastMethod = request.httpMethod
        lastToken = request.value(forHTTPHeaderField: "token")
    }
}

private final class TestKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    func remove(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private final class ModuleFavoriteMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func jmEncryptedEnvelope(_ plaintext: String, timestamp: String, secret: String) -> String {
    let key = Insecure.MD5.hash(data: Data("\(timestamp)\(secret)".utf8)).map { String(format: "%02x", $0) }.joined()
    let encrypted = jmAesEcbEncrypt(Data(plaintext.utf8), key: key) ?? Data()
    return #"{"code":200,"data":"\#(encrypted.base64EncodedString())"}"#
}

private func jmAesEcbEncrypt(_ data: Data, key: String) -> Data? {
    #if canImport(CommonCrypto)
    let keyData = Data(key.utf8)
    let inputCount = data.count
    var output = Data(count: inputCount + kCCBlockSizeAES128)
    let outputCapacity = output.count
    var outputLength = 0
    let status = output.withUnsafeMutableBytes { outputBytes in
        data.withUnsafeBytes { inputBytes in
            keyData.withUnsafeBytes { keyBytes in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                    keyBytes.baseAddress,
                    keyData.count,
                    nil,
                    inputBytes.baseAddress,
                    inputCount,
                    outputBytes.baseAddress,
                    outputCapacity,
                    &outputLength
                )
            }
        }
    }
    guard status == kCCSuccess else { return nil }
    output.removeSubrange(outputLength..<output.count)
    return output
    #else
    return nil
    #endif
}

private func jmSolidRowsPNG(width: Int, height: Int) throws -> Data {
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            rgba[index] = UInt8(y)
            rgba[index + 1] = 0
            rgba[index + 2] = UInt8(x)
        }
    }
    return try jmPNG(width: width, height: height, rgba: rgba)
}

private func jmScramblePNG(_ data: Data, width: Int, height: Int, num: Int) throws -> Data {
    let source = try jmTopDownRGBA(from: data, width: width, height: height)
    var destination = [UInt8](repeating: 0, count: source.count)
    let bytesPerRow = width * 4
    let over = height % num
    for index in 0..<num {
        var move = height / num
        let sourceY = height - (move * (index + 1)) - over
        var destinationY = move * index
        if index == 0 {
            move += over
        } else {
            destinationY += over
        }
        for row in 0..<move {
            let from = (destinationY + row) * bytesPerRow
            let to = (sourceY + row) * bytesPerRow
            destination.replaceSubrange(to..<(to + bytesPerRow), with: source[from..<(from + bytesPerRow)])
        }
    }
    return try jmPNG(width: width, height: height, rgba: destination)
}

private func jmRowReds(from data: Data, width: Int, height: Int) throws -> [UInt8] {
    let rgba = try jmTopDownRGBA(from: data, width: width, height: height)
    return (0..<height).map { y in rgba[y * width * 4] }
}

private func jmPNG(width: Int, height: Int, rgba: [UInt8], bytesPerRow: Int? = nil) throws -> Data {
    let bytesPerRow = bytesPerRow ?? width * 4
    let data = Data(rgba) as CFData
    let provider = try XCTUnwrap(CGDataProvider(data: data))
    let image = try XCTUnwrap(
        CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    )
    let output = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return output as Data
}

private func jmTopDownRGBA(from data: Data, width: Int, height: Int) throws -> [UInt8] {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    XCTAssertTrue(ok)
    return pixels
}

#if canImport(UIKit)
private func jmUIKitRowsImage(width: Int, height: Int, top: UIColor, bottom: UIColor) throws -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
        top.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        bottom.setFill()
        ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
    }
}

private func jmMeanRed(_ image: CGImage) throws -> Double {
    var pixel = [UInt8](repeating: 0, count: 4)
    try pixel.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "jm", code: 1) }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return Double(pixel[0])
}
#endif
