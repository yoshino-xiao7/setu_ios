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
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查询图片详情。"))
            } else {
                querySection
                contentSection
            }
        }
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
        Section("查询") {
            TextField("PID", text: $pidText)
            TextField("p", text: $pText)
            Button {
                Task { await load() }
            } label: {
                Label("查询图片", systemImage: "magnifyingglass")
            }
            .disabled(parsedPID == nil)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch state {
        case .idle:
            ContentUnavailableView("输入 PID 查询", systemImage: "photo.badge.magnifyingglass")
        case .loading:
            ProgressView("正在加载图片详情")
        case .failed(let message):
            ContentUnavailableView("图片详情加载失败", systemImage: "photo.badge.exclamationmark", description: Text(message))
        case .loaded(let image):
            Section {
                AdminImageInfoHeader(image: image)
            }
            Section("基础信息") {
                LabeledContent("PID", value: image.pidText)
                LabeledContent("UID", value: "\(image.uid)")
                LabeledContent("标题", value: image.title)
                LabeledContent("作者", value: image.author)
                LabeledContent("分级", value: image.ratingTitle)
                LabeledContent("AI 类型", value: image.aiTitle)
                LabeledContent("尺寸", value: "\(image.width)x\(image.height)")
                LabeledContent("扩展名", value: image.ext)
                LabeledContent("上传时间", value: "\(image.uploadDate)")
            }
            if let tags = image.tags, !tags.isEmpty {
                Section("标签") {
                    Text(tags.joined(separator: " / "))
                        .font(.footnote)
                }
            }
            if let urlString = image.urlOriginal, let url = URL(string: urlString) {
                Section {
                    Link(destination: url) {
                        Label("打开原图", systemImage: "arrow.up.forward.square")
                    }
                }
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
        HStack(alignment: .top, spacing: 14) {
            AdminImageInfoThumbnail(urlString: image.urlOriginal)
            VStack(alignment: .leading, spacing: 6) {
                Text(image.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(image.author)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    RequestStatusBadge(title: image.ratingTitle, status: image.r18 == 1 ? 2 : 1)
                    RequestStatusBadge(title: image.aiTitle, status: image.aiType == 2 ? 0 : 1)
                }
            }
        }
        .padding(.vertical, 4)
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
        .background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .foregroundStyle(.pink)
    }
}
