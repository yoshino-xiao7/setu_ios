import SetuIOSCore
import SwiftUI

#if os(iOS)
import Photos
import UIKit
#endif

struct UserImagePreviewItem: Identifiable {
    let id: String
    let pid: Int
    let page: Int
    let title: String
    let author: String
    let width: Int?
    let height: Int?
    let r18: Bool
    let tags: [String]
    let displayURLString: String?
    let originalURLString: String?

    init(favorite: FavoriteItem) {
        let image = favorite.image
        id = "favorite-\(favorite.id)"
        pid = favorite.pid
        page = favorite.p
        title = image?.title.nonEmpty ?? "未命名作品"
        author = image?.author.nonEmpty ?? "未知作者"
        width = image?.width
        height = image?.height
        r18 = image?.r18 == 1
        tags = image?.tags ?? []
        displayURLString = image?.urlRegular ?? image?.urlSmall ?? image?.urlOriginal
        originalURLString = image?.urlOriginal ?? image?.urlRegular ?? image?.urlSmall
    }

    init(collectionItem: CollectionItem) {
        let image = collectionItem.image
        id = "collection-\(collectionItem.id)"
        pid = collectionItem.pid
        page = collectionItem.p
        title = image?.title.nonEmpty ?? "未命名作品"
        author = image?.author.nonEmpty ?? "未知作者"
        width = image?.width
        height = image?.height
        r18 = image?.r18 == 1
        tags = image?.tags ?? []
        displayURLString = image?.urlRegular ?? image?.urlSmall ?? image?.urlOriginal
        originalURLString = image?.urlOriginal ?? image?.urlRegular ?? image?.urlSmall
    }

    init(image: SetuImageItem) {
        id = "setu-\(image.id)"
        pid = image.pid
        page = image.page
        title = image.title.nonEmpty ?? "未命名作品"
        author = image.author.nonEmpty ?? "未知作者"
        width = image.width
        height = image.height
        r18 = image.r18 == 1
        tags = image.tags ?? []
        displayURLString = image.previewURLString
        originalURLString = image.originalURLString ?? image.previewURLString
    }

    init(
        id: String,
        title: String,
        author: String,
        width: Int?,
        height: Int?,
        r18: Bool,
        tags: [String] = [],
        displayURLString: String?,
        originalURLString: String?
    ) {
        self.id = id
        pid = 0
        page = 0
        self.title = title
        self.author = author
        self.width = width
        self.height = height
        self.r18 = r18
        self.tags = tags
        self.displayURLString = displayURLString
        self.originalURLString = originalURLString
    }

    var bestURL: URL? {
        (originalURLString ?? displayURLString).flatMap(URL.init(string:))
    }
}

