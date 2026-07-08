import SetuIOSCore
import SwiftUI

struct AdminImageInfoView: View {
    @Bindable var environment: AppEnvironment
    @State private var pidText: String
    @State private var pText: String
    @State private var state: LoadState<AdminImageDetail> = .idle

    init(environment: AppEnvironment, initialPID: Int? = nil, initialPage: Int = 0) {
        self.environment = environment
        _pidText = State(initialValue: initialPID.map(String.init) ?? "")
        _pText = State(initialValue: String(initialPage))
    }

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                AdminImageInfoStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查询图片详情。", systemImage: "shield.slash")
            } else {
                querySection
                contentSection
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("图片详情")
        .task {
            if Int(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                await load()
            }
        }
        .refreshable {
            await load()
        }
    }

    private var querySection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "查询")
                TextField("PID", text: $pidText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("p", text: $pText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button {
                    Task { await load() }
                } label: {
                    Label("查询图片", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
                .disabled(parsedPID == nil)
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var contentSection: some View {
        switch state {
        case .idle:
            AdminImageInfoStateSection(title: "查询结果", stateTitle: "输入 PID 查询", systemImage: "photo.badge.magnifyingglass")
        case .loading:
            AdminImageInfoStateSection(title: "查询结果", stateTitle: "正在加载图片详情", systemImage: "photo.badge.magnifyingglass", isLoading: true)
        case .failed(let message):
            AdminImageInfoStateSection(title: "查询结果", stateTitle: "图片详情加载失败", message: message, systemImage: "photo.badge.exclamationmark")
        case .loaded(let image):
            SetuCard {
                AdminImageInfoHeader(image: image)
            }
            .setuListRow()
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "基础信息")
                    AdminImageInfoMetadataRow(title: "PID", value: image.pidText)
                    AdminImageInfoMetadataRow(title: "UID", value: "\(image.uid)")
                    AdminImageInfoMetadataRow(title: "标题", value: image.title)
                    AdminImageInfoMetadataRow(title: "作者", value: image.author)
                    AdminImageInfoMetadataRow(title: "分级", value: image.ratingTitle)
                    AdminImageInfoMetadataRow(title: "AI 类型", value: image.aiTitle)
                    AdminImageInfoMetadataRow(title: "尺寸", value: "\(image.width)x\(image.height)")
                    AdminImageInfoMetadataRow(title: "扩展名", value: image.ext)
                    AdminImageInfoMetadataRow(title: "上传时间", value: "\(image.uploadDate)")
                }
            }
            .setuListRow()
            if let tags = image.tags, !tags.isEmpty {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "标签")
                        Text(tags.joined(separator: " / "))
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
                .setuListRow()
            }
            if let urlString = image.urlOriginal, let url = URL(string: urlString) {
                SetuCard {
                    Link(destination: url) {
                        Label("打开原图", systemImage: "arrow.up.forward.square")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .setuListRow()
            }
        }
    }

    private var parsedPID: Int? {
        Int(pidText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedPage: Int {
        Int(pText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin, let pid = parsedPID else { return }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.imageInfo(pid: pid, p: parsedPage))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AdminImageInfoHeader: View {
    let image: AdminImageDetail

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            AdminImageInfoThumbnail(urlString: image.urlOriginal)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(image.title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(image.author)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 8) {
                    RequestStatusBadge(title: image.ratingTitle, status: image.r18 == 1 ? 2 : 1)
                    RequestStatusBadge(title: image.aiTitle, status: image.aiType == 2 ? 0 : 1)
                }
            }
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct AdminImageInfoThumbnail: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 96, height: 120)
        .background(SetuColor.brandSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .foregroundStyle(SetuColor.brandPink)
    }
}

private struct AdminImageInfoStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
            }
        }
        .setuListRow()
    }
}

private struct AdminImageInfoMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
