import SetuIOSCore
import SwiftUI
import UIKit

struct NeteaseLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment

    enum LoginMode: String, CaseIterable, Identifiable {
        case captcha = "验证码登录"
        case qrcode = "扫码登录"
        case cookie = "Cookie 导入"

        var id: String { rawValue }
    }

    @State private var mode: LoginMode = .captcha
    @State private var feedback: SetuFeedback?

    // SMS Captcha State
    @State private var phone: String = ""
    @State private var captcha: String = ""
    @State private var countdown: Int = 0
    @State private var isSendingCaptcha = false
    @State private var isSubmittingCaptcha = false
    @State private var timerTask: Task<Void, Never>?

    // QR Code State
    @State private var qrImage: UIImage?
    @State private var qrKey: String?
    @State private var isQrExpired = false
    @State private var isQrLoading = false
    @State private var qrStatusText: String = "正在生成登录二维码..."
    @State private var pollingTask: Task<Void, Never>?

    // Cookie State
    @State private var cookieText: String = ""
    @State private var isVerifyingCookie = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("登录方式", selection: $mode) {
                        ForEach(LoginMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: SetuSpacing.sm, leading: SetuSpacing.md, bottom: SetuSpacing.sm, trailing: SetuSpacing.md))
                    .listRowBackground(Color.clear)
                }

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                switch mode {
                case .captcha:
                    captchaSection
                case .qrcode:
                    qrSection
                case .cookie:
                    cookieSection
                }

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                            Text("为什么要登录网易云账号？")
                                .font(SetuTypography.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(SetuColor.textPrimary)
                            Text("1. 完整播放 VIP 专属歌曲与 Hi-Res / 无损无缝高码率音质\n2. 自动同步网易云音乐个人创建及收藏的所有歌单\n3. 支持在亦可中直接将歌曲一键收藏回网易云歌单")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: SetuSpacing.sm, leading: SetuSpacing.md, bottom: SetuSpacing.md, trailing: SetuSpacing.md))
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle("网易云账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        stopQrPolling()
                        timerTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                stopQrPolling()
                timerTask?.cancel()
            }
            .onChange(of: mode) { _, newMode in
                feedback = nil
                if newMode == .qrcode {
                    Task { await loadQrCode() }
                } else {
                    stopQrPolling()
                }
            }
        }
    }

    // MARK: - SMS Captcha View

    private var captchaSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "手机短信验证码", subtitle: "无需切屏，输入验证码极速登录")

                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text("手机号")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                        HStack(spacing: SetuSpacing.sm) {
                            TextField("请输入 11 位手机号", text: $phone)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                Task { await sendSmsCode() }
                            } label: {
                                if isSendingCaptcha {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                        .font(SetuTypography.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SetuColor.brandPink)
                            .disabled(countdown > 0 || isSendingCaptcha || phone.trimmingCharacters(in: .whitespaces).count != 11)
                        }
                    }

                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text("验证码")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                        TextField("请输入收到的验证码", text: $captcha)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        Task { await loginWithSms() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmittingCaptcha {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("登录网易云")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, SetuSpacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SetuColor.brandPink)
                    .disabled(isSubmittingCaptcha || phone.trimmingCharacters(in: .whitespaces).count != 11 || captcha.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
        .listRowBackground(Color.clear)
    }

    // MARK: - QR Code View

    private var qrSection: some View {
        Section {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "网易云音乐扫码", subtitle: "支持多设备扫描或一键存图唤起")

                    ZStack {
                        RoundedRectangle(cornerRadius: SetuRadius.md)
                            .fill(Color.white)
                            .frame(width: 220, height: 220)
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)

                        if isQrLoading {
                            ProgressView("生成二维码中...")
                                .foregroundStyle(Color.black)
                        } else if let qrImage {
                            Image(uiImage: qrImage)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .blur(radius: isQrExpired ? 4 : 0)

                            if isQrExpired {
                                Color.black.opacity(0.65)
                                    .frame(width: 200, height: 200)
                                    .cornerRadius(SetuRadius.sm)

                                VStack(spacing: SetuSpacing.xs) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                    Text("二维码已过期\n点击刷新")
                                        .font(SetuTypography.caption)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                }
                                .onTapGesture {
                                    Task { await loadQrCode() }
                                }
                            }
                        } else {
                            VStack(spacing: SetuSpacing.xs) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title)
                                    .foregroundStyle(SetuColor.warning)
                                Text("加载失败，点击重试")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(Color.black)
                            }
                            .onTapGesture {
                                Task { await loadQrCode() }
                            }
                        }
                    }

                    Text(qrStatusText)
                        .font(SetuTypography.caption)
                        .foregroundStyle(isQrExpired ? SetuColor.warning : SetuColor.textSecondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: SetuSpacing.sm) {
                        Button {
                            saveQrAndOpenApp()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.forward.app.fill")
                                Text("保存至相册并打开网易云")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SetuSpacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SetuColor.brandPink)
                        .disabled(qrImage == nil || isQrExpired || isQrLoading)

                        Button {
                            Task { await loadQrCode() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("刷新二维码")
                            }
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.brandPink)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, SetuSpacing.xs)
            }
        }
        .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
        .listRowBackground(Color.clear)
        .onAppear {
            if qrImage == nil {
                Task { await loadQrCode() }
            }
        }
    }

    // MARK: - Cookie View

    private var cookieSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "Cookie 导入", subtitle: "从网页端开发者工具或快捷指令复制 MUSIC_U 凭证")

                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text("Cookie 内容")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                        TextField("粘贴完整的 Cookie 字符串（含 MUSIC_U）", text: $cookieText, axis: .vertical)
                            .lineLimit(4...7)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: SetuSpacing.sm) {
                        Button {
                            if let paste = UIPasteboard.general.string {
                                cookieText = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                                .font(SetuTypography.caption)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            Task { await importCookie() }
                        } label: {
                            if isVerifyingCookie {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("确认导入")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SetuColor.brandPink)
                        .disabled(isVerifyingCookie || cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
        .listRowBackground(Color.clear)
    }

    // MARK: - Logic & Handlers

    private func sendSmsCode() async {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 11 else { return }
        isSendingCaptcha = true
        defer { isSendingCaptcha = false }
        do {
            let ok = try await environment.neteaseMusicApiClient.sendCaptcha(phone: trimmed)
            if ok {
                feedback = .success("验证码已发送至 \(trimmed)")
                startCountdown()
            } else {
                feedback = .error(UserFacingError(message: "验证码发送失败，请稍后重试"))
            }
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func startCountdown() {
        countdown = 60
        timerTask?.cancel()
        timerTask = Task {
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                countdown -= 1
            }
        }
    }

    private func loginWithSms() async {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedCode = captcha.trimmingCharacters(in: .whitespaces)
        guard trimmedPhone.count == 11, !trimmedCode.isEmpty else { return }
        isSubmittingCaptcha = true
        defer { isSubmittingCaptcha = false }
        do {
            let result = try await environment.neteaseMusicApiClient.loginWithCellphone(phone: trimmedPhone, captcha: trimmedCode)
            await environment.neteaseMusicSession.loginWithCookie(result.cookie)
            feedback = .success("登录成功！欢迎，\(result.profile?.nickname ?? "网易云用户")")
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func loadQrCode() async {
        stopQrPolling()
        isQrLoading = true
        isQrExpired = false
        qrStatusText = "正在生成登录二维码..."
        defer { isQrLoading = false }
        do {
            let key = try await environment.neteaseMusicApiClient.createQrKey()
            let (qrimg, _) = try await environment.neteaseMusicApiClient.createQrImage(key: key)
            self.qrKey = key
            if let img = parseQrImage(base64String: qrimg) {
                self.qrImage = img
                self.qrStatusText = "请使用网易云音乐 App 扫码登录"
                startQrPolling(key: key)
            } else {
                self.qrStatusText = "解析二维码图片失败"
            }
        } catch {
            self.qrStatusText = "生成二维码失败，请重试"
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func parseQrImage(base64String: String) -> UIImage? {
        let clean = base64String.components(separatedBy: ",").last ?? base64String
        guard let data = Data(base64Encoded: clean, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    private func startQrPolling(key: String) {
        stopQrPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { break }
                do {
                    let check = try await environment.neteaseMusicApiClient.checkQrStatus(key: key)
                    switch check.code {
                    case 800:
                        isQrExpired = true
                        qrStatusText = "二维码已过期，点击重新获取"
                        return
                    case 801:
                        qrStatusText = "等待网易云音乐扫码..."
                    case 802:
                        qrStatusText = "已扫描，请在网易云音乐 App 点击授权确认"
                    case 803:
                        if let cookie = check.cookie {
                            qrStatusText = "授权成功，正在初始化..."
                            await environment.neteaseMusicSession.loginWithCookie(cookie)
                            feedback = .success("网易云账号已成功绑定！")
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            dismiss()
                            return
                        }
                    default:
                        break
                    }
                } catch {
                    // Continuous polling network jitter, keep trying
                }
            }
        }
    }

    private func stopQrPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func saveQrAndOpenApp() {
        guard let qrImage else { return }
        UIImageWriteToSavedPhotosAlbum(qrImage, nil, nil, nil)
        feedback = .info("二维码已保存到相册！正在唤起网易云音乐，请在扫一扫中选取相册图片...")

        let orpheusUrl = URL(string: "orpheus://")!
        if UIApplication.shared.canOpenURL(orpheusUrl) {
            UIApplication.shared.open(orpheusUrl)
        } else if let webUrl = URL(string: "https://music.163.com") {
            UIApplication.shared.open(webUrl)
        }
    }

    private func importCookie() async {
        let trimmed = cookieText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isVerifyingCookie = true
        defer { isVerifyingCookie = false }
        do {
            if let profile = try await environment.neteaseMusicApiClient.fetchLoginStatus(cookie: trimmed) {
                await environment.neteaseMusicSession.loginWithCookie(trimmed)
                feedback = .success("Cookie 验证通过，欢迎 \(profile.nickname)！")
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            } else {
                feedback = .error(UserFacingError(message: "该 Cookie 未能解析到有效网易云账号信息，请检查是否包含 MUSIC_U"))
            }
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
