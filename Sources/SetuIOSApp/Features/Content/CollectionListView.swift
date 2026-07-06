import SetuIOSCore
import SwiftUI

struct CollectionListView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[CollectionInfo]> = .idle

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("收藏夹加载失败", systemImage: "heart.slash", description: Text(message))
            case .loaded(let collections):
                if collections.isEmpty {
                    ContentUnavailableView("暂无收藏夹", systemImage: "heart", description: Text("网页端或图片详情中创建收藏夹后会显示在这里。"))
                } else {
                    Section("共 \(collections.count) 个收藏夹") {
                        ForEach(collections) { collection in
                            CollectionRow(collection: collection)
                        }
                    }
                }
            }
        }
        .navigationTitle("我的收藏夹")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.collectionClient.listMine())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct CollectionRow: View {
    let collection: CollectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(collection.name)
                    .font(.headline)
                Spacer()
                if collection.isDefault {
                    Label("默认", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }

            if let description = collection.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(collection.visibility.title, systemImage: collection.visibility == .publicVisible ? "eye" : "lock")
                Label("\(collection.itemCount ?? 0) 张", systemImage: "photo")
                if collection.isShared == true {
                    Label("已分享", systemImage: "square.and.arrow.up")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
