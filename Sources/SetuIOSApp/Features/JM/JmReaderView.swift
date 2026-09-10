import SetuIOSCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct JmReaderView: View {
    @Bindable var environment: AppEnvironment
    let albumID: String
    let chapterID: String
    @State private var pagesState: LoadState<[JmPageImage]> = .idle
    @State private var pageIndex = 0

    var body: some View {
        Group {
            switch pagesState {
            case .idle, .loading:
                SetuEmptyState(title: "正在打开阅读器", systemImage: "book", isLoading: true)
            case .failed(let error):
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "章节加载失败", message: error.message, systemImage: "book")
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(SetuSpacing.lg)
            case .loaded(let pages):
                if pages.isEmpty {
                    SetuEmptyState(title: "这一话没有页面", systemImage: "book")
                } else {
                    TabView(selection: $pageIndex) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            JmPageImageView(page: page)
                                .tag(index)
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    #endif
                    .overlay(alignment: .bottom) {
                        Text("\(pageIndex + 1) / \(pages.count)")
                            .font(SetuTypography.caption)
                            .padding(.horizontal, SetuSpacing.md)
                            .padding(.vertical, SetuSpacing.sm)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, SetuSpacing.lg)
                    }
                }
            }
        }
        .setuBackground()
        .navigationTitle("阅读")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .accessibilityIdentifier("jm.reader.page")
    }

    private func load() async {
        pagesState = .loading
        do {
            pagesState = .loaded(try await environment.jmCatalogClient.pages(chapterID: chapterID))
        } catch {
            pagesState = .failed(UserFacingErrorMapper.map(error))
        }
    }
}

private struct JmPageImageView: View {
    let page: JmPageImage
    #if canImport(UIKit)
    @State private var image: UIImage?
    #endif
    @State private var failed = false

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            } else if failed {
                SetuEmptyState(title: "这一页加载失败", systemImage: "photo")
            } else {
                ProgressView()
            }
            #else
            if failed {
                SetuEmptyState(title: "这一页加载失败", systemImage: "photo")
            } else {
                ProgressView()
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    private func load() async {
        do {
            let request = JmAppToken.imageRequest(url: page.url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                failed = true
                return
            }
            #if canImport(UIKit)
            image = JmImageDescrambler.descrambleUIImage(data: data, page: page)
            failed = image == nil
            #else
            let restored = JmImageDescrambler.descramble(data: data, page: page)
            failed = restored.isEmpty
            #endif
        } catch {
            failed = true
        }
    }
}
