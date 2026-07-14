import SetuIOSCore
import SwiftUI

#if DEBUG

/// A compact visual audit surface for the most reused product-facing components.
///
/// It intentionally uses long, mixed-language copy and every common async state
/// so regressions are visible without connecting to a backend.
struct SetuDesignSystemPreviewGallery: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SetuSpacing.xxl) {
                galleryHeader
                feedbackSection
                contentStateSection
                loadMoreSection
                cardAndButtonSection
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.xl)
        }
        .background(SetuColor.pageGradient.ignoresSafeArea())
    }

    private var galleryHeader: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            SetuPill(text: "Preview Gallery", systemImage: "paintpalette.fill", tone: .brand)

            Text("设计系统质量检查")
                .font(SetuTypography.display)
                .foregroundStyle(SetuColor.textPrimary)

            Text(SetuPreviewFixtures.longMixedLanguage)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var feedbackSection: some View {
        previewSection(
            title: "类型化反馈",
            subtitle: "Success / Error / Info / Warning"
        ) {
            ForEach(SetuPreviewFixtures.feedbackSamples) { sample in
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    previewLabel(sample.title)
                    SetuFeedbackBanner(feedback: sample.feedback)
                }
            }
        }
    }

    private var contentStateSection: some View {
        previewSection(
            title: "内容状态",
            subtitle: "Loading / Empty / Failed / Loaded"
        ) {
            ForEach(SetuPreviewFixtures.ContentScenario.allCases) { scenario in
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    previewLabel(scenario.title)
                    SetuCard(padding: 0) {
                        content(for: scenario.state)
                    }
                }
            }
        }
    }

    private var loadMoreSection: some View {
        previewSection(
            title: "增量加载",
            subtitle: "保留已有内容，并提供清晰的恢复动作"
        ) {
            ForEach(SetuPreviewFixtures.loadMoreSamples) { sample in
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    previewLabel(sample.title)

                    SetuCard(padding: SetuSpacing.md) {
                        if case .idle = sample.state {
                            Text("滚动到内容末尾后开始加载")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }

                        SetuLoadMoreFooter(state: sample.state, retry: {})
                    }
                }
            }
        }
    }

    private var cardAndButtonSection: some View {
        previewSection(
            title: "按钮与卡片",
            subtitle: "长文本、主次操作与卡片层级"
        ) {
            SetuHeroCard(
                title: "继续上次创作",
                subtitle: SetuPreviewFixtures.longChinese,
                systemImage: "wand.and.stars",
                action: {}
            )

            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.title2)
                            .foregroundStyle(SetuColor.brandPink)
                            .frame(minWidth: 44, minHeight: 44)

                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                            Text(SetuPreviewFixtures.contentItems[0].title)
                                .font(SetuTypography.headline)
                                .foregroundStyle(SetuColor.textPrimary)
                            Text(SetuPreviewFixtures.longMixedLanguage)
                                .font(SetuTypography.body)
                                .foregroundStyle(SetuColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: SetuSpacing.md) {
                            secondaryButton
                            primaryButton
                        }

                        VStack(spacing: SetuSpacing.sm) {
                            primaryButton
                            secondaryButton
                        }
                    }
                }
            }

            SetuCard {
                SetuNavigationRow(
                    title: "管理我的作品与收藏",
                    subtitle: SetuPreviewFixtures.longChinese,
                    systemImage: "rectangle.stack.fill",
                    action: {}
                )
            }
        }
    }

    @ViewBuilder
    private func content(for state: LoadState<[SetuPreviewFixtures.ContentItem]>) -> some View {
        switch state {
        case .idle, .loading:
            SetuEmptyState(
                title: "正在准备内容",
                message: "请稍候，已加载的内容不会消失。",
                systemImage: "arrow.triangle.2.circlepath",
                isLoading: true
            )
        case .loaded(let items) where items.isEmpty:
            SetuEmptyState(
                title: "还没有收藏",
                message: "浏览广场并收藏喜欢的作品，它们会出现在这里。",
                systemImage: "heart",
                actionTitle: "去逛广场",
                action: {}
            )
        case .failed(let message):
            SetuEmptyState(
                title: "内容暂时没有加载出来",
                message: message,
                systemImage: "wifi.exclamationmark",
                actionTitle: "重新加载",
                action: {}
            )
        case .loaded(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        Image(systemName: item.systemImage)
                            .font(.title3)
                            .foregroundStyle(SetuColor.brandPink)
                            .frame(minWidth: 44, minHeight: 44)

                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                            Text(item.title)
                                .font(SetuTypography.headline)
                                .foregroundStyle(SetuColor.textPrimary)
                            Text(item.detail)
                                .font(SetuTypography.body)
                                .foregroundStyle(SetuColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.metadata)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                    .padding(SetuSpacing.lg)
                    .accessibilityElement(children: .combine)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(SetuColor.separator)
                    }
                }
            }
        }
    }

    private var primaryButton: some View {
        SetuPrimaryButton(action: {}) {
            Label("保存并继续", systemImage: "arrow.right.circle.fill")
        }
    }

    private var secondaryButton: some View {
        Button("稍后处理") {}
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func previewLabel(_ text: String) -> some View {
        Text(text)
            .font(SetuTypography.caption.weight(.semibold))
            .foregroundStyle(SetuColor.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func previewSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.lg) {
            SetuSectionHeader(title: title, subtitle: subtitle)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

#Preview("375 · Light · Default") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 375, height: 812)
        .preferredColorScheme(.light)
}

#Preview("375 · Dark · AX5") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 375, height: 812)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("390 · Light · Default") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 390, height: 844)
        .preferredColorScheme(.light)
}

#Preview("390 · Dark · XXL") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 390, height: 844)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .xxLarge)
}

#Preview("390 · Light · Increase Contrast") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 390, height: 844)
        .preferredColorScheme(.light)
        // SwiftUI exposes the public contrast value as read-only. Its preview/test
        // override is the writable underscored environment value.
        .environment(\._colorSchemeContrast, .increased)
}

#Preview("430 · Light · AX5") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 430, height: 932)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("430 · Dark · Default") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 430, height: 932)
        .preferredColorScheme(.dark)
}

#Preview("430 · Dark · Reduce Motion") {
    SetuDesignSystemPreviewGallery()
        .frame(width: 430, height: 932)
        .preferredColorScheme(.dark)
        // See the contrast preview above; this is SwiftUI's writable override.
        .environment(\._accessibilityReduceMotion, true)
}
#endif
