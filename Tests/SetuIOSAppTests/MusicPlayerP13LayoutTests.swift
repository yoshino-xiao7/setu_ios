#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicPlayerP13LayoutTests: XCTestCase {
    func testPlayerAt375And430StandardAndAX5LightAndDark() async throws {
        for width in [375.0, 430.0] {
            for size in [DynamicTypeSize.large, .accessibility5] {
                for color in [ColorScheme.light, .dark] {
                    let environment = p13Environment(airPlay: true)
                    let player = MusicPlaybackController(persistsPlayback: false)
                    player.configurePreview(songs: [MusicSong(id: 7101, name: "夏夜微风", artists: [MusicArtist(id: 1, name: "雪涼乐队")], album: MusicAlbum(id: 11, name: "粉色云层"), duration: 238_000)])
                    let lyrics = NowPlayingLyricsModel()
                    let view = NowPlayingSheet(environment: environment, player: player, lyrics: lyrics)
                        .environment(\.dynamicTypeSize, size).environment(\.colorScheme, color)
                        .environment(MusicStore(client: environment.musicClient, userID: 1))
                    let host = UIHostingController(rootView: view)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 812))
                    window.rootViewController = host; window.makeKeyAndVisible()
                    host.view.frame = window.bounds; host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    XCTAssertEqual(image.size.width, width)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "p13-player-\(Int(width))-\(size)-\(color)"
                    attachment.lifetime = .keepAlways; add(attachment)
                    window.isHidden = true
                }
            }
        }
    }

    func testWordRenderingAndScrollingCadenceOnDevice() async throws {
        let lyric = try JSONDecoder().decode(MusicV2Lyric.self, from: Data(p13WordJSON.utf8))
        let base = LyricParser.parse(lyric)[0]
        let lines = (0..<40).map { LyricLine(id: "perf-\($0)", time: Double($0), text: base.text,
                                            translation: base.translation, words: base.words) }
        let started = CACurrentMediaTime()
        let content = LyricScrollView(lines: lines, currentTime: 1.5, expands: true, isPlaying: true,
                                      sampleTime: { 1 + (CACurrentMediaTime() - started).truncatingRemainder(dividingBy: 0.7) }, onSeek: { _ in })
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        func scrollView(_ view: UIView) -> UIScrollView? {
            if let value = view as? UIScrollView { return value }
            return view.subviews.lazy.compactMap { scrollView($0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(host.view))
        let probe = P13DisplayProbe(scroll: scroll)
        let link = CADisplayLink(target: probe, selector: #selector(P13DisplayProbe.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        try await Task.sleep(nanoseconds: 4_000_000_000)
        link.invalidate()
        window.isHidden = true
        XCTAssertGreaterThan(probe.intervals.count, 30)
        let intervals = probe.intervals.sorted()
        print("P13_WORD_SCROLL samples=\(intervals.count) maximumFPS=\(UIScreen.main.maximumFramesPerSecond) medianMs=\(intervals[intervals.count / 2] * 1000) maxMs=\((intervals.last ?? 0) * 1000) over20ms=\(intervals.filter { $0 > 0.020 }.count)")
        // Record cadence; do not substitute a callback count for a no-dropped-frame acceptance.
    }

    func testWordMaskWrapsLongUnicodeTextAndTranslation() async throws {
        let words = ["你好", "世界", "沿着星光", "回家", "微风吹过", "夏夜", "Hello ", "world"]
        let body: [String: Any] = ["trackId": "netease:track:1", "kind": "word", "hasTranslation": true, "contributors": [],
            "lines": [["text": words.joined(), "startMs": 1000, "durationMs": 8000, "translation": "逐字歌词换行与翻译",
                       "words": words.enumerated().map { ["text": $0.element, "startMs": 1000 + $0.offset * 1000, "durationMs": 1000] as [String: Any] }]]]
        let lyric = try JSONDecoder().decode(MusicV2Lyric.self, from: JSONSerialization.data(withJSONObject: body))
        let lines = LyricParser.parse(lyric)
        let content = LyricScrollView(lines: lines, currentTime: 5.5, expands: true, onSeek: { _ in })
            .environment(\.dynamicTypeSize, .accessibility5)
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 500))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "p13-word-mask-AX5"; attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true
    }
}
@MainActor
private final class P13DisplayProbe: NSObject {
    let scroll: UIScrollView
    var intervals: [Double] = []
    var previous: Double?
    var start: Double?
    init(scroll: UIScrollView) { self.scroll = scroll }
    @objc func tick(_ link: CADisplayLink) {
        if let previous { intervals.append(link.timestamp - previous) }
        previous = link.timestamp
        if start == nil { start = link.timestamp }
        let extent = max(0, min(900, scroll.contentSize.height - scroll.bounds.height))
        let phase = (link.timestamp - (start ?? link.timestamp)) / 4
        scroll.setContentOffset(CGPoint(x: 0, y: extent * (1 - cos(phase * .pi * 2)) / 2), animated: false)
    }
}
#endif
