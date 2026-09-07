#if DEBUG && canImport(MobileVLCKit)
import AVFoundation
import CryptoKit
import Observation
import SetuIOSCore
import SwiftUI

/// Development-only independent playback gate. No production controller/cache is used.
@MainActor @Observable
final class VLCProbeModel {
    let engine = VLCPlaybackEngine()
    var snapshot: MusicEngineSnapshot?
    var tracks: [MusicV2Track] = []
    var lines: [LyricLine] = []
    var title = "尚未选曲"
    var message = "VLC 3.7.3 直连；未接入旧缓存和播放控制器"
    var busy = false
    private var generation = UUID()
    private var began = Date()
    private var events: [[String: String]] = []
    private var lastPersist = Date.distantPast
    init() {
        engine.onChange = { [weak self] value in
            guard let self else { return }
            self.snapshot = value
            self.record(["event": "playback", "state": value.state.rawValue,
                         "positionMs": String(value.positionMilliseconds), "durationMs": String(value.durationMilliseconds)])
        }
    }
    func search(_ query: String, client: MusicV2Client) async {
        busy = true
        defer { busy = false }
        do {
            let result = try await client.search(keywords: query)
            tracks = result.sections.flatMap { section in if case .tracks(let page) = section { return page.items }; return [] }
            message = tracks.isEmpty ? "未搜索到歌曲" : "选择具体版本后开始 VLC 直连播放"
        } catch { message = UserFacingErrorMapper.map(error).message }
    }
    func play(_ track: MusicV2Track, client: MusicV2Client,
              resolve: (MusicPlaybackIdentity) async throws -> ResolvedPlaybackURL) async {
        let request = UUID(); generation = request; engine.stop(); lines = []; snapshot = nil
        busy = true; title = track.title; began = Date(); events = []
        defer { if generation == request { busy = false } }
        do {
            let source = try await resolve(.canonical(track.id))
            guard generation == request else { return }
            record(["event": "source", "track": track.title, "trackID": track.id.rawValue,
                    "quality": source.effectiveLevel ?? "unknown",
                    "urlHash": SHA256.hash(data: Data(source.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()])
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            engine.load(url: source.url, mediaID: request); engine.play()
            message = "VLC 直连播放中；点击下面的歌词验证实际声音位置"
            if let lyric = try? await client.lyrics(trackID: track.id), generation == request { lines = LyricParser.parse(lyric) }
        } catch { message = UserFacingErrorMapper.map(error).message; record(["event": "failed", "message": message]) }
    }
    func seek(_ time: TimeInterval) async {
        record(["event": "seekRequested", "targetMs": String(Int64(time * 1000))])
        do { try await engine.seek(toMilliseconds: Int64(time * 1000)); message = "引擎已返回定位位置，请对照实际声音" }
        catch { message = "VLC 定位未完成：\(String(describing: error))" }
        record(["event": "seekFinished", "message": message])
    }
    func stop() { generation = UUID(); engine.stop(); record(["event": "stopped"]) }
    private func record(_ event: [String: String]) {
        var event = event; event["elapsedMs"] = String(Int(Date().timeIntervalSince(began) * 1000)); events.append(event)
        if events.count > 4000 { events.removeFirst(events.count - 4000) }
        guard event["event"] != "playback" || Date().timeIntervalSince(lastPersist) >= 1 else { return }
        lastPersist = Date()
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: folder.appendingPathComponent("vlc-direct-probe.json"), options: .atomic)
    }
}

struct VLCProbeView: View {
    let environment: AppEnvironment
    let resolve: (MusicPlaybackIdentity) async throws -> ResolvedPlaybackURL
    @State private var model = VLCProbeModel()
    @State private var query = "不擅长生长的树 房东的猫"
    var body: some View {
        NavigationStack {
            List {
                Section("独立验证，不代表正式迁移完成") {
                    Text(model.message).font(.footnote)
                    TextField("歌曲和歌手", text: $query)
                    HStack {
                        Button("搜索") { Task { await model.search(query, client: environment.musicV2Client) } }
                        Button("昔涟") { query = "昔涟"; Task { await model.search(query, client: environment.musicV2Client) } }
                    }.disabled(model.busy)
                }
                Section("播放状态") {
                    Text(model.title)
                    if let value = model.snapshot {
                        Text("\(value.state.rawValue) · \(Double(value.positionMilliseconds) / 1000, specifier: "%.2f") / \(Double(value.durationMilliseconds) / 1000, specifier: "%.2f") 秒")
                    }
                    HStack {
                        Button("播放") { model.engine.play() }
                        Button("暂停") { model.engine.pause() }
                        Button("停止") { model.stop() }
                    }
                }
                Section("歌曲版本") {
                    ForEach(model.tracks, id: \.id) { track in
                        Button("\(track.title) — \(track.artists.map(\.name).joined(separator: " / "))") {
                            Task { await model.play(track, client: environment.musicV2Client, resolve: resolve) }
                        }.disabled(model.busy)
                    }
                }
                Section("点击歌词定位") {
                    ForEach(model.lines) { line in
                        Button("\(Int(line.time))s  \(line.text)") { Task { await model.seek(line.time) } }
                            .disabled(!line.isTimed || model.snapshot?.seekable != true)
                    }
                }
            }
            .buttonStyle(.borderless)
            .navigationTitle("VLC 直连验证")
            .task { await model.search(query, client: environment.musicV2Client) }
            .onDisappear { model.stop() }
        }
    }
}
#endif
