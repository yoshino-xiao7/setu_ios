import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct RandomImageSwipeView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    @State private var pointsState: LoadState<PointsBalance> = .idle
    @State private var imageState: LoadState<SetuImageItem> = .idle
    @State private var currentImage: SetuImageItem?
    @State private var r18 = 0
    @State private var keyword = ""
    @State private var tagText = ""
    @State private var size = "regular"
    @State private var excludeAI = true
    @State private var message: String?
    @State private var showingParameters = false
    @State private var dragOffset = CGSize.zero

    private let costPerCall = 20

    var body: some View {
        ZStack {
            SetuColor.pageGradient
                .ignoresSafeArea()

            VStack(spacing: SetuSpacing.md) {
                statusStrip
                if let message {
                    messageStrip(message)
                }
                imageStage
                actionBar
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.bottom, SetuSpacing.sm)
        }
        .navigationTitle("随机图片")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingParameters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                Menu {
                    Button {
                        router.navigate(to: .points)
                    } label: {
                        Label("高级参数与批量获取", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        router.navigate(to: .pointsLogs)
                    } label: {
                        Label("积分流水", systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        router.navigate(to: .galleryUploads)
                    } label: {
                        Label("图库投稿", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        router.navigate(to: .imageDeleteRequests)
                    } label: {
                        Label("我的删除申请", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingParameters) {
            RandomImageParameterSheet(
                r18: $r18,
                keyword: $keyword,
                tagText: $tagText,
                size: $size,
                excludeAI: $excludeAI
            ) {
                showingParameters = false
                Task { await reloadFromParameters() }
            }
        }
        .task {
            await loadPoints()
            if currentImage == nil {
                await loadNextImage(reason: "上滑、下滑或左右滑继续刷图")
            }
        }
        .refreshable {
            await reloadFromParameters()
        }
    }

    private var statusStrip: some View {
        HStack(spacing: SetuSpacing.sm) {
            Label(pointsText, systemImage: "bolt.circle")
            Divider()
                .frame(height: 18)
            Label("单次 \(costPerCall)", systemImage: "tag")
            Spacer()
            if isLoadingImage {
                ProgressView()
                    .tint(SetuColor.brandPink)
            } else {
                Label("滑动换图", systemImage: "hand.draw")
            }
        }
        .font(.footnote)
        .foregroundStyle(SetuColor.textSecondary)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.sm)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private func messageStrip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: text.contains("失败") || text.contains("不足") ? "exclamationmark.triangle" : "hand.draw")
            Text(text)
                .lineLimit(2)
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(text.contains("失败") || text.contains("不足") ? SetuColor.danger : SetuColor.textSecondary)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.sm)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: SetuRadius.lg)
                    .fill(SetuColor.surfaceMuted)

                switch imageState {
                case .idle where currentImage == nil:
                    loadingPlaceholder
                case .loading where currentImage == nil:
                    loadingPlaceholder
                case .failed(let text) where currentImage == nil:
                    SetuEmptyState(title: "图片加载失败", message: text, systemImage: "photo.on.rectangle")
                default:
                    if let currentImage {
                        RandomImageCard(item: currentImage, stageSize: proxy.size)
                    } else {
                        SetuEmptyState(title: "暂无图片", systemImage: "photo.on.rectangle")
                    }
                }

                if isLoadingImage && currentImage != nil {
                    VStack {
                        ProgressView()
                            .tint(SetuColor.brandPink)
                        Text("正在切换")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                    .stroke(SetuColor.separator, lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                if let currentImage {
                    imageMetadataOverlay(currentImage)
                }
            }
            .offset(dragOffset)
            .animation(.snappy(duration: 0.18), value: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        dragOffset = CGSize(
                            width: value.translation.width * 0.18,
                            height: value.translation.height * 0.18
                        )
                    }
                    .onEnded { value in
                        let distance = max(abs(value.translation.width), abs(value.translation.height))
                        let reason = swipeReason(for: value.translation)
                        dragOffset = .zero
                        if distance > 70 {
                            playSwipeFeedback()
                            Task { await loadNextImage(reason: reason) }
                        }
                    }
            )
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(SetuColor.brandPink)
            Text("正在获取图片")
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: SetuSpacing.lg) {
            Button {
                openOriginal()
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .frame(width: 48, height: 48)
                    .background(SetuColor.surface.opacity(0.62), in: Circle())
            }
            .disabled(currentImage?.originalURLString == nil)
            .accessibilityLabel("打开原图")

            Button {
                showingParameters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 48, height: 48)
                    .background(SetuColor.surface.opacity(0.62), in: Circle())
            }
            .accessibilityLabel("刷图参数")

            Button {
                Task { await loadNextImage(reason: "已换到下一张图片") }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .frame(width: 48, height: 48)
                    .background(SetuColor.surface.opacity(0.62), in: Circle())
            }
            .accessibilityLabel("下一张")
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(SetuColor.brandPink)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SetuSpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private func imageMetadataOverlay(_ item: SetuImageItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.author)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.86))
                }
                Spacer()
                if item.r18 == 1 {
                    SetuPill(text: "R18", tone: .danger)
                }
            }

            HStack(spacing: 10) {
                Label("PID \(item.pid)-\(item.page)", systemImage: "number")
                Label("\(item.width)x\(item.height)", systemImage: "aspectratio")
                if let firstTag = item.tags?.first {
                    Label(firstTag, systemImage: "tag")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.86))
        }
        .foregroundStyle(.white)
        .padding(SetuSpacing.md)
        .background(.ultraThinMaterial)
    }

    private var pointsText: String {
        switch pointsState {
        case .loaded(let balance):
            return "\(balance.points) 积分"
        case .failed:
            return "积分未知"
        default:
            return "积分加载中"
        }
    }

    private var canCall: Bool {
        guard case .loaded(let balance) = pointsState else {
            return false
        }
        return balance.points >= costPerCall
    }

    private var isLoadingImage: Bool {
        if case .loading = imageState {
            return true
        }
        return false
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

    private func reloadFromParameters() async {
        currentImage = nil
        await loadPoints()
        await loadNextImage(reason: "已应用参数")
    }

    private func loadNextImage(reason: String) async {
        guard !isLoadingImage else {
            return
        }
        if !canCall {
            await loadPoints()
        }
        guard canCall else {
            imageState = currentImage == nil ? .failed("积分不足，至少需要 \(costPerCall) 积分") : imageState
            message = "积分不足，至少需要 \(costPerCall) 积分"
            return
        }

        imageState = .loading
        message = nil
        do {
            let request = PointsCallRequest(
                r18: r18,
                num: 1,
                keyword: keyword,
                tags: parsedTags,
                size: size,
                excludeAI: excludeAI
            )
            let items = try await environment.pointsClient.callSetu(request: request)
            guard let item = items.first else {
                imageState = currentImage.map { .loaded($0) } ?? .failed("当前筛选条件没有匹配图片")
                message = "当前筛选条件没有匹配图片"
                await loadPoints()
                return
            }
            currentImage = item
            imageState = .loaded(item)
            message = reason
            await loadPoints()
        } catch {
            imageState = currentImage.map { .loaded($0) } ?? .failed(error.localizedDescription)
            message = error.localizedDescription
            await loadPoints()
        }
    }

    private func openOriginal() {
        guard let urlString = currentImage?.originalURLString ?? currentImage?.previewURLString,
              let url = URL(string: urlString)
        else {
            message = "图片链接无效"
            return
        }
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func swipeReason(for translation: CGSize) -> String {
        if abs(translation.width) > abs(translation.height) {
            return translation.width > 0 ? "已向右换图，继续滑动可以再刷" : "已向左换图，继续滑动可以再刷"
        }
        return translation.height > 0 ? "已向下换图，继续滑动可以再刷" : "已向上换图，继续滑动可以再刷"
    }

    private func playSwipeFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

private struct RandomImageCard: View {
    let item: SetuImageItem
    let stageSize: CGSize

    var body: some View {
        ZStack {
            SetuColor.surfaceMuted
            if let url = item.previewURLString.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(SetuColor.brandPink)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: stageSize.width, maxHeight: stageSize.height)
                    case .failure:
                        SetuEmptyState(title: "图片加载失败", systemImage: "photo")
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                SetuEmptyState(title: "没有可用图片地址", systemImage: "photo")
            }
        }
    }
}

private struct RandomImageParameterSheet: View {
    @Binding var r18: Int
    @Binding var keyword: String
    @Binding var tagText: String
    @Binding var size: String
    @Binding var excludeAI: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "筛选", subtitle: "设置下一次刷图使用的范围和标签")
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
                        }
                    }
                }
                .setuListRow()

                Section {
                    SetuCard {
                        Label(
                            "每次滑动会获取 1 张图片并消耗积分。收藏、删除申请和批量获取可以在“高级参数与批量获取”里处理。",
                            systemImage: "hand.draw"
                        )
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    }
                }
                .setuListRow()
            }
            .listStyle(.plain)
            .setuBackground()
            .navigationTitle("刷图参数")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: onApply)
                        .foregroundStyle(SetuColor.brandInk)
                }
            }
        }
    }
}
