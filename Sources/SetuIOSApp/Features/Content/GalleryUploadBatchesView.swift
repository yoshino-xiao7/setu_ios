import SetuIOSCore
import SwiftUI

struct GalleryUploadBatchesView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<GalleryUploadBatchSummary>> = .idle
    @State private var statusFilter = "ALL"

    var body: some View {
        List {
            Picker("状态", selection: $statusFilter) {
                Text("全部").tag("ALL")
                Text("上传中").tag("UPLOADING")
                Text("待审核").tag("WAITING_MANUAL_REVIEW")
                Text("已发布").tag("PUBLISHED")
                Text("已拒绝").tag("REJECTED")
            }
            .pickerStyle(.segmented)
            .onChange(of: statusFilter) {
                Task { await load() }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("投稿批次加载失败", systemImage: "tray.full", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无投稿批次", systemImage: "tray")
                } else {
                    Section("共 \(page.total) 个批次") {
                        ForEach(page.list) { batch in
                            Button {
                                router.navigate(to: .galleryUploadDetail(batch.batchId))
                            } label: {
                                GalleryUploadBatchRow(batch: batch)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("图库投稿")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.galleryUploadClient.listMine(status: statusFilter))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct GalleryUploadBatchRow: View {
    let batch: GalleryUploadBatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.title ?? "投稿批次 #\(batch.batchId)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(batch.author ?? "未知作者")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(batch.statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 12) {
                Label("\(batch.itemCount)", systemImage: "photo")
                Label("\(batch.uploadedCount) 已传", systemImage: "icloud.and.arrow.up")
                Label("\(batch.publishedCount) 已发布", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(batch.createdAt)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
