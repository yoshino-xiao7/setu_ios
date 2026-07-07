import SetuIOSCore
import SwiftUI

struct AiSquareView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationJob>> = .idle
    @State private var category = "GENERAL"
    @State private var page = 1
    @State private var previewSelection: AiSquarePreviewSelection?
    @State private var message: String?
    private let pageSize = 16

    var body: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("分类", selection: $category) {
                Text("全部").tag("")
                Text("全年龄").tag("GENERAL")
                Text("R18").tag("R18")
            }
            .pickerStyle(.segmented)
            .onChange(of: category) {
                Task {
                    page = 1
                    await load()
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("AI 广场加载失败", systemImage: "photo.on.rectangle", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无公开 AI 作品", systemImage: "sparkles")
                } else {
                    Section("共 \(page.total) 个作品") {
                        ForEach(page.list) { job in
                            AiSquareRow(job: job) {
                                previewSelection = AiSquarePreviewSelection(job: job)
                            }
                        }
                    }
                    pagerSection(page)
                }
            }
        }
        .navigationTitle("AI 广场")
        .sheet(item: $previewSelection) { selection in
            AiGenerationImagePreviewSheet(
                environment: environment,
                job: selection.job,
                onOpenDetail: {
                    previewSelection = nil
                    router.navigate(to: .aiGenerationDetail(selection.job.id))
                },
                onMessage: { message = $0 }
            )
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func pagerSection(_ result: PageResult<AiGenerationJob>) -> some View {
        Section {
            HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(result.page * result.pageSize >= result.total)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.square(category: category, page: page, pageSize: pageSize))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AiSquarePreviewSelection: Identifiable {
    let job: AiGenerationJob

    var id: Int { job.id }
}

private struct AiSquareRow: View {
    let job: AiGenerationJob
    let onPreview: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ImageThumbnailView(urlString: job.imageUrl)
            VStack(alignment: .leading, spacing: 7) {
                Text(job.promptCn)
                    .font(.headline)
                    .lineLimit(2)
                if let styleNotes = job.styleNotes, !styleNotes.isEmpty {
                    Text(styleNotes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label(job.publicCategory ?? "公开", systemImage: "globe")
                    Label("\(job.width)x\(job.height)", systemImage: "aspectratio")
                    if let createdAt = job.createdAt {
                        Label(createdAt, systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if job.imageUrl != nil {
                    Button {
                        onPreview()
                    } label: {
                        Label("查看原图", systemImage: "eye")
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                }
            }
        }
        .padding(.vertical, 5)
    }
}
