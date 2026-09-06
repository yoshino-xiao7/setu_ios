import SetuIOSCore
import SwiftUI

struct MusicCutoverSearchView: View {
    @Environment(MusicStore.self) private var store
    @Environment(RouterPath.self) private var router
    let environment: AppEnvironment
    let initialQuery: String?
    private var flags: MusicFeatureFlags { environment.config.musicFeatureFlags }
    var body: some View {
        @Bindable var session = store.v2SearchSession
        List {
            Section {
                TextField("搜索音乐", text: $session.query).onSubmit { search() }
                Picker("搜索范围", selection: $session.scope) {
                    ForEach(MusicV2SearchScope.allCases, id: \.self) { scope in Text(label(scope)).tag(scope) }
                }
                Button("搜索") { search() }.disabled(session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if session.loading { ProgressView("正在搜索") }
            if let error = session.error {
                Text(error.message)
                Button("重试") { search(more: session.nextOffset != nil) }
            }
            ForEach(Array(session.pages.enumerated()), id: \.offset) { _, result in
                ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in content(section) }
            }
            if session.pages.isEmpty && !session.loading && session.error == nil {
                ContentUnavailableView("搜索音乐", systemImage: "magnifyingglass", description: Text("输入关键词开始搜索"))
            }
            if session.nextOffset != nil { Button("加载更多") { search(more: true) }.disabled(session.loading) }
        }
        .listStyle(.plain).setuBackground().navigationTitle("搜索")
        .task(id: store.userID) {
            if let initialQuery, store.v2SearchSession.pages.isEmpty {
                store.v2SearchSession.query = initialQuery
                await store.v2SearchSession.submit(client: environment.musicV2Client)
            }
        }
    }
    private func search(more: Bool = false) { Task { await store.v2SearchSession.submit(client: environment.musicV2Client, more: more) } }
    private func label(_ scope: MusicV2SearchScope) -> String {
        switch scope { case .all: "综合"; case .tracks: "歌曲"; case .artists: "歌手"; case .albums: "专辑"; case .playlists: "歌单"; case .mvs: "MV" }
    }
    @ViewBuilder private func content(_ section: MusicV2SearchSection) -> some View {
        switch section {
        case .tracks(let page):
            Section("歌曲") { MusicDetailTracks(tracks: page.items, context: .unknown(reason: .missingProvenance, label: "搜索"), flags: flags) }
        case .artists(let page):
            Section("歌手") {
                if page.items.isEmpty { Text("暂无歌手") }
                ForEach(page.items, id: \.id) { item in
                    if let route = MusicDetailRoutes.artist(item.id, flags: flags) { Button(item.name) { router.navigate(to: route) } }
                    else { Text(item.name) }
                }
            }
        case .albums(let page):
            Section("专辑") {
                if page.items.isEmpty { Text("暂无专辑") }
                ForEach(page.items, id: \.id) { item in
                    if let route = MusicDetailRoutes.album(item.id, flags: flags) { Button(item.title) { router.navigate(to: route) } }
                    else { Text(item.title) }
                }
            }
        case .playlists(let page):
            Section("歌单") {
                if page.items.isEmpty { Text("暂无歌单") }
                ForEach(page.items, id: \.id) { item in
                    if flags.usesV2PlaylistDetail { Button(item.title) { router.navigate(to: .playlistDetailV2(item.id.rawValue)) } }
                    else { Text(item.title) }
                }
            }
        case .mvs(let page):
            Section("MV") {
                if page.items.isEmpty { Text("暂无 MV") }
                ForEach(page.items, id: \.id) { item in Text(item.title) }
            }
        case .failed(let scope, _):
            Section(label(scope)) { Text("此范围暂时不可用"); Button("重试搜索") { search() } }
        case .unknown: EmptyView()
        }
    }
}
