import SetuIOSCore
import SwiftUI

#if os(iOS)
struct ArtworkSelection: Identifiable {
    let source: ArtworkSource
    let workID: String
    var id: String { "\(source.rawValue):\(workID)" }
}

struct ArtworkBrowserView: View {
    @Bindable var environment: AppEnvironment
    @State private var store: ArtworkBrowserStore
    @State private var source: ArtworkSource = .pixiv
    @Namespace private var artworkTransition
    @State private var selection: ArtworkSelection?
    @State private var authorization: PixivAuthorization?
    @State private var showImport = false
    @State private var showFilters = false
    @State private var showUnlink = false
    @State private var feedback: String?
    @State private var authorizing = false
    @AppStorage(PixivImageHost.preferenceKey) private var imageHost = PixivImageHost.mirror.rawValue
    @AppStorage(PixivImageHost.customPreferenceKey) private var customImageHost = ""
    @State private var showImageHost = false
    @State private var imageHostDraft = PixivImageHost.mirror
    @State private var customHostDraft = ""
    @State private var imageHostError: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        _store = State(initialValue: ArtworkBrowserStore(client: environment.artworkClient))
    }
    private var admin: Bool { environment.authSession.currentUser?.role == .admin }
    private var preferenceKey: String { "images.channel.\(environment.authSession.currentUser?.id ?? 0)" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("图片来源", selection: $source) {
                ForEach(ArtworkSource.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 10)
            if source == .pixiv && store.binding == nil && store.accountError == nil {
                ProgressView("正在获取 Pixiv 绑定状态").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if source == .pixiv && store.binding?.bound != true { bindingView }
            else {
                ArtworkChannelView(source: source, state: store.state(source), store: store, transition: artworkTransition, open: { work in
                    selection = ArtworkSelection(source: work.source, workID: work.id)
                }, bookmark: { work in
                    Task { do { try await store.bookmark(work) } catch { feedback = error.localizedDescription } }
                }, artist: { id in Task { await store.selectArtist(id) } }, filters: { showFilters = true })
                .id(source)
            }
        }
        .environment(\.artworkImages, store.images)
        .setuBackground()
        .navigationTitle("图片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SetuToolbarLogo(assetName: "ImageHomeLogo", accessibilityLabel: "图片")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if admin { Button { showImport = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增图片") }
                Menu {
                    Text("浏览与保存免费")
                    Button("图片图床") {
                        imageHostDraft = PixivImageHost(rawValue: imageHost) ?? .mirror
                        customHostDraft = customImageHost; imageHostError = nil; showImageHost = true
                    }
                    if store.binding?.bound == true {
                        Text(store.binding?.name ?? "Pixiv 用户")
                        Button("重新登录 Pixiv") { Task { await authorize() } }
                        Button("刷新 Pixiv 状态") { Task { await store.loadAccount() } }
                        Button("解除 Pixiv 绑定", role: .destructive) { showUnlink = true }
                    } else { Button("绑定 Pixiv") { Task { await authorize() } } }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("图片设置")
            }
        }
        .task {
            source = ArtworkSource(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "pixiv") ?? .pixiv
            if source == .gallery { await store.load(.gallery) }
            await store.loadAccount()
        }
        .onChange(of: store.binding?.version) { _, _ in selection = nil }
        .onChange(of: source) { _, value in
            UserDefaults.standard.set(value.rawValue, forKey: preferenceKey)
            Task { await store.load(value) }
        }
        .sheet(isPresented: $showImageHost) { imageHostSettings }
        .fullScreenCover(item: $selection) { selected in
            ArtworkDetailView(source: selected.source, initialID: selected.workID, store: store, environment: environment, transition: artworkTransition) { id in
                selection = nil; source = .pixiv; Task { await store.selectArtist(id) }
            } onTag: { tag in
                selection = nil; source = selected.source; Task { await store.selectTag(tag, source: selected.source) }
            }
        }
        .sheet(item: $authorization) { session in
            PixivAuthorizationView(authorization: session, client: store.client) {
                Task { await store.loadAccount() }
            }
        }
        .sheet(isPresented: $showImport) { ArtworkPIDImportView(environment: environment) { feedback = "任务已提交，可在管理员页面的「图片任务」查看进度和结果。" } }
        .sheet(isPresented: $showFilters) { ArtworkFiltersView(state: store.state(source), source: source) { Task { await store.load(source, reset: true) } } }
        .confirmationDialog("解除 Pixiv 绑定？", isPresented: $showUnlink, titleVisibility: .visible) {
            Button("解除绑定", role: .destructive) {
                Task { do { try await store.client.unlink(); await store.loadAccount() } catch { feedback = error.localizedDescription } }
            }
        } message: { Text("仅清除这台设备上的 Pixiv 登录与缓存，Pixiv 上的收藏和关注会保留。") }
        .alert("图片", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("知道了", role: .cancel) { }
        } message: { Text(feedback ?? "") }
    }
    private var imageHostSettings: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("图片图床", selection: $imageHostDraft) {
                        ForEach(PixivImageHost.allCases, id: \.rawValue) { host in Text(host.title).tag(host) }
                    }.pickerStyle(.inline)
                    if imageHostDraft == .custom {
                        TextField("images.example.com", text: $customHostDraft)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .accessibilityLabel("自定义图床域名")
                    }
                } footer: {
                    Text("图床需支持 Pixiv 原图片路径。图片请求使用 HTTPS，图床可见所请求的图片路径和网络地址；账号凭据保留在本机。")
                }
                if let imageHostError { Text(imageHostError).foregroundStyle(SetuColor.danger) }
            }
            .navigationTitle("图片图床").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showImageHost = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            if imageHostDraft == .custom { customImageHost = try PixivImageHost.normalizedCustomHost(customHostDraft) }
                            imageHost = imageHostDraft.rawValue; showImageHost = false
                            Task { await store.load(.pixiv, reset: true) }
                        } catch { imageHostError = error.localizedDescription }
                    }
                }
            }
        }.tint(SetuColor.brandPink)
    }
    private var bindingView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54)).foregroundStyle(SetuColor.brandPink).padding(.top, 60)
                Text("连接你的 Pixiv 世界").font(.title2.bold())
                Text("使用增强连接（ECH）访问 Pixiv。\n登录信息仅保存在本机，收藏与关注同步到 Pixiv。")
                    .font(.subheadline).foregroundStyle(SetuColor.textSecondary).multilineTextAlignment(.center)
                if let error = store.accountError { Text(error).font(.caption).foregroundStyle(SetuColor.danger) }
                Button { Task { await authorize() } } label: {
                    HStack { if authorizing { ProgressView() }; Text("登录 Pixiv") }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(SetuColor.brandPink).disabled(authorizing)
                Button("刷新绑定状态") { Task { await store.loadAccount() } }
                Button("先逛逛本站图库 →") { source = .gallery }
            }.padding(24)
        }.refreshable { await store.loadAccount() }
    }
    private func authorize() async {
        authorizing = true
        defer { authorizing = false }
        do { authorization = try await store.client.authorize() }
        catch { feedback = error.localizedDescription }
    }
}

