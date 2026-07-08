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
                    SetuPill(text: message, systemImage: "checkmark.circle", tone: .brand)
                }
                .setuListRow()
            }

            Section {
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
            }
            .setuListRow()

            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载 AI 绘画广场", systemImage: "photo.on.rectangle", isLoading: true)
                    }
                }
                .setuListRow()
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "AI 绘画广场加载失败", message: message, systemImage: "photo.on.rectangle")
                    }
                }
                .setuListRow()
            case .loaded(let page):
                if page.list.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(title: "暂无公开 AI 作品", systemImage: "sparkles")
                        }
                    }
                    .setuListRow()
                } else {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "共 \(page.total) 个作品")
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SetuSpacing.md) {
                                    ForEach(page.list) { job in
                                        AiGenerationGridTile(job: job, footerTitle: job.createdAt) {
                                            previewSelection = AiSquarePreviewSelection(job: job)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .setuListRow()
                    pagerSection(page)
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("AI 绘画广场")
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
            HStack(spacing: SetuSpacing.md) {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)
                .buttonStyle(.bordered)

                Spacer()
                Text("第 \(result.page) 页")
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(result.page * result.pageSize >= result.total)
                .buttonStyle(.bordered)
            }
        }
        .setuListRow()
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