#if os(iOS)
struct UserImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let item: UserImagePreviewItem

    @State private var exportState: ImageExportState = .idle
    @State private var sharePayload: ImageSharePayload?
    @State private var photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    imageStage
                    metadata
                    exportActions
                }
                .padding(SetuSpacing.lg)
            }
            .setuBackground()
            .navigationTitle("图片预览")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("image.preview.close")
                }
            }
            .sheet(item: $sharePayload) { payload in
                SystemActivitySheet(items: [payload.image]) { result in
                    switch result {
                    case .completed:
                        exportState = .message("已分享图片", .success)
                    case .cancelled:
                        exportState = .message("已取消分享", .muted)
                    case .failed(let message):
                        exportState = .message(message.message, .danger)
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshPhotoAuthorizationStatus()
                }
            }
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        if let url = item.bestURL {
            SetuRemoteImage(
                urlString: url.absoluteString,
                accessibilityLabel: "\(item.title)，作者 \(item.author)",
                width: nil,
                height: nil,
                cornerRadius: SetuRadius.md,
                contentMode: .fit
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            SetuCard {
                SetuEmptyState(title: "图片暂不可用", systemImage: "photo")
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private var metadata: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                Text(item.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("image.preview.title")
                Text(item.author)
                    .font(.subheadline)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: SetuSpacing.sm) {
                    if let width = item.width, let height = item.height, width > 0, height > 0 {
                        SetuPill(text: "\(width) × \(height)", systemImage: "aspectratio", tone: .muted)
                    }
                    if item.r18 {
                        SetuPill(text: "成人内容", systemImage: "eye.slash", tone: .danger)
                    }
                }
                if !item.tags.isEmpty {
                    TagFlow(tags: item.tags)
                }
            }
        }
    }

    private var exportActions: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "保存与分享", subtitle: "保存时才会请求照片权限")

                SetuPermissionPrompt(
                    title: "照片权限",
                    message: photoPermissionMessage,
                    systemImage: "photo.badge.arrow.down",
                    state: photoPermissionState,
                    actionTitle: photoPermissionState == .denied ? "前往系统设置" : nil,
                    action: photoPermissionState == .denied ? openPhotoSettings : nil
                )

                Button {
                    Task { await saveToPhotos() }
                } label: {
                    Label("保存到照片", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.gradientTop)
                .disabled(exportState.isLoading || item.bestURL == nil || photoPermissionState == .denied)

                Button {
                    Task { await prepareShare() }
                } label: {
                    Label("使用系统分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(exportState.isLoading || item.bestURL == nil)

                switch exportState {
                case .idle:
                    EmptyView()
                case .loading(let title):
                    ProgressView(title)
                case .message(let text, let tone):
                    SetuPill(text: text, systemImage: tone.systemImage, tone: tone)
                }
            }
        }
    }

    private func saveToPhotos() async {
        guard let url = item.bestURL else { return }
        exportState = .loading("正在保存图片")
        defer { refreshPhotoAuthorizationStatus() }
        do {
            let image = try await ImageExportService.loadImage(from: url)
            try await ImageExportService.saveToPhotos(image)
            exportState = .message("已保存到照片", .success)
        } catch {
            exportState = .message(ImageExportService.userMessage(for: error), .danger)
        }
    }

    private var photoPermissionState: SetuPermissionState {
        switch photoAuthorizationStatus {
        case .authorized, .limited: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private var photoPermissionMessage: String {
        switch photoPermissionState {
        case .notDetermined:
            "只有在你主动保存图片时才会询问，雪涼云不会读取你的相册。"
        case .granted:
            "已允许添加图片；雪涼云只会保存你主动选择的作品。"
        case .denied:
            "照片权限已关闭，可前往系统设置后再保存。"
        }
    }

    private func refreshPhotoAuthorizationStatus() {
        photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    private func openPhotoSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func prepareShare() async {
        guard let url = item.bestURL else { return }
        exportState = .loading("正在准备分享")
        do {
            let image = try await ImageExportService.loadImage(from: url)
            sharePayload = ImageSharePayload(image: image)
            exportState = .idle
        } catch {
            exportState = .message(ImageExportService.userMessage(for: error), .danger)
        }
    }
}

private enum ImageExportState {
    case idle
    case loading(String)
    case message(String, SetuPillTone)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

private extension SetuPillTone {
    var systemImage: String {
        switch self {
        case .success: "checkmark.circle"
        case .danger: "exclamationmark.triangle"
        case .warning: "exclamationmark.circle"
        case .info: "info.circle"
        case .brand: "sparkles"
        case .muted: "xmark.circle"
        }
    }
}

private struct ImageSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum ActivityResult {
    case completed
    case cancelled
    case failed(UserFacingError)
}

private struct SystemActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (ActivityResult) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            if let error {
                onComplete(.failed(UserFacingErrorMapper.map(error)))
            } else {
                onComplete(completed ? .completed : .cancelled)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum ImageExportService {
    static func loadImage(from url: URL) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let image = UIImage(data: data) else {
            throw ImageExportError.invalidImage
        }
        return image
    }

    static func saveToPhotos(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ImageExportError.photoPermissionDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    static func userMessage(for error: Error) -> String {
        if let exportError = error as? ImageExportError {
            return exportError.errorDescription ?? "图片操作失败，请重试"
        }
        return "图片操作失败，请检查网络后重试"
    }
}

private enum ImageExportError: LocalizedError {
    case invalidImage
    case photoPermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "图片下载失败，请稍后重试"
        case .photoPermissionDenied:
            "未能保存，请在系统设置中允许雪涼云添加照片"
        }
    }
}
#else
struct UserImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: UserImagePreviewItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    if let url = item.bestURL {
                        SetuRemoteImage(
                            urlString: url.absoluteString,
                            accessibilityLabel: "\(item.title)，作者 \(item.author)",
                            width: nil,
                            height: nil,
                            cornerRadius: SetuRadius.md,
                            contentMode: .fit
                        )
                    }
                    Text(item.title)
                        .font(SetuTypography.headline)
                    Text(item.author)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                .padding(SetuSpacing.lg)
            }
            .setuBackground()
            .navigationTitle("图片预览")
            .toolbar {
                Button("关闭") { dismiss() }
            }
        }
    }
}
#endif

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
