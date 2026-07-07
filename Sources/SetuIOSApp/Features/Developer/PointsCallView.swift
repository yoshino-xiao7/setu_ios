import SetuIOSCore
import SwiftUI

struct PointsCallView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    @State private var pointsState: LoadState<PointsBalance> = .idle
    @State private var results: [SetuImageItem] = []
    @State private var r18 = 0
    @State private var num = 1
    @State private var keyword = ""
    @State private var tagText = ""
    @State private var size = "regular"
    @State private var excludeAI = true
    @State private var calling = false
    @State private var message: String?
    @State private var favoriteTarget: SetuImageItem?
    @State private var deleteTarget: SetuImageItem?
    @State private var defaultFavoriteIDs: Set<String> = []

    private let costPerCall = 20

    var body: some View {
        List {
            overviewSection
            requestSection
            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            resultsSection
        }
        .navigationTitle("积分调用")
        .toolbar {
            Button {
                router.navigate(to: .pointsLogs)
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
        }
        .sheet(item: $favoriteTarget) { item in
            PointsFavoriteSheet(environment: environment, item: item) { text in
                defaultFavoriteIDs.insert(item.id)
                message = text
            }
        }
        .sheet(item: $deleteTarget) { item in
            PointsDeleteRequestSheet(environment: environment, item: item) { text in
                message = text
            }
        }
        .task { await loadPoints() }
        .refreshable { await loadPoints() }
    }

    private var overviewSection: some View {
        Section("余额") {
            switch pointsState {
            case .idle, .loading:
                ProgressView("正在加载积分")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let balance):
                LabeledContent("当前积分", value: "\(balance.points)")
                LabeledContent("单次消耗", value: "\(costPerCall)")
                LabeledContent("本页结果", value: "\(results.count)")
            }
        }
    }

    private var requestSection: some View {
        Section("调用参数") {
            Picker("R18", selection: $r18) {
                Text("非 R18").tag(0)
                Text("R18").tag(1)
                Text("混合").tag(2)
            }
            Picker("图片尺寸", selection: $size) {
                Text("regular（推荐）").tag("regular")
                Text("original（原图）").tag("original")
                Text("small（小图）").tag("small")
            }
            Stepper("数量：\(num)", value: $num, in: 1...20)
            TextField("关键词", text: $keyword)
            TextField("标签，逗号分隔", text: $tagText)
            Toggle("排除 AI 图片", isOn: $excludeAI)
            Button {
                Task { await callSetu() }
            } label: {
                if calling {
                    ProgressView()
                } else {
                    Label("调用 /setu/v2", systemImage: "bolt.circle")
                }
            }
            .disabled(calling || !canCall)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if results.isEmpty {
            Section {
                ContentUnavailableView("暂无调用结果", systemImage: "photo.on.rectangle", description: Text("设置参数后调用 /setu/v2。"))
            }
        } else {
            Section("调用结果") {
                ForEach(results) { item in
                    PointsResultRow(item: item, isDefaultFavorited: defaultFavoriteIDs.contains(item.id)) {
                        favoriteTarget = item
                    } onDeleteRequest: {
                        deleteTarget = item
                    }
                }
            }
        }
    }

    private var currentPoints: Int {
        if case .loaded(let balance) = pointsState {
            return balance.points
        }
        return 0
    }

    private var canCall: Bool {
        currentPoints >= costPerCall
    }

    private var parsedTags: [String] {
        tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func loadPoints() async {
        pointsState = .loading
        do {
            pointsState = .loaded(try await environment.pointsClient.balance())
        } catch {
            pointsState = .failed(error.localizedDescription)
        }
    }

    private func callSetu() async {
        guard canCall else {
            message = "积分不足：至少需要 \(costPerCall) 积分"
            return
        }
        calling = true
        message = nil
        results = []
        defaultFavoriteIDs = []
        do {
            let request = PointsCallRequest(r18: r18, num: num, keyword: keyword, tags: parsedTags, size: size, excludeAI: excludeAI)
            results = try await environment.pointsClient.callSetu(request: request)
            await loadDefaultFavoriteStatuses(for: results)
            await loadPoints()
            message = results.isEmpty ? "返回为空：当前筛选条件没有匹配图片" : "成功返回 \(results.count) 张"
        } catch {
            message = error.localizedDescription
            await loadPoints()
        }
        calling = false
    }

    private func loadDefaultFavoriteStatuses(for items: [SetuImageItem]) async {
        var nextIDs = Set<String>()
        for item in items {
            if (try? await environment.favoriteClient.exists(pid: item.pid, p: item.page)) == true {
                nextIDs.insert(item.id)
            }
        }
        defaultFavoriteIDs = nextIDs
    }
}

private struct PointsResultRow: View {
    let item: SetuImageItem
    let isDefaultFavorited: Bool
    let onFavorite: () -> Void
    let onDeleteRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ImageThumbnailView(urlString: item.previewURLString)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.author)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(item.pid)-\(item.page)", systemImage: "number")
                    Label("\(item.width)x\(item.height)", systemImage: "rectangle")
                    if item.r18 == 1 {
                        Text("R18")
                    }
                    if isDefaultFavorited {
                        Label("已收藏", systemImage: "heart.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button(action: onFavorite) {
                    Label(isDefaultFavorited ? "收藏到其他收藏夹" : "收藏", systemImage: isDefaultFavorited ? "heart.fill" : "heart")
                }
                Button(action: onDeleteRequest) {
                    Label("申请删除", systemImage: "trash")
                }
                if let urlString = item.originalURLString, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("打开原图", systemImage: "arrow.up.forward.square")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

private struct PointsFavoriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: SetuImageItem
    let onDone: (String) -> Void

    @State private var state: LoadState<[CollectionInfo]> = .idle
    @State private var selectedID: Int?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                switch state {
                case .idle, .loading:
                    ProgressView("正在加载收藏夹")
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.red)
                case .loaded(let collections):
                    Picker("收藏到", selection: $selectedID) {
                        ForEach(collections) { collection in
                            Text(collection.name).tag(Optional(collection.id))
                        }
                    }
                }
            }
            .navigationTitle("收藏图片")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("收藏") {
                        Task { await save() }
                    }
                    .disabled(selectedID == nil || saving)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            let collections = try await environment.collectionClient.listMine()
            state = .loaded(collections)
            selectedID = collections.first(where: { $0.isDefault })?.id ?? collections.first?.id
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let selectedID, case .loaded(let collections) = state else { return }
        saving = true
        do {
            let collection = collections.first { $0.id == selectedID }
            if collection?.isDefault == true {
                try await environment.favoriteClient.add(pid: item.pid, p: item.page)
            } else {
                try await environment.collectionClient.addItem(collectionID: selectedID, pid: item.pid, p: item.page)
            }
            onDone("已收藏到「\(collection?.name ?? "收藏夹")」")
            dismiss()
        } catch {
            onDone(error.localizedDescription)
        }
        saving = false
    }
}

private struct PointsDeleteRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: SetuImageItem
    let onDone: (String) -> Void

    @State private var reason = ""
    @State private var submitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("图片") {
                    LabeledContent("标题", value: item.title)
                    LabeledContent("PID", value: "\(item.pid)_p\(item.page)")
                }
                Section("原因") {
                    TextField("可选", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("申请删除")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Task { await submit() }
                    }
                    .disabled(submitting)
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        do {
            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            try await environment.imageDeleteRequestClient.submit(pid: item.pid, p: item.page, reason: trimmedReason.isEmpty ? nil : trimmedReason)
            onDone("申请已提交，请在我的删除申请中查看进度")
            dismiss()
        } catch {
            onDone(error.localizedDescription)
        }
        submitting = false
    }
}
