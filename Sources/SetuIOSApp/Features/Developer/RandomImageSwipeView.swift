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
            groupedBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 12) {
                statusStrip
                if let message {
                    messageStrip(message)
                }
                imageStage
                actionBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
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
                        Label("详细参数调用", systemImage: "bolt.circle")
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
        HStack(spacing: 10) {
            Label(pointsText, systemImage: "bolt.circle")
            Divider()
                .frame(height: 18)
            Label("单次 \(costPerCall)", systemImage: "tag")
            Spacer()
            if isLoadingImage {
                ProgressView()
            } else {
                Label("滑动换图", systemImage: "hand.draw")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func messageStrip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: text.contains("失败") || text.contains("不足") ? "exclamationmark.triangle" : "hand.draw")
            Text(text)
                .lineLimit(2)
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var imageStage: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(secondaryGroupedBackgroundColor)

                switch imageState {
                case .idle where currentImage == nil:
                    loadingPlaceholder
                case .loading where currentImage == nil:
                    loadingPlaceholder
                case .failed(let text) where currentImage == nil:
                    ContentUnavailableView("图片加载失败", systemImage: "photo.on.rectangle", description: Text(text))
                default:
                    if let currentImage {
                        RandomImageCard(item: currentImage, stageSize: proxy.size)
                    } else {
                        ContentUnavailableView("暂无图片", systemImage: "photo.on.rectangle")
                    }
                }

                if isLoadingImage && currentImage != nil {
                    VStack {
                        ProgressView()
                        Text("正在切换")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
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
                        dragOffset = .zero
                        if distance > 70 {
                            Task { await loadNextImage(reason: "已切换下一张，继续滑动可以再换") }
                        }
                    }
            )
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在获取图片")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                openOriginal()
            } label: {
                Label("原图", systemImage: "arrow.up.forward.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(currentImage?.originalURLString == nil)

            Button {
                showingParameters = true
            } label: {
                Label("参数", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
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
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.r18 == 1 {
                    Text("R18")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.16), in: Capsule())
                        .foregroundStyle(.red)
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
            .foregroundStyle(.secondary)
        }
        .padding(14)
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
}

private struct RandomImageCard: View {
    let item: SetuImageItem
    let stageSize: CGSize

    var body: some View {
        ZStack {
            Color.black.opacity(0.04)
            if let url = item.previewURLString.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: stageSize.width, maxHeight: stageSize.height)
                    case .failure:
                        ContentUnavailableView("图片加载失败", systemImage: "photo")
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                ContentUnavailableView("没有可用图片地址", systemImage: "photo")
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
            Form {
                Section("筛选") {
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
                    TextField("标签，逗号分隔", text: $tagText)
                    Toggle("排除 AI 图片", isOn: $excludeAI)
                }

                Section {
                    Text("每次滑动会获取 1 张图片并消耗积分。收藏、删除申请和批量获取仍在“详细参数调用”里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("刷图参数")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: onApply)
                }
            }
        }
    }
}

private var groupedBackgroundColor: Color {
    #if os(iOS)
    Color(uiColor: .systemGroupedBackground)
    #elseif os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color.gray.opacity(0.08)
    #endif
}

private var secondaryGroupedBackgroundColor: Color {
    #if os(iOS)
    Color(uiColor: .secondarySystemGroupedBackground)
    #elseif os(macOS)
    Color(nsColor: .controlBackgroundColor)
    #else
    Color.gray.opacity(0.12)
    #endif
}