private struct ArtworkChannelView: View {
    let source: ArtworkSource
    @Bindable var state: ArtworkChannelState
    @Bindable var store: ArtworkBrowserStore
    let transition: Namespace.ID
    let open: (BrowserArtwork) -> Void
    let bookmark: (BrowserArtwork) -> Void
    let artist: (String) -> Void
    let filters: () -> Void

    private var columns: [[BrowserArtwork]] {
        var columns: [[BrowserArtwork]] = [[], []]
        var heights = [Double(0), Double(0)]
        for work in state.items {
            let index = heights[0] <= heights[1] ? 0 : 1
            columns[index].append(work)
            heights[index] += 1 / (work.pages.first?.aspectRatio ?? 1) + 0.35
        }
        return columns
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                if source == .pixiv && state.view == "recommended" && state.query.isEmpty {
                    if let error = store.homeError { Text(error).font(.caption).foregroundStyle(SetuColor.textSecondary) }
                    if !store.spotlights.isEmpty { spotlightSection }
                    HStack {
                        Text("为你推荐").font(.title2.bold())
                        Spacer(minLength: 12)
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach(store.artists) { person in
                                    Button { artist(person.id) } label: {
                                        ArtworkMediaImage(path: person.avatarUrl, client: store.client, label: person.name, maxPixelSize: 150).frame(width: 42).clipShape(Circle())
                                    }.buttonStyle(.plain).accessibilityLabel("查看 \(person.name) 的作品")
                                }
                            }
                        }.scrollIndicators(.hidden).frame(maxWidth: 190)
                    }
                } else { Text(source == .gallery ? "本站图库" : state.view == "artist" ? "画师作品" : state.query.isEmpty ? "发现作品" : "搜索结果").font(.title2.bold()) }
                if !state.tag.isEmpty {
                    Button("#\(state.tag) · 清除筛选") { state.tag = ""; Task { await store.load(source, reset: true) } }.font(.caption)
                }
                if let error = state.error {
                    VStack(spacing: 10) {
                        Text(error).font(.caption).foregroundStyle(SetuColor.danger)
                        Button("重试") { Task { await store.load(source, reset: !state.loaded) } }
                    }.frame(maxWidth: .infinity).padding()
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<2) { column in
                        LazyVStack(spacing: 12) {
                            ForEach(columns[column]) { work in
                                ArtworkTile(work: work, client: store.client, transition: transition, busy: store.busyIDs.contains(work.id), open: { open(work) }, bookmark: { bookmark(work) })
                                    .id(work.id)
                            }
                        }.scrollTargetLayout()
                    }
                }
                if state.loading { ProgressView("正在发现作品").frame(maxWidth: .infinity).padding() }
                if state.loaded && state.items.isEmpty && state.error == nil {
                    ContentUnavailableView("暂无作品", systemImage: "photo.on.rectangle", description: Text("试试更换关键词或筛选条件"))
                }
                if state.cursor != nil {
                    Button("继续发现") { Task { await store.load(source) } }
                        .frame(maxWidth: .infinity).padding().onAppear { if state.error == nil { Task { await store.load(source) } } }
                } else if state.loaded && !state.items.isEmpty {
                    Text("已看到这里的全部作品").font(.caption).foregroundStyle(SetuColor.textTertiary).frame(maxWidth: .infinity).padding()
                }
            }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 24)
        }
        .scrollPosition(id: $state.scrollID)
        .refreshable { await store.load(source, reset: true) }
    }
    private var controls: some View {
        VStack(spacing: 12) {
            if source == .pixiv {
                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach([("recommended", "推荐"), ("ranking", "排行"), ("bookmarks", "收藏"), ("privateBookmarks", "私密收藏"), ("following", "关注")], id: \.0) { option in
                            Button(option.1) { state.view = option.0; state.query = ""; Task { await store.load(source, reset: true) } }
                                .font(.subheadline.weight(state.view == option.0 ? .semibold : .regular))
                                .foregroundStyle(state.view == option.0 ? SetuColor.brandPink : SetuColor.textSecondary)
                                .frame(minHeight: 44)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(SetuColor.textTertiary)
                TextField("搜索作品、画师或标签", text: $state.query).font(.subheadline).submitLabel(.search)
                    .onSubmit { Task { await store.load(source, reset: true) } }
                Button(action: filters) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("图片筛选")
            }.padding(.leading, 12).background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private var spotlightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("亮点").font(.title2.bold())
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(store.spotlights) { article in
                        if let url = URL(string: article.url) {
                            Link(destination: url) {
                                ArtworkMediaImage(path: article.thumbnailUrl, client: store.client, ratio: 1.9, label: article.title, contentMode: .fill)
                                    .overlay(alignment: .bottomLeading) {
                                        Text(article.title).font(.subheadline).lineLimit(2).foregroundStyle(.white)
                                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                                    }.frame(width: 280).clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }
}

private struct ArtworkFiltersView: View {
    @Bindable var state: ArtworkChannelState
    let source: ArtworkSource
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if source == .gallery {
                    Picker("排序", selection: $state.sort) { Text("最新作品").tag("latest"); Text("随机发现").tag("random") }
                    TextField("精确标签", text: $state.tag)
                    Picker("来源", selection: $state.sourceFilter) { Text("全部来源").tag("ALL"); Text("Pixiv 导入").tag("PIXIV"); Text("用户投稿").tag("YUKIRYOU") }
                }
                if source == .pixiv && state.view == "ranking" {
                    Picker("排行", selection: $state.ranking) { Text("日榜").tag("day"); Text("周榜").tag("week"); Text("月榜").tag("month") }
                }
                Picker("内容", selection: $state.r18) { Text("普通内容").tag(0); Text("限制级内容").tag(1); Text("全部内容").tag(2) }
                Toggle("排除 AI 作品", isOn: $state.excludeAI)
                Text("浏览、原图查看及保存均不消耗积分。").font(.caption).foregroundStyle(SetuColor.textSecondary)
            }.navigationTitle("图片筛选").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("应用") { apply(); dismiss() } } }
        }.presentationDetents([.medium])
    }
}
#else
struct ArtworkBrowserView: View {
    let environment: AppEnvironment
    var body: some View { Text("请在 iOS 或 Web 使用图片浏览") }
}
#endif
