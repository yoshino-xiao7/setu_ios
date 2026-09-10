import SetuIOSCore
import SwiftUI

struct ModuleWatchHistoryStrip: View {
    let title: String
    let records: [ModuleWatchRecord]
    var aspectRatio: CGFloat = 3 / 4
    var progressText: ((ModuleWatchRecord) -> String?)?
    let onSeeAll: () -> Void
    let onOpen: (ModuleWatchRecord) -> Void

    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                SetuSectionHeader(title: title, subtitle: "最近 \(records.count) 部", actionTitle: "全部") {
                    onSeeAll()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        ForEach(records.prefix(12)) { record in
                            Button { onOpen(record) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    SetuImageTile(
                                        urlString: record.coverUrl,
                                        accessibilityLabel: record.title,
                                        aspectRatio: aspectRatio
                                    )
                                    .frame(width: 108)
                                    Text(record.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(SetuColor.textPrimary)
                                        .lineLimit(2)
                                        .frame(width: 108, alignment: .leading)
                                    if let progress = progressText?(record), !progress.isEmpty {
                                        Text(progress)
                                            .font(.caption2)
                                            .foregroundStyle(SetuColor.brandPink)
                                            .lineLimit(1)
                                            .frame(width: 108, alignment: .leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("module.history.\(record.module.rawValue).\(record.externalId)")
                        }
                    }
                }
            }
        }
    }
}

struct ModuleWatchHistoryView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    let module: ModuleFavoriteModule
    var aspectRatio: CGFloat = 3 / 4
    @State private var records: [ModuleWatchRecord] = []

    var body: some View {
        Group {
            if records.isEmpty {
                SetuEmptyState(title: "还没有观看历史", message: "打开作品后会出现在这里，最多保留最近 100 部。", systemImage: "clock")
                    .padding(SetuSpacing.lg)
            } else {
                List {
                    ForEach(records) { record in
                        Button { open(record) } label: {
                            HStack(alignment: .top, spacing: SetuSpacing.md) {
                                SetuImageTile(
                                    urlString: record.coverUrl,
                                    accessibilityLabel: record.title,
                                    aspectRatio: aspectRatio
                                )
                                .frame(width: 72)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(SetuColor.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    if let subtitle = historySubtitle(record) {
                                        Text(subtitle)
                                            .font(SetuTypography.caption)
                                            .foregroundStyle(SetuColor.textSecondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .setuBackground()
        .navigationTitle("观看历史")
        .task { reload() }
        .onAppear { reload() }
        .accessibilityIdentifier(module == .jm ? "jm.history.page" : "asmr.history.page")
    }

    private func reload() {
        records = environment.moduleWatchHistoryStore.records(module: module)
    }

    private func historySubtitle(_ record: ModuleWatchRecord) -> String? {
        if module == .jm {
            return environment.jmReadingProgressStore.progress(albumID: record.externalId)?.pageProgressText
        }
        return nil
    }

    private func open(_ record: ModuleWatchRecord) {
        switch record.module {
        case .jm:
            router.navigate(to: .jmAlbum(record.externalId))
        case .asmr:
            router.navigate(to: .asmrWork(record.externalId))
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let record = records[index]
            environment.moduleWatchHistoryStore.remove(module: record.module, externalId: record.externalId)
        }
        reload()
    }
}
