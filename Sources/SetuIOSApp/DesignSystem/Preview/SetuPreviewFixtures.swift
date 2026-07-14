import SetuIOSCore

#if DEBUG

/// Stable, network-free values used by Design System and feature previews.
///
/// Keep these fixtures deterministic so visual comparisons are not affected by
/// the current date, locale, account, or backend data.
enum SetuPreviewFixtures {
    struct ContentItem: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
        let metadata: String
        let systemImage: String
    }

    enum ContentScenario: String, CaseIterable, Identifiable {
        case loading
        case empty
        case failed
        case loaded

        var id: String { rawValue }

        var title: String {
            switch self {
            case .loading: "加载中"
            case .empty: "空内容"
            case .failed: "加载失败"
            case .loaded: "已有内容"
            }
        }

        var state: LoadState<[ContentItem]> {
            switch self {
            case .loading:
                .loading
            case .empty:
                .loaded([])
            case .failed:
                .failed(SetuPreviewFixtures.recoverableError)
            case .loaded:
                .loaded(SetuPreviewFixtures.contentItems)
            }
        }
    }

    struct FeedbackSample: Identifiable, Hashable {
        let id: String
        let title: String
        let feedback: SetuFeedback
    }

    struct LoadMoreSample: Identifiable, Equatable {
        let id: String
        let title: String
        let state: SetuLoadMoreFooterState
    }

    static let longChinese =
        "第一次使用也能看懂的内容状态：这里会完整说明发生了什么、接下来可以做什么，并在辅助功能大字号下自然换行。"

    static let longMixedLanguage =
        "A quiet summer playlist — 12 tracks / 48 min · v2.4.1；同步于 2026-07-10 18:30，完成度 99.9%。"

    static let recoverableError =
        "暂时无法连接到服务。请检查网络后重试，已经加载的内容会继续保留。"

    static let contentItems: [ContentItem] = [
        ContentItem(
            id: "preview-content-001",
            title: "夏夜微风与粉色云层",
            detail: longChinese,
            metadata: "收藏于 2026-07-10 · 4 张图片",
            systemImage: "photo.on.rectangle.angled"
        ),
        ContentItem(
            id: "preview-content-002",
            title: "Focus Mix / 深度工作 #42",
            detail: longMixedLanguage,
            metadata: "12 tracks · 48 min · Lossless",
            systemImage: "music.note.list"
        ),
    ]

    static let feedbackSamples: [FeedbackSample] = [
        FeedbackSample(
            id: "success",
            title: "成功",
            feedback: .success("已保存到收藏，稍后可以在“我的收藏”中继续查看。")
        ),
        FeedbackSample(
            id: "error",
            title: "错误",
            feedback: .error(recoverableError)
        ),
        FeedbackSample(
            id: "info",
            title: "信息",
            feedback: .info("作品提交后通常会在 1–3 分钟内完成审核，无需停留在当前页面。")
        ),
        FeedbackSample(
            id: "warning",
            title: "提醒",
            feedback: .warning("本次生成预计消耗 6 积分，开始后将无法撤销。")
        ),
    ]

    static let loadMoreSamples: [LoadMoreSample] = [
        LoadMoreSample(id: "idle", title: "等待触发", state: .idle),
        LoadMoreSample(id: "loading", title: "正在加载", state: .loading),
        LoadMoreSample(id: "failed", title: "可以恢复", state: .failed("后续内容加载失败")),
        LoadMoreSample(id: "complete", title: "全部完成", state: .complete("已经看到全部内容")),
    ]
}
#endif
