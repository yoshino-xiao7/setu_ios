import SetuIOSCore
import SwiftUI

struct CollectionListView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[CollectionInfo]> = .idle
    @State private var editor: CollectionEditorContext?

    var body: some View {
        List {
            Section {
                SetuCard {
                    Button {
                        router.navigate(to: .favorites)
                    } label: {
                        HStack(spacing: SetuSpacing.md) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(SetuColor.brandPink)
                                .frame(width: 40, height: 40)
                                .background(SetuColor.brandSoft.opacity(0.22), in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text("默认收藏")
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                                Text("快速查看默认收藏夹中的图片")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SetuColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "heart", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "收藏夹加载失败",
                            message: message,
                            systemImage: "heart.slash",
                            actionTitle: "重试",
                            action: { Task { await load() } }
                        )
                    }
                }
            case .loaded(let collections):
                if collections.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(
                                title: "暂无收藏夹",
                                message: "创建一个收藏夹，把喜欢的图片按主题整理起来。",
                                systemImage: "heart",
                                actionTitle: "创建收藏夹",
                                action: { editor = .create }
                            )
                        }
                    }
                } else {
                    Section {
                        SetuCard {
                            SetuSectionHeader(title: "我的收藏夹", subtitle: "共 \(collections.count) 个收藏夹")
                        }
                    }
                    Section {
                        ForEach(collections) { collection in
                            Button {
                                router.navigate(to: .collectionDetail(collection.id))
                            } label: {
                                SetuCard {
                                    CollectionRow(collection: collection)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle("我的收藏夹")
        .toolbar {
            Button {
                editor = .create
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("创建收藏夹")
        }
        .sheet(item: $editor) { context in
            CollectionEditorSheet(environment: environment, context: context) {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.collectionClient.listMine())
        } catch {
            state = .failed(UserFacingErrorMapper.map(error).message)
        }
    }
}

private struct CollectionRow: View {
    let collection: CollectionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(collection.name)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                Spacer()
                if collection.isDefault {
                    SetuPill(text: "默认", systemImage: "checkmark.seal", tone: .brand)
                }
            }

            if let description = collection.description, !description.isEmpty {
                Text(description)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }

            HStack(spacing: 12) {
                Label(collection.visibility.title, systemImage: collection.visibility == .publicVisible ? "eye" : "lock")
                Label("\(collection.itemCount ?? 0) 张", systemImage: "photo")
                if collection.isShared == true {
                    Label("已分享", systemImage: "square.and.arrow.up")
                }
            }
            .font(.caption)
            .foregroundStyle(SetuColor.textSecondary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}
