#if DEBUG && canImport(MobileVLCKit)
import AVFoundation
import CryptoKit
import Observation
import SetuIOSCore
import SwiftUI

/// Development-only differential playback gate. Production snapshots and user caches are untouched.
@MainActor @Observable
final class VLCProbeModel {
    enum Route: String, CaseIterable, Identifiable {
        case current = "现有控制器与缓存"
        case vlcRemote = "VLC 直连", avRemote = "AVPlayer 直连"
        case vlcLocal = "VLC 本地", avLocal = "AVPlayer 本地"
        var id: String { rawValue }
        var isLocal: Bool { self == .vlcLocal || self == .avLocal }
    }
    var route: Route = .vlcRemote
    private(set) var engine: any MusicPlaybackEngine = VLCPlaybackEngine()
    private var selectedID: String?
    private var selectedSource: ResolvedPlaybackURL?
    private var localFile: URL?
    private var downloadSession: URLSession?
    private var runID = UUID()
    var snapshot: MusicEngineSnapshot?
    var tracks: [MusicV2Track] = []
    var lines: [LyricLine] = []
    var title = "尚未选曲"
    var message = "VLC 3.7.3 直连；未接入旧缓存和播放控制器"
    var busy = false
    var isBatchRunning = false
    private var batchID = UUID()
    private var latestSeek = UUID()
    private var generation = UUID()
    private var began = ProcessInfo.processInfo.systemUptime
    private var events: [[String: String]] = []
    private var lastPersist = Date.distantPast
    init() { attachObserver() }
    private func attachObserver() {
        engine.onChange = { [weak self] value in
            guard let self, value.mediaID == self.generation else { return }
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
            for section in result.sections {
                if case .failed(let scope, let error) = section {
                    record(["event": "searchSectionFailed", "scope": scope.rawValue, "code": error.code.rawValue])
                }
            }
            tracks = result.sections.flatMap { section in if case .tracks(let page) = section { return page.items }; return [] }
            for track in tracks {
                record(["event": "searchResult", "title": track.title, "trackID": track.id.rawValue,
                    "artists": track.artists.map(\.name).joined(separator: " / ")])
            }
            message = tracks.isEmpty ? "未搜索到歌曲" : "选择具体版本后开始 VLC 直连播放"
        } catch {
            tracks = []; message = UserFacingErrorMapper.map(error).message
            record(["event": "searchFailed", "code": String((error as NSError).code), "domain": (error as NSError).domain])
        }
    }
    func play(_ track: MusicV2Track, client: MusicV2Client,
              resolve: (MusicPlaybackIdentity) async throws -> ResolvedPlaybackURL, resolver: PlaybackURLResolver? = nil) async {
        let request = UUID(); generation = request; downloadSession?.invalidateAndCancel(); engine.onChange = nil; engine.stop(); lines = []; snapshot = nil
        busy = true; title = track.title; began = ProcessInfo.processInfo.systemUptime; events = []; runID = UUID()
        switch route {
        case .current: engine = CurrentPlaybackProbeEngine(track: MusicPlaybackTrack(track: track), resolver: resolver)
        case .avRemote, .avLocal: engine = AVDirectProbeEngine()
        case .vlcRemote, .vlcLocal: engine = VLCPlaybackEngine()
        }
        attachObserver()
        record(["event": "click", "route": route.rawValue])
        defer { if generation == request { busy = false } }
        do {
            if selectedID != track.id.rawValue {
                if let localFile { try? FileManager.default.removeItem(at: localFile) }
                selectedSource = nil; localFile = nil; selectedID = track.id.rawValue
            }
            let source: ResolvedPlaybackURL
            if let existing = selectedSource { source = existing }
            else { source = try await resolve(.canonical(track.id)) }
            guard generation == request else { return }
            selectedSource = source
            record(["event": "resolved", "route": route.rawValue])
            guard generation == request else { return }
            record(["event": "source", "track": track.title, "trackID": track.id.rawValue,
                    "quality": source.effectiveLevel,
                    "urlHash": SHA256.hash(data: Data(source.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()])
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            var playbackURL = source.url
            if route.isLocal {
                if localFile == nil {
                    message = "正在准备同源本地文件；下载时间单独记录"
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.timeoutIntervalForRequest = 20
                    configuration.timeoutIntervalForResource = 120
                    let session = URLSession(configuration: configuration)
                    downloadSession = session
                    defer { session.invalidateAndCancel(); if generation == request { downloadSession = nil } }
                    let (temporary, response) = try await session.download(from: source.url)
                    guard generation == request else { return }
                    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    let header = try Data(contentsOf: temporary, options: .mappedIfSafe).prefix(4)
                    let suffix = header == Data("fLaC".utf8) ? "flac" : "audio"
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("music-probe-\(UUID()).\(suffix)")
                    try FileManager.default.moveItem(at: temporary, to: file)
                    localFile = file
                    let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
                    record(["event": "localReady", "file": file.lastPathComponent, "bytes": String(bytes.count),
                        "contentSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                        "mime": response.mimeType ?? "unknown"])
                }
                guard let file = localFile else { throw URLError(.fileDoesNotExist) }
                playbackURL = file
                record(["event": "localInput", "file": file.lastPathComponent])
            }
            record(["event": "engineLoad", "route": route.rawValue])
            engine.load(url: playbackURL, mediaID: request); engine.play()
            message = "\(route.rawValue)；时间戳不代表声音已验证准确"
            if let lyric = try? await client.lyrics(trackID: track.id), generation == request { lines = LyricParser.parse(lyric) }
        } catch { guard generation == request else { return }; message = "验证失败，请重试"; record(["event": "failed", "code": String((error as NSError).code), "domain": (error as NSError).domain]) }
    }
    func seek(_ time: TimeInterval) async {
        let request = generation, seek = UUID(); latestSeek = seek
        record(["event": "seekRequested", "targetMs": String(Int64(time * 1000))])
        do { try await engine.seek(toMilliseconds: Int64(time * 1000)); guard generation == request, latestSeek == seek else { return }; message = "引擎已返回定位位置，请对照实际声音" }
        catch { guard generation == request, latestSeek == seek else { return }; message = "定位未完成" }
        record(["event": "seekFinished", "message": message])
    }
    func stop() { batchID = UUID(); stopPlayback() }
    private func stopPlayback() {
        latestSeek = UUID(); generation = UUID(); downloadSession?.invalidateAndCancel(); downloadSession = nil
        engine.stop(); snapshot = nil; busy = false; record(["event": "stopped"])
    }
    func smoke(client: MusicV2Client, resolve: (MusicPlaybackIdentity) async throws -> ResolvedPlaybackURL, resolver: PlaybackURLResolver? = nil) async {
        let batch = UUID(); batchID = batch; isBatchRunning = true
        defer { isBatchRunning = false }
        for name in ["不擅生长的树", "昔涟"] {
            await search(name, client: client)
            if tracks.isEmpty, name == "不擅生长的树" { await search("房东的猫 不擅生长的树", client: client) }
            guard batchID == batch, !Task.isCancelled else { return }
            let matches = tracks.filter { $0.title == name && (name == "不擅生长的树" ? $0.artists.contains { $0.name == "房东的猫" } : $0.artists.contains { $0.name == "张韶涵" }) }
            guard matches.count == 1, let track = matches.first else {
                record(["event": "selectionRequired", "title": name, "matches": String(matches.count)])
                message = "歌曲版本需要手动选择：\(name)"; return
            }
            let arguments = ProcessInfo.processInfo.arguments
            let selectedRoute = arguments.firstIndex(of: "-music-probe-route").flatMap { index in
                arguments.indices.contains(index + 1) ? Route(rawValue: arguments[index + 1]) : nil
            }
            for candidate in selectedRoute.map({ [$0] }) ?? Route.allCases {
                guard batchID == batch, !Task.isCancelled else { return }
                route = candidate
                await play(track, client: client, resolve: resolve, resolver: resolver)
                guard batchID == batch, !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(15))
                guard batchID == batch, !Task.isCancelled else { return }
                if snapshot?.seekable == true, let duration = snapshot?.durationMilliseconds, duration > 0 {
                    await seek(Double(duration) / 2000)
                    try? await Task.sleep(for: .seconds(5))
                }
                guard batchID == batch, !Task.isCancelled else { return }
                stopPlayback()
            }
        }
        message = "冒烟对照完成；尚未验证实际声音、完整播放和性能分位数"
    }
    private func record(_ event: [String: String]) {
        var event = event; event["elapsedMs"] = String(Int((ProcessInfo.processInfo.systemUptime - began) * 1000)); events.append(event)
        if events.count > 4000 { events.removeFirst(events.count - 4000) }
        guard event["event"] != "playback" || Date().timeIntervalSince(lastPersist) >= 1 else { return }
        lastPersist = Date()
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: folder.appendingPathComponent("music-probe-\(runID.uuidString).json"), options: .atomic)
    }
}

struct VLCProbeView: View {
    let environment: AppEnvironment
    var resolver: PlaybackURLResolver? = nil
    let resolve: (MusicPlaybackIdentity) async throws -> ResolvedPlaybackURL
    @State private var model = VLCProbeModel()
    @State private var query = "不擅生长的树 房东的猫"
    var body: some View {
        NavigationStack {
            List {
                Section("独立验证，不代表正式迁移完成") {
                    Text(model.message).font(.footnote)
                    Picker("对照路径", selection: $model.route) {
                        ForEach(VLCProbeModel.Route.allCases) { Text($0.rawValue).tag($0) }
                    }.disabled(model.busy || model.isBatchRunning)
                    Text("同一歌曲复用已解析地址。本地两条路径复用同一文件；选曲后开始新一轮记录。").font(.caption)
                    TextField("歌曲和歌手", text: $query)
                    HStack {
                        Button("搜索") { Task { await model.search(query, client: environment.musicV2Client) } }
                        Button("昔涟") { query = "昔涟"; Task { await model.search(query, client: environment.musicV2Client) } }
                    }.disabled(model.busy || model.isBatchRunning)
                }
                Section("播放状态") {
                    Text(model.title)
                    if let value = model.snapshot {
                        Text("\(value.state.rawValue) · \(Double(value.positionMilliseconds) / 1000, specifier: "%.2f") / \(Double(value.durationMilliseconds) / 1000, specifier: "%.2f") 秒")
                    }
                    HStack {
                        Button("播放") { model.engine.play() }.disabled(model.isBatchRunning)
                        Button("暂停") { model.engine.pause() }.disabled(model.isBatchRunning)
                        Button("停止") { model.stop() }
                    }
                }
                Section("歌曲版本") {
                    ForEach(model.tracks, id: \.id) { track in
                        Button("\(track.title) — \(track.artists.map(\.name).joined(separator: " / "))") {
                            Task { await model.play(track, client: environment.musicV2Client, resolve: resolve, resolver: resolver) }
                        }.disabled(model.busy || model.isBatchRunning)
                    }
                }
                Section("点击歌词定位") {
                    ForEach(model.lines) { line in
                        Button("\(Int(line.time))s  \(line.text)") { Task { await model.seek(line.time) } }
                            .disabled(model.isBatchRunning || !line.isTimed || model.snapshot?.seekable != true)
                    }
                }
            }
            .buttonStyle(.borderless)
            .navigationTitle("音乐同源对照")
            .task {
                if ProcessInfo.processInfo.arguments.contains("-music-probe-smoke") {
                    await model.smoke(client: environment.musicV2Client, resolve: resolve, resolver: resolver)
                } else { await model.search(query, client: environment.musicV2Client) }
            }
            .onDisappear { model.stop() }
        }
    }
}
#endif

#if DEBUG && canImport(MobileVLCKit)
/// Deliberately bypasses the application resource loader for differential testing.
@MainActor
final class AVDirectProbeEngine: MusicPlaybackEngine {
    private var player: AVPlayer?
    private var observer: Any?
    private var stateObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var mediaID = UUID()
    private var seekID = UUID()
    private var completedSeek: UUID?
    private(set) var snapshot: MusicEngineSnapshot?
    var onChange: ((MusicEngineSnapshot) -> Void)?
    var volume: Float {
        get { player?.volume ?? 1 }
        set { player?.volume = newValue }
    }
    func load(url: URL, mediaID: UUID) {
        stop(); self.mediaID = mediaID
        let next = AVPlayer(url: url); player = next
        stateObserver = next.observe(\.timeControlStatus, options: [.new]) { [weak self, weak next] _, _ in
            Task { @MainActor in guard let self, let next, self.player === next else { return }; self.publish() }
        }
        itemObserver = next.currentItem?.observe(\.status, options: [.new]) { [weak self, weak next] _, _ in
            Task { @MainActor in guard let self, let next, self.player === next else { return }; self.publish() }
        }
        observer = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self, weak next] _ in
            Task { @MainActor in
                guard let self, let next, self.player === next else { return }
                self.publish()
            }
        }
        publish()
    }
    func play() { player?.play(); publish() }
    func pause() { player?.pause(); publish() }
    func stop() {
        seekID = UUID()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil; stateObserver = nil; itemObserver = nil; player?.pause(); player = nil; snapshot = nil
    }
    func seek(toMilliseconds target: Int64) async throws {
        guard let player else { throw CancellationError() }
        let operation = UUID(); seekID = operation
        completedSeek = nil
        player.seek(to: CMTime(value: max(0, target), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
            Task { @MainActor in
                guard let self, let player, self.player === player, self.seekID == operation, finished else { return }
                self.completedSeek = operation
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard self.player === player, seekID == operation else { throw CancellationError() }
            let actual = player.currentTime().seconds
            if completedSeek == operation, actual.isFinite, abs(actual - Double(target) / 1000) < 0.2 { publish(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw URLError(.timedOut)
    }
    private func publish() {
        guard let player, let item = player.currentItem else { return }
        let state: MusicEngineSnapshot.State
        if item.status == .failed { state = .failed }
        else if item.status == .unknown { state = .opening }
        else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate { state = .buffering }
        else if player.timeControlStatus == .playing { state = .playing }
        else if item.duration.seconds.isFinite, player.currentTime().seconds >= item.duration.seconds { state = .ended }
        else { state = .paused }
        func milliseconds(_ time: CMTime) -> Int64 {
            time.seconds.isFinite ? Int64(max(0, time.seconds) * 1000) : 0
        }
        let value = MusicEngineSnapshot(mediaID: mediaID, state: state,
            positionMilliseconds: milliseconds(player.currentTime()), durationMilliseconds: milliseconds(item.duration),
            seekable: item.status == .readyToPlay)
        snapshot = value; onChange?(value)
    }
}
#endif

#if DEBUG && canImport(MobileVLCKit)
/// The production controller/resource loader with an isolated cache and disabled
/// playback snapshots/history. URL resolution is shared with the direct routes.
@MainActor
final class CurrentPlaybackProbeEngine: MusicPlaybackEngine {
    private let controller: MusicPlaybackController
    private let track: MusicPlaybackTrack
    private var polling: Task<Void, Never>?
    private var mediaID = UUID()
    private(set) var snapshot: MusicEngineSnapshot?
    var onChange: ((MusicEngineSnapshot) -> Void)?
    var volume: Float = 1
    init(track: MusicPlaybackTrack, resolver: PlaybackURLResolver? = nil) {
        self.track = track
        let cache = MusicAudioCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("music-controller-probe-cache"), capacity: 256 * 1024 * 1024)
        controller = MusicPlaybackController(persistsPlayback: false, audioAssets: CachedAudioAssetFactory(cache: cache))
        controller.urlResolver = resolver
    }
    func load(url: URL, mediaID: UUID) {
        stop(); self.mediaID = mediaID
        controller.play(url: url, track: track)
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.publish()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    func play() { controller.resume() }
    func pause() { controller.pause(); publish() }
    func stop() { mediaID = UUID(); polling?.cancel(); polling = nil; controller.stop(); snapshot = nil }
    func seek(toMilliseconds target: Int64) async throws {
        guard controller.playbackError == nil else { throw URLError(.cannotDecodeContentData) }
        let request = mediaID
        controller.seek(to: Double(target) / 1000)
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard mediaID == request else { throw CancellationError() }
            guard controller.playbackError == nil else { throw URLError(.cannotDecodeContentData) }
            if abs(controller.currentTimeSeconds - Double(target) / 1000) < 0.2 { publish(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw URLError(.timedOut)
    }
    private func publish() {
        let state: MusicEngineSnapshot.State = controller.playbackError != nil ? .failed :
            controller.isBuffering ? .buffering : controller.isPlaying ? .playing : .paused
        let value = MusicEngineSnapshot(mediaID: mediaID, state: state,
            positionMilliseconds: Int64(max(0, controller.currentTimeSeconds) * 1000),
            durationMilliseconds: Int64(max(0, controller.durationSeconds) * 1000), seekable: controller.currentTrack != nil && controller.playbackError == nil)
        snapshot = value; onChange?(value)
    }
}
#endif
