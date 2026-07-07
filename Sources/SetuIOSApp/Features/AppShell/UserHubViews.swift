import SetuIOSCore
import SwiftUI

struct AiHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "AI 绘画",
                    subtitle: "输入提示词、选择尺寸和模型，直接创建新的绘图任务。",
                    systemImage: "paintbrush.pointed",
                    tint: .purple
                ) {
                    router.navigate(to: .aiDraw)
                }
            }

            Section("我的创作") {
                HubNavigationRow(title: "AI 绘画历史", subtitle: "查看任务状态、结果图和复用参数", systemImage: "clock.arrow.circlepath") {
                    router.navigate(to: .aiHistory)
                }
                HubNavigationRow(title: "我的删除记录", subtitle: "查看已提交的 AI 作品删除申请", systemImage: "xmark.bin") {
                    router.navigate(to: .aiDeleteRequests)
                }
            }

            Section("公开内容") {
                HubNavigationRow(title: "AI 绘图广场", subtitle: "浏览公开的 AI 作品", systemImage: "sparkles.rectangle.stack") {
                    router.navigate(to: .aiSquare)
                }
            }
        }
        .navigationTitle("AI")
    }
}

struct ImageHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "随机图片",
                    subtitle: "使用积分调用图片接口，上下或左右滑动获取新图片。",
                    systemImage: "photo.on.rectangle.angled",
                    tint: .pink
                ) {
                    router.navigate(to: .imageSwipe)
                }
            }

            Section("图片工具") {
                HubNavigationRow(title: "积分调用", subtitle: "配置 R18、尺寸、关键词、标签等参数", systemImage: "bolt.circle") {
                    router.navigate(to: .points)
                }
                HubNavigationRow(title: "积分流水", subtitle: "查看积分消耗和接口调用记录", systemImage: "list.bullet.rectangle") {
                    router.navigate(to: .pointsLogs)
                }
                HubNavigationRow(title: "图库投稿", subtitle: "上传图片并查看投稿批次", systemImage: "square.and.arrow.up") {
                    router.navigate(to: .galleryUploads)
                }
                HubNavigationRow(title: "我的删除申请", subtitle: "查看图片删除申请状态", systemImage: "trash") {
                    router.navigate(to: .imageDeleteRequests)
                }
            }
        }
        .navigationTitle("图片")
    }
}

struct SquareHubView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment

    var body: some View {
        List {
            Section {
                HubHeroRow(
                    title: "广场",
                    subtitle: "集中浏览用户公开内容，后续会把图片预览做成更沉浸的瀑布流。",
                    systemImage: "rectangle.stack.fill",
                    tint: .blue
                ) {
                    router.navigate(to: .collectionSquare)
                }
            }

            Section("内容广场") {
                HubNavigationRow(title: "收藏夹广场", subtitle: "查看公开收藏夹和图片集合", systemImage: "rectangle.stack") {
                    router.navigate(to: .collectionSquare)
                }
                HubNavigationRow(title: "AI 绘图广场", subtitle: "查看公开 AI 生成作品", systemImage: "sparkles") {
                    router.navigate(to: .aiSquare)
                }
            }

            Section("我的内容") {
                HubNavigationRow(title: "我的收藏夹", subtitle: "管理自己的图片收藏", systemImage: "heart.rectangle") {
                    router.navigate(to: .collections)
                }
                HubNavigationRow(title: "我的收藏", subtitle: "查看默认收藏图片", systemImage: "heart.fill") {
                    router.navigate(to: .favorites)
                }
            }
        }
        .navigationTitle("广场")
    }
}

private struct HubHeroRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

private struct HubNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.pink)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}
