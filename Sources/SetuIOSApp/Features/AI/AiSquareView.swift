import SetuIOSCore
import SwiftUI

struct AiSquareView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationJob>> = .idle
    @State private var category = ""

    var body: some View {
        List {
            Picker("分类", selection: $category) {
                Text("全部").tag("")
                Text("全年龄").tag("GENERAL")
                Text("R18").tag("R18")
            }
            .pickerStyle(.segmented)
            .onChange(of: category) {
                Task { await load() }
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
                            AiSquareRow(job: job)
                        }
                    }
                }
            }
        }
        .navigationTitle("AI 广场")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.square(category: category))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AiSquareRow: View {
    let job: AiGenerationJob

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
            }
        }
        .padding(.vertical, 5)
    }
}
