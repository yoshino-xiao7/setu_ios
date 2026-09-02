import SetuIOSCore
import SwiftUI

struct PointsCallView: View {
    @Environment(\.setuRecoveryActions) private var recovery
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var feedback: SetuFeedback?
    @State private var userFacingError: UserFacingError?
    @State private var favoriteTarget: SetuImageItem?
    @State private var deleteTarget: SetuImageItem?
    @State private var previewTarget: UserImagePreviewItem?
    @State private var favoriteStates: [String: LoadState<Bool>] = [:]
    @State private var favoriteStatusLoadID = UUID()

    private let costPerCall = 20

    var body: some View {
        List {
            overviewSection
            requestSection
            if let userFacingError {
                Section {
                    SetuFeedbackBanner(error: userFacingError, onAction: handleErrorAction)
                }
                .setuListRow()
            } else if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }
                .setuListRow()
            }
            resultsSection
        }
        .listStyle(.plain)
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .accessibilityIdentifier("points.page")
        .navigationTitle("按条件找图")
        .toolbar {
            Button {
                router.navigate(to: .pointsLogs)
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .accessibilityLabel("查看积分明细")
        }
        .sheet(item: $favoriteTarget) { item in
            PointsFavoriteSheet(environment: environment, item: item) { result, savedToDefault in
                if case .success = result, savedToDefault {
                    favoriteStates[item.id] = .loaded(true)
                }
                userFacingError = nil
                feedback = result
            }
        }
        .sheet(item: $deleteTarget) { item in
            PointsDeleteRequestSheet(environment: environment, item: item) { result in
                userFacingError = nil
                feedback = result
            }
        }
        .sheet(item: $previewTarget) { item in
            UserImagePreviewSheet(item: item)
        }
        .task { await loadPoints() }
        .refreshable { await loadPoints() }
    }

    private var overviewSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    SetuSectionHeader(title: "积分概览", subtitle: "每次获取会消耗积分，完成后自动刷新余额")
                    switch pointsState {
                    case .idle, .loading:
                        SetuEmptyState(title: "正在加载积分", message: "同步你的当前积分余额", systemImage: "creditcard", isLoading: true)
                    case .failed(let message):
                        SetuEmptyState(
                            title: "积分加载失败",
                            message: message,
                            systemImage: "exclamationmark.triangle",
                            actionTitle: "重试",
                            action: { Task { await loadPoints() } }
                        )
                    case .loaded(let balance):
                        statLayout {
                            SetuStatTile(title: "当前积分", value: "\(balance.points)", systemImage: "sparkles", color: SetuColor.brandPink)
                            SetuStatTile(title: "单次消耗", value: "\(costPerCall)", systemImage: "minus.circle", color: SetuColor.warning)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: SetuSpacing.sm) { parameterPills }
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) { parameterPills }
                        }
                    }
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text("关键词：\(keyword.isEmpty ? "未填写" : keyword)")
                        Text("标签：\(tagText.isEmpty ? "未填写" : tagText)")
                    }
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .setuListRow()
    }

    private var statLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: SetuSpacing.md))
            : AnyLayout(HStackLayout(spacing: SetuSpacing.md))
    }

    @ViewBuilder
    private var parameterPills: some View {
        SetuPill(text: r18Title, systemImage: "shield.lefthalf.filled", tone: r18 == 1 ? .danger : .muted)
        SetuPill(text: sizeTitle, systemImage: "rectangle", tone: .info)
        SetuPill(text: "数量 \(num)", systemImage: "photo.stack", tone: .brand)
        SetuPill(text: "\(results.count) 张结果", systemImage: "photo.on.rectangle", tone: .success)
    }

    private var requestSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "筛选条件", subtitle: "选择内容、清晰度与数量后开始找图")
                    Picker("内容级别", selection: $r18) {
                        Text("普通内容").tag(0)
                        Text("成人内容").tag(1)
                        Text("混合").tag(2)
                    }
                    Picker("图片尺寸", selection: $size) {
                        Text("清晰（推荐）").tag("regular")
                        Text("原始尺寸").tag("original")
                        Text("流量节省").tag("small")
                    }
                    Stepper("数量：\(num)", value: $num, in: 1...20)
                    TextField("关键词", text: $keyword)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    TextField("标签，逗号分隔", text: $tagText)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Toggle("排除 AI 图片", isOn: $excludeAI)
                        .tint(SetuColor.brandPink)
                    SetuPrimaryButton {
                        Task { await callSetu() }
                    } label: {
                        if calling {
                            HStack(spacing: SetuSpacing.sm) {
                                ProgressView()
                                    .tint(.white)
                                Text("正在寻找图片")
                            }
                        } else {
                            Label("获取图片", systemImage: "photo.on.rectangle")
                        }
                    }
                    .disabled(calling || !canAttemptCall)
                    .accessibilityIdentifier("points.call")
                }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var resultsSection: some View {
        if results.isEmpty {
            Section {
                SetuEmptyState(title: "暂无图片", message: "设置参数后获取图片", systemImage: "photo.on.rectangle")
            }
            .setuListRow()
        } else {
            Section {
                SetuSectionHeader(title: "获取结果", subtitle: "\(results.count) 张图片")
                    .padding(.horizontal, SetuSpacing.lg)
                    .setuListRow()
                ForEach(results) { item in
                    SetuCard {
                        PointsResultRow(item: item, favoriteState: favoriteStates[item.id] ?? .idle) {
                            previewTarget = UserImagePreviewItem(image: item)
                        } onFavorite: {
                            favoriteTarget = item
                        } onRetryFavoriteStatus: {
                            Task { await retryDefaultFavoriteStatus(for: item) }
                        } onDeleteRequest: {
                            deleteTarget = item
                        }
                    }
                    .setuListRow()
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

    private var canAttemptCall: Bool {
        if case .loaded = pointsState {
            return true
        }
        return false
    }

    private var r18Title: String {
        switch r18 {
        case 1: "成人内容"
        case 2: "混合"
        default: "普通内容"
        }
    }

    private var sizeTitle: String {
        switch size {
        case "original": "原始尺寸"
        case "small": "流量节省"
        default: "清晰"
        }
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
            pointsState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func callSetu() async {
        guard canCall else {
            feedback = nil
            userFacingError = UserFacingError(
                title: "积分不足",
                message: "至少需要 \(costPerCall) 积分才能获取图片，你可以先查看积分明细。",
                action: .viewPoints,
                diagnosticCode: nil
            )
            return
        }
        calling = true
        feedback = nil
        userFacingError = nil
        results = []
        favoriteStatusLoadID = UUID()
        favoriteStates = [:]
        do {
            let request = PointsCallRequest(r18: r18, num: num, keyword: keyword, tags: parsedTags, size: size, excludeAI: excludeAI)
            let nextResults = try await environment.pointsClient.callSetu(request: request)
            let loadID = UUID()
            favoriteStatusLoadID = loadID
            favoriteStates = Dictionary(uniqueKeysWithValues: nextResults.map { ($0.id, .loading) })
            results = nextResults
            Task { await loadDefaultFavoriteStatuses(for: nextResults, loadID: loadID) }
            await loadPoints()
            feedback = results.isEmpty
                ? .info("当前筛选条件没有匹配图片")
                : .success("已获取 \(results.count) 张图片")
        } catch {
            userFacingError = UserFacingErrorMapper.map(error)
            await loadPoints()
        }
        calling = false
    }

    private func handleErrorAction(_ action: UserFacingErrorAction) {
        switch action {
        case .retry:
            Task { await loadPoints() }
            userFacingError = nil
            feedback = .info("请确认积分与已有结果，再点击找图按钮。")
        case .refresh:
            Task { await loadPoints() }
        case .signIn:
            recovery.signIn?()
        case .goBack:
            if !router.path.isEmpty {
                router.path.removeLast()
            }
        case .reviewInput:
            userFacingError = nil
            feedback = .info("请检查筛选条件后重试。")
        case .wait:
            userFacingError = nil
        case .viewPoints:
            userFacingError = nil
            router.navigate(to: .pointsLogs)
        }
    }

    private func loadDefaultFavoriteStatuses(for items: [SetuImageItem], loadID: UUID) async {
        let client = environment.favoriteClient
        let batchSize = 4

        for start in stride(from: 0, to: items.count, by: batchSize) {
            guard loadID == favoriteStatusLoadID else { return }
            let end = min(start + batchSize, items.count)
            let batch = Array(items[start..<end])

            await withTaskGroup(of: (String, PointsFavoriteStatusResult).self) { group in
                for item in batch {
                    group.addTask {
                        do {
                            let isFavorited = try await client.exists(pid: item.pid, p: item.page)
                            return (item.id, .loaded(isFavorited))
                        } catch {
                            return (item.id, .failed(UserFacingErrorMapper.map(error)))
                        }
                    }
                }

                for await (itemID, result) in group {
                    guard loadID == favoriteStatusLoadID,
                          results.contains(where: { $0.id == itemID }) else { continue }
                    favoriteStates[itemID] = result.loadState
                }
            }
        }
    }

    private func retryDefaultFavoriteStatus(for item: SetuImageItem) async {
        let loadID = favoriteStatusLoadID
        guard results.contains(where: { $0.id == item.id }) else { return }
        favoriteStates[item.id] = .loading
        do {
            let isFavorited = try await environment.favoriteClient.exists(pid: item.pid, p: item.page)
            guard loadID == favoriteStatusLoadID,
                  results.contains(where: { $0.id == item.id }) else { return }
            favoriteStates[item.id] = .loaded(isFavorited)
        } catch {
            guard loadID == favoriteStatusLoadID,
                  results.contains(where: { $0.id == item.id }) else { return }
            favoriteStates[item.id] = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

private enum PointsFavoriteStatusResult: Sendable {
    case loaded(Bool)
    case failed(UserFacingError)

    var loadState: LoadState<Bool> {
        switch self {
        case .loaded(let value): .loaded(value)
        case .failed(let message): .failed(message)
        }
    }
}

private struct PointsResultRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: SetuImageItem
    let favoriteState: LoadState<Bool>
    let onPreview: () -> Void
    let onFavorite: () -> Void
    let onRetryFavoriteStatus: () -> Void
    let onDeleteRequest: () -> Void

    var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            SetuRemoteImage(
                urlString: item.previewURLString,
                accessibilityLabel: "图片：\(item.title)",
                onActivate: onPreview,
                activationHint: "打开预览，可保存或分享"
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(item.author)
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                ViewThatFits(in: .horizontal) {
                    metadata
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)

                if case .failed = favoriteState {
                    Button("重试收藏状态", action: onRetryFavoriteStatus)
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("points.favorite.retry.\(item.id)")
                }
            }
            Spacer()
            actionsMenu
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("points.result.\(item.id)")
    }

    private var metadata: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Label("\(item.width) × \(item.height)", systemImage: "rectangle")
            if item.r18 == 1 {
                SetuPill(text: "成人内容", tone: .danger)
            }
            if case .loaded(true) = favoriteState {
                Label("已收藏", systemImage: "heart.fill")
            } else if case .loading = favoriteState {
                Label("正在确认收藏", systemImage: "clock")
            } else if case .failed = favoriteState {
                Label("收藏状态未知", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SetuColor.warning)
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button(action: onFavorite) {
                Label(favoriteActionTitle, systemImage: favoriteActionSystemImage)
            }
            .disabled(!favoriteActionIsAvailable)
            Button(action: onDeleteRequest) {
                Label("申请删除", systemImage: "trash")
            }
            Button(action: onPreview) {
                Label("预览、保存与分享", systemImage: "eye")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(SetuColor.brandInk)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("更多图片操作")
    }

    private var favoriteActionTitle: String {
        switch favoriteState {
        case .loaded(true): "收藏到其他收藏夹"
        case .loaded(false): "收藏"
        case .idle, .loading: "正在确认收藏状态"
        case .failed: "收藏状态未知"
        }
    }

    private var favoriteActionSystemImage: String {
        if case .loaded(true) = favoriteState { return "heart.fill" }
        return "heart"
    }

    private var favoriteActionIsAvailable: Bool {
        if case .loaded = favoriteState { return true }
        return false
    }
}

private struct PointsFavoriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: SetuImageItem
    let onDone: (SetuFeedback, Bool) -> Void

    @State private var state: LoadState<[CollectionInfo]> = .idle
    @State private var selectedID: Int?
    @State private var saving = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "收藏图片", subtitle: item.title)
                            switch state {
                            case .idle, .loading:
                                SetuEmptyState(title: "正在加载收藏夹", message: "请选择要收藏到的位置", systemImage: "heart", isLoading: true)
                            case .failed(let message):
                                SetuEmptyState(title: "收藏夹加载失败", message: message, systemImage: "exclamationmark.triangle")
                            case .loaded(let collections):
                                Picker("收藏到", selection: $selectedID) {
                                    ForEach(collections) { collection in
                                        Text(collection.name).tag(Optional(collection.id))
                                    }
                                }
                            }
                        }
                    }
                }
                .setuListRow()

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                    .setuListRow()
                }
            }
            .listStyle(.plain)
            .setuBackground()
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
            state = .failed(UserFacingErrorMapper.map(error))
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
            onDone(
                .success("已收藏到「\(collection?.name ?? "收藏夹")」"),
                collection?.isDefault == true
            )
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
        saving = false
    }
}

private struct PointsDeleteRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let item: SetuImageItem
    let onDone: (SetuFeedback) -> Void

    @State private var reason = ""
    @State private var submitting = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "图片", subtitle: "确认要申请删除的图片")
                            LabeledContent("标题", value: item.title)
                            LabeledContent("作者", value: item.author)
                            LabeledContent("画幅", value: "\(item.width) × \(item.height)")
                        }
                    }
                }
                .setuListRow()

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                    .setuListRow()
                }

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "原因", subtitle: "可选填写，便于管理员判断")
                            TextField("可选", text: $reason, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .setuListRow()
            }
            .listStyle(.plain)
            .setuBackground()
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
            onDone(.success("申请已提交，请在我的删除申请中查看进度"))
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
        submitting = false
    }
}
