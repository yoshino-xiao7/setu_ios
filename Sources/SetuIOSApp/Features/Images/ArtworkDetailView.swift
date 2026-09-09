import SetuIOSCore
import SwiftUI
#if os(iOS)
import AVKit
import Photos

struct ArtworkDetailPage: View {
    let source: ArtworkSource
    @Bindable var store: ArtworkBrowserStore
    let environment: AppEnvironment
    let onArtist: (String) -> Void
    let onTag: (String) -> Void
    let active: Bool
    let close: () -> Void
    let select: (String) -> Void
    let workID: String
    @State private var work: BrowserArtwork?
    @State private var related: [BrowserArtwork] = []
    @State private var error: String?
    @State private var feedback: String?
    @State private var busy = false
    @State private var saving = ""
    @State private var zoom: ArtworkPage?
    @State private var importing = false
    private var importTaskID: String? { store.importTasks[work?.pid ?? workID] }
    @State private var reloadID = UUID()
    @State private var loadedReloadID: UUID?
    @State private var animationMessage: String?
    @State private var videoFile: URL?
    @State private var player: AVQueuePlayer?
    @State private var videoLooper: AVPlayerLooper?

    init(source: ArtworkSource, initialID: String, store: ArtworkBrowserStore, environment: AppEnvironment,
         active: Bool, close: @escaping () -> Void, select: @escaping (String) -> Void,
         onArtist: @escaping (String) -> Void, onTag: @escaping (String) -> Void) {
        self.source = source; self.store = store; self.environment = environment
        self.onArtist = onArtist; self.onTag = onTag
        self.active = active; self.close = close; self.select = select; self.workID = initialID
        _work = State(initialValue: store.cachedDetail(source: source, id: initialID)
                      ?? store.state(source).items.first { $0.id == initialID })
    }
    private var index: Int? { store.state(source).items.firstIndex { $0.id == workID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let work {
                    LazyVStack(spacing: 0) {
                        if work.kind == "ugoira" { animationView(work) }
                        else {
                            ForEach(Array(work.pages.enumerated()), id: \.element.id) { offset, page in
                                Button { zoom = page } label: {
                                    ArtworkMediaImage(path: page.previewUrl, client: store.client, ratio: page.aspectRatio, label: work.title, maxPixelSize: 2000, identity: work.imageIdentity(page), quality: .preview)
                                        .accessibilityIdentifier("artwork-image-\(work.id)-\(page.index)")
                                }.buttonStyle(.plain)
                                    .contextMenu { saveMenu(work, page: page) }
                                if work.pages.count > 1 {
                                    HStack {
                                        Text("\(offset + 1) / \(work.pages.count)").font(.caption).foregroundStyle(SetuColor.textSecondary)
                                        Spacer()
                                    }.font(.caption).padding()
                                }
                            }
                        }
                        information(work)
                    }
                } else if let error {
                    VStack(spacing: 16) { Text(error).font(.subheadline); Button("重试") { reloadID = UUID() } }.padding(30)
                } else { ProgressView("正在加载作品").padding(.top, 100) }
            }
            .setuBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(action: close) { Image(systemName: "chevron.down") }.accessibilityLabel("关闭作品") }
                ToolbarItem(placement: .principal) { Text(source.title).font(.caption).foregroundStyle(SetuColor.textSecondary) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("重新加载作品") { reloadID = UUID() }
                        if environment.authSession.currentUser?.role == .admin && source == .pixiv {
                            Button(importTaskID != nil ? "已提交至管理员图片任务" : importing ? "正在提交 PID…" : "通过 PID 导入本站") { Task { await importCurrentPID() } }.disabled(importing || importTaskID != nil)
                        }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("作品操作")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let work {
                    Button { Task { await bookmark(nil) } } label: {
                        Image(systemName: work.bookmarked ? "heart.fill" : "heart")
                            .font(.system(size: 27, weight: .medium)).frame(width: 60, height: 60)
                            .background(SetuColor.brandSoft, in: RoundedRectangle(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    }.buttonStyle(.plain).foregroundStyle(SetuColor.brandPink).disabled(busy)
                        .accessibilityLabel(work.bookmarked ? "取消收藏作品" : "收藏作品")
                        .accessibilityIdentifier("artwork-favorite")
                        .padding(16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !saving.isEmpty { Text(saving).font(.caption).padding(8).background(.regularMaterial, in: Capsule()) }
            }
            .task(id: "\(active)-\(reloadID)") { if active { await load() } else { clearVideo() } }
            .onDisappear { clearVideo() }
            .fullScreenCover(item: $zoom) { page in ArtworkZoomView(page: page, client: store.client, identity: work?.imageIdentity(page) ?? page.id)
                .environment(\.artworkImages, store.images) }
            .alert("图片", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
                Button("知道了", role: .cancel) { }
            } message: { Text(feedback ?? "") }
        }
    }
    @ViewBuilder private func animationView(_ work: BrowserArtwork) -> some View {
        if let player {
            VideoPlayer(player: player).contextMenu { Button("保存 MP4") { Task { await saveVideo() } }.disabled(!saving.isEmpty) }.aspectRatio(work.pages.first?.aspectRatio ?? 1, contentMode: .fit)
                .onAppear { player.play() }
        } else {
            ArtworkMediaImage(path: work.pages.first?.previewUrl, client: store.client, ratio: work.pages.first?.aspectRatio ?? 1, label: work.title, identity: work.pages.first.map { work.imageIdentity($0) }, quality: .preview)
            HStack { Text(animationMessage ?? "正在准备动图…").font(.caption); Button("重试") { reloadID = UUID() } }.padding()
        }
    }
    private func information(_ value: BrowserArtwork) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(value.title).font(.title2.weight(.medium)).textSelection(.enabled)
            HStack(spacing: 14) {
                if let views = value.views { Label(String(views), systemImage: "eye") }
                if let bookmarks = value.bookmarks { Label(String(bookmarks), systemImage: "heart.fill") }
                if let created = value.createdAt { Text(String(created.prefix(10))) }
            }.font(.caption).foregroundStyle(SetuColor.textSecondary)
            HStack {
                Button { UIPasteboard.general.string = value.pid; feedback = "已复制 PID" } label: { Text("PID \(value.pid)"); Image(systemName: "doc.on.doc") }
                Spacer()
                if let page = value.pages.first { Text("\(page.width) × \(page.height)").foregroundStyle(SetuColor.textSecondary) }
            }.font(.caption)
            HStack(spacing: 12) {
                if let avatar = value.artist.avatarUrl { ArtworkMediaImage(path: avatar, client: store.client, label: value.artist.name, maxPixelSize: 160).frame(width: 44).clipShape(Circle()) }
                Button(value.artist.name) { if source == .pixiv { onArtist(value.artist.id) } }.buttonStyle(.plain)
                Spacer()
                if source == .pixiv {
                    Button(value.artist.followed == true ? "已关注" : "关注") { Task { await follow() } }.buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(busy)
                }
            }
            ArtworkTagFlow(tags: value.tags, select: onTag)
            if let error {
                HStack { Text(error).font(.caption); Button("重试详情") { reloadID = UUID() } }
                    .foregroundStyle(SetuColor.textSecondary)
            }
            if let caption = value.caption, !caption.isEmpty { Text(caption).font(.subheadline).foregroundStyle(SetuColor.textSecondary).textSelection(.enabled) }
            if !related.isEmpty {
                Text("继续发现").font(.title2.bold()).padding(.top, 20)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(related) { item in
                        ArtworkTile(work: item, client: store.client, open: { openRelated(item) }, bookmark: { Task { do { try await store.bookmark(item) } catch { feedback = error.localizedDescription } } })
                    }
                }
            }
        }.padding(20).padding(.bottom, 40)
    }
    private func openRelated(_ item: BrowserArtwork) {
        if !store.state(source).items.contains(where: { $0.id == item.id }) { store.state(source).items.append(item) }
        select(item.id)
    }
    private func load() async {
        let id = workID
        clearVideo(); error = nil
        do {
            let value: BrowserArtwork
            if let cached = store.cachedDetail(source: source, id: id), error == nil, (loadedReloadID == nil || loadedReloadID == reloadID) {
                value = cached
            } else { value = try await store.client.detail(source: source, id: id) }
            loadedReloadID = reloadID
            try Task.checkCancellation()
            guard workID == id else { return }
            work = value; store.rememberDetail(value)
            if let index, index > store.state(source).items.count - 6 { await store.load(source) }
            if related.isEmpty, let result = try? await store.client.works(source: source, params: source == .pixiv ? ["view": "related", "relatedId": id] : ["sort": "random", "tag": value.tags.first ?? ""]) {
                try Task.checkCancellation()
                related = Array(result.items.filter { $0.id != id }.prefix(12))
            }
            if value.kind == "ugoira" { await loadAnimation(id) }
        } catch is CancellationError { }
        catch { if !Task.isCancelled && workID == id { self.error = error.localizedDescription } }
    }
    private func loadAnimation(_ id: String) async {
        do {
            var animation = try await store.client.animation(workID: id)
            for _ in 0..<120 {
                try Task.checkCancellation()
                if animation.status == "failed" { animationMessage = animation.message; return }
                if animation.status == "ready", let path = animation.mediaUrl {
                    let data = try await store.client.media(path)
                    try Task.checkCancellation()
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("setu-animation-\(UUID().uuidString).mp4")
                    try data.write(to: file, options: .atomic)
                    videoFile = file
                    let item = AVPlayerItem(url: file)
                    let player = AVQueuePlayer()
                    videoLooper = AVPlayerLooper(player: player, templateItem: item)
                    self.player = player
                    player.play()
                    return
                }
                try await Task.sleep(for: .seconds(2))
                animation = try await store.client.animationStatus(id: animation.id)
            }
            animationMessage = "动图准备超时，请重试"
        } catch { if !Task.isCancelled { animationMessage = error.localizedDescription } }
    }
    private func clearVideo() {
        player?.pause(); videoLooper = nil; player = nil
        if let videoFile { try? FileManager.default.removeItem(at: videoFile) }
        videoFile = nil; animationMessage = nil
    }
    private func bookmark(_ page: ArtworkPage?) async {
        guard var value = work, !busy else { return }
        busy = true; defer { busy = false }
        let enabled = !(page?.bookmarked ?? value.bookmarked)
        do {
            try await store.client.bookmark(value, enabled: enabled, page: page)
            if let page, let index = value.pages.firstIndex(where: { $0.id == page.id }) {
                value.pages[index].bookmarked = enabled
                if index == 0 { value.bookmarked = enabled }
            } else { value.bookmarked = enabled }
            store.update(value)
            if workID == value.id { work = value }
        } catch { feedback = error.localizedDescription }
    }
    private func follow() async {
        guard var value = work, !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await store.client.follow(value.artist, enabled: value.artist.followed != true)
            value.artist.followed = value.artist.followed != true
            if workID == value.id { work = value }
        } catch { feedback = error.localizedDescription }
    }
    @ViewBuilder private func saveMenu(_ value: BrowserArtwork, page: ArtworkPage) -> some View {
        if source == .gallery && value.pages.count > 1 {
            Button(page.bookmarked == true ? "取消收藏本页" : "收藏本页", systemImage: page.bookmarked == true ? "heart.fill" : "heart") {
                Task { await bookmark(page) }
            }.disabled(busy)
        }
        Button("保存原图", systemImage: "square.and.arrow.down") { Task { await save([page]) } }
            .disabled(!saving.isEmpty)
        if value.pages.count > 1 {
            Button("保存整部作品（\(value.pages.count) 张）") { Task { await save(value.pages) } }
                .disabled(!saving.isEmpty)
        }
    }
    private func importCurrentPID() async {
        guard !importing, importTaskID == nil, source == .pixiv,
              environment.authSession.currentUser?.role == .admin, let work else { return }
        importing = true; defer { importing = false }
        do {
            let response = try await environment.adminClient.crawlPixivByIDs(PixivPIDInput.parse(work.pid), skipExisting: true)
            guard let taskID = response.taskID, !taskID.isEmpty else { throw APIError.invalidResponse }
            store.importTasks[work.pid] = taskID
            feedback = "已提交 PID \(work.pid)，可在管理员页面的「图片任务」查看进度和结果。"
        } catch { feedback = error.localizedDescription }
    }
    private func photoPermission() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        if status == .authorized || status == .limited { return true }
        feedback = "请在系统设置中允许亦可添加照片后重试"; return false
    }
    private func save(_ pages: [ArtworkPage]) async {
        guard saving.isEmpty, await photoPermission() else { return }
        var failures = 0
        for (index, page) in pages.enumerated() {
            saving = "保存 \(index + 1)/\(pages.count)"
            do {
                guard let path = page.originalUrl else { throw APIError.invalidResponse }
                let data = try await store.client.media(path)
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            } catch { failures += 1 }
        }
        saving = ""
        feedback = failures == 0 ? "已保存到相册" : "\(failures) 张保存失败，可以重新保存对应图片"
    }
    private func saveVideo() async {
        guard saving.isEmpty, let videoFile, await photoPermission() else { return }
        saving = "正在保存"; defer { saving = "" }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoFile) }
            feedback = "动图已作为视频保存到相册"
        } catch { feedback = error.localizedDescription }
    }
}

private struct ArtworkTagFlow: View {
    let tags: [String]
    let select: (String) -> Void
    var body: some View {
        ImageBrowseTagLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Button { select(tag) } label: { Text("#\(tag)").font(.caption).lineLimit(2).padding(.horizontal, 12).padding(.vertical, 8).background(SetuColor.brandSoft, in: Capsule()) }
                    .buttonStyle(.plain).foregroundStyle(SetuColor.textSecondary)
            }
        }
    }
}

private struct ArtworkZoomView: View {
    let page: ArtworkPage
    let client: ArtworkClient
    let identity: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var initialScale: CGFloat = 1
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    ArtworkMediaImage(path: page.originalUrl ?? page.previewUrl, client: client, ratio: page.aspectRatio, maxPixelSize: 4000, identity: identity, quality: .original)
                        .frame(width: geometry.size.width * scale)
                        .gesture(MagnifyGesture().onChanged { scale = min(5, max(1, initialScale * $0.magnification)) }.onEnded { _ in initialScale = scale })
                        .onTapGesture(count: 2) { scale = scale == 1 ? 2.5 : 1; initialScale = scale }
                }
            }
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }.padding().accessibilityLabel("关闭放大图片")
        }
    }
}
#endif
