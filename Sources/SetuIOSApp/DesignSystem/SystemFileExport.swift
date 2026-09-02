import SwiftUI

#if os(iOS)
import UIKit
#endif

struct SystemFileSharePayload: Identifiable {
    let id = UUID()
    let fileURL: URL
}

enum SystemFileShareResult {
    case completed
    case cancelled
    case failed(UserFacingError)
}

#if os(iOS)
struct SystemFileShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: (SystemFileShareResult) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
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
#else
struct SystemFileShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fileURL: URL
    let onComplete: (SystemFileShareResult) -> Void

    var body: some View {
        VStack(spacing: SetuSpacing.lg) {
            ShareLink(item: fileURL) {
                Label("使用系统分享", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)

            Button("关闭") {
                onComplete(.cancelled)
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(SetuSpacing.xl)
    }
}
#endif

enum RemoteFileExportService {
    static func download(from url: URL, filename: String) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RemoteFileExportError.downloadFailed
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetuExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(sanitizedFilename(filename))
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func userMessage(for error: Error) -> String {
        if let exportError = error as? RemoteFileExportError {
            return exportError.errorDescription ?? "文件下载失败，请重试"
        }
        return "文件下载失败，请检查网络后重试"
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let components = filename.components(separatedBy: invalid)
        let value = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "雪涼云下载" : value
    }
}

private enum RemoteFileExportError: LocalizedError {
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            "文件下载失败，请稍后重试"
        }
    }
}
