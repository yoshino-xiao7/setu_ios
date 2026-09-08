import CryptoKit
import Foundation
import Security

public enum PixivImageHost: String, CaseIterable, Sendable {
    case origin, mirror, custom
    public static let preferenceKey = "pixiv.images.host"
    public static let customPreferenceKey = "pixiv.images.customHost"
    public static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .mirror }
    public var title: String {
        switch self { case .mirror: return "直连镜像（i.pixiv.re）"; case .origin: return "Pixiv 原站"; case .custom: return "自定义图床" }
    }
    public static func normalizedCustomHost(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = value.contains("://") ? value : "https://" + value
        guard let url = URLComponents(string: raw), url.scheme == "https",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", let host = url.url?.host?.lowercased(), host.count <= 253,
              host.contains("."), !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              host != "pixiv.net", !host.hasSuffix(".pixiv.net"),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }), host.split(separator: ".").last?.contains(where: { $0.isLetter }) == true else {
            throw PixivClientError("请输入 HTTPS 图床域名，例如 images.example.com；不包含路径、端口或账号信息")
        }
        return host
    }
    func resourceURL(_ value: String, customHost: String? = nil) -> String {
        guard self != .origin, let selected = self == .mirror ? "i.pixiv.re" : customHost,
              var url = URLComponents(string: value), url.scheme == "https",
              ["i.pximg.net", "i-cf.pximg.net"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { return value }
        url.host = selected
        return url.string ?? value
    }
}

/// One local Setu account owns one Pixiv binding. Credentials never enter APIClient.
public actor PixivLocalClient: PixivOnlineServing {
    private struct Credentials: Codable, Sendable {
        let access: String
        let refresh: String
        let expires: Date
        let accountID: String
        let name: String
        let version: String
    }
    private struct AuthorizationSession {
        let id: String
        let verifier: String
        let expires: Date
        let epoch: UUID
    }
    private let owner: String
    private let keychain: KeychainStoring
    private let transport: any PixivHTTPTransport
    private let animationRenderer: any PixivAnimationRendering
    private let imageHost: @Sendable () -> PixivImageHost
    private let customImageHost: @Sendable () -> String
    private var credentials: Credentials?
    private var restored = false
    private var pending: AuthorizationSession?
    private var epoch = UUID()
    private var refreshTask: Task<Credentials, Error>?
    private var refreshGeneration = UUID()
    private struct Cursor { let path: String; let filter: String; let version: String; let expires: Date }
    private struct Media { let url: String; let version: String }
    private var cursors: [String: Cursor] = [:]
    private var resources: [String: Media] = [:]
    private var resourceOrder: [String] = []
    // Owned by this binding only. Cap compressed bytes independently of decoded view images.
    private var mediaCache = PixivMediaCache()
    private var mediaTasks: [String: Task<Data, Error>] = [:]
    private struct AnimationJob {
        let id: String; let workID: String; let version: String; let created: Date
        var status = "pending"; var output: URL?; var message: String?
    }
    private var jobs: [String: AnimationJob] = [:]
    private var animationTasks: [String: Task<Void, Never>] = [:]
    private var key: String { "pixiv.local.\(owner).credentials" }

    // Public native-client protocol identifiers; never a Setu secret or a user's password.
    private static let clientID = "MOBrBDS8blbauoSck0ZfDbtuzpyT"
    private static let clientSignature = "lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"
    private static let hashSalt = "28c1fdd170a5204386cb1313c7077b34f83e4aaf4aa829ce78c231e05b0bae2c"

    public init(owner: String, keychain: KeychainStoring, transport: any PixivHTTPTransport = PixivDirectHTTPTransport(), animationRenderer: any PixivAnimationRendering = PixivAnimationRenderer(), imageHost: @escaping @Sendable () -> PixivImageHost = { .origin }, customImageHost: @escaping @Sendable () -> String = { UserDefaults.standard.string(forKey: PixivImageHost.customPreferenceKey) ?? "" }) {
        self.owner = owner; self.keychain = keychain; self.transport = transport
        self.animationRenderer = animationRenderer
        self.imageHost = imageHost
        self.customImageHost = customImageHost
    }
    public func binding() throws -> PixivAccountBinding {
        try restore()
        return PixivAccountBinding(bound: credentials != nil, accountId: credentials?.accountID, name: credentials?.name, version: credentials?.version)
    }
    public func authorize() throws -> PixivAuthorization {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw PixivClientError("无法创建安全登录会话，请重试") }
        let verifier = Self.base64URL(Data(bytes))
        epoch = UUID()
        let session = AuthorizationSession(id: UUID().uuidString, verifier: verifier, expires: Date().addingTimeInterval(600), epoch: epoch)
        pending = session
        let query = Self.form(["code_challenge": Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))), "code_challenge_method": "S256", "client": "pixiv-android"])
        return PixivAuthorization(sessionId: session.id, loginUrl: "https://app-api.pixiv.net/web/v1/login?" + query)
    }
    public func complete(sessionID: String, code: String) async throws -> PixivAccountBinding {
        guard let session = pending, session.id == sessionID, session.expires > Date(), !code.isEmpty, code.count <= 4096 else {
            throw PixivClientError("登录会话已失效，请重新开始")
        }
        pending = nil // Consume before suspension; neither another owner nor a retry can replay it.
        let token = try await exchange(["grant_type": "authorization_code", "code": code, "code_verifier": session.verifier,
            "redirect_uri": "https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback"])
        guard session.epoch == epoch else { throw CancellationError() }
        refreshTask?.cancel(); refreshTask = nil; refreshGeneration = UUID()
        try persist(token)
        clearResources()
        return try binding()
    }
    public func unlink() throws {
        epoch = UUID(); pending = nil; refreshTask?.cancel(); refreshTask = nil; refreshGeneration = UUID()
        try keychain.remove(key)
        credentials = nil; restored = true
        clearResources()
    }
    private func restore() throws {
        guard !restored else { return }
        if let encoded = try keychain.string(for: key) {
            do { credentials = try JSONDecoder().decode(Credentials.self, from: Data(encoded.utf8)) }
            catch { throw PixivClientError("本机 Pixiv 登录信息不可用，请重新登录") }
        }
        restored = true
    }
    private func persist(_ value: Credentials) throws {
        let encoded = try JSONEncoder().encode(value)
        try keychain.setString(String(decoding: encoded, as: UTF8.self), for: key)
        credentials = value; restored = true
    }
    private func required() throws -> Credentials {
        try restore()
        guard let value = credentials else { throw PixivClientError("请先在本机登录 Pixiv") }
        return value
    }
    private func token(rejected: String? = nil) async throws -> Credentials {
        let current = try required()
        if current.expires > Date().addingTimeInterval(60), rejected == nil || rejected != current.access { return current }
        if let refreshTask { return try await refreshTask.value }
        let generation = UUID()
        refreshGeneration = generation
        let task = Task { try await self.refresh(current) }
        refreshTask = task
        defer { if refreshGeneration == generation { refreshTask = nil } }
        return try await task.value
    }
    private func refresh(_ previous: Credentials) async throws -> Credentials {
        let next = try await exchange(["grant_type": "refresh_token", "refresh_token": previous.refresh], version: previous.version)
        try Task.checkCancellation()
        guard credentials?.version == previous.version else { throw CancellationError() }
        guard next.accountID == previous.accountID else { throw PixivClientError("Pixiv 刷新返回的账号不一致，请重新登录") }
        try persist(next)
        return next
    }
    private func exchange(_ fields: [String: String], version: String = UUID().uuidString) async throws -> Credentials {
        var form = fields
        form["client_id"] = Self.clientID; form["client_secret"] = Self.clientSignature; form["include_policy"] = "true"
        var request = PixivHTTPRequest(url: "https://oauth.secure.pixiv.net/auth/token")
        request.method = "POST"; request.headers = Self.headers(oauth: true)
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = Self.form(form)
        let response = try await transport.send(request)
        try Self.validate(response, authorization: true)
        let decoder = Self.decoder()
        let token: Token
        do { token = try decoder.decode(TokenEnvelope.self, from: response.data).value }
        catch { throw PixivClientError("Pixiv 授权响应异常，请重新登录") }
        guard !token.accessToken.isEmpty, !token.refreshToken.isEmpty, token.expiresIn >= 0 else { throw PixivClientError("Pixiv 未返回有效的登录信息") }
        return Credentials(access: token.accessToken, refresh: token.refreshToken, expires: Date().addingTimeInterval(min(token.expiresIn, 86400)),
            accountID: token.user.id.value, name: token.user.name, version: version)
    }
    private static func decoder() -> JSONDecoder { let value = JSONDecoder(); value.keyDecodingStrategy = .convertFromSnakeCase; return value }
    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func form(_ values: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }
    private static func headers(oauth: Bool = false) -> [String: String] {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'+00:00'"
        let now = format.string(from: Date())
        let hash = Insecure.MD5.hash(data: Data((now + hashSalt).utf8)).map { String(format: "%02x", $0) }.joined()
        return ["User-Agent": oauth ? "PixivAndroidApp/5.0.155 (Android 6.0; Pixel C)" : "PixivAndroidApp/5.0.155 (Android 10.0; Pixel C)", "App-OS": "Android", "App-OS-Version": oauth ? "Android 6.0" : "Android 10.0", "App-Version": "5.0.166", "Accept-Language": "zh-CN", "X-Client-Time": now, "X-Client-Hash": hash]
    }
    private static func validate(_ response: PixivHTTPResponse, authorization: Bool = false) throws {
        if response.status == 429 { throw PixivClientError("Pixiv 请求频繁，请稍后重试") }
        if response.status == 401 || (authorization && response.status == 400) { throw PixivClientError("Pixiv 登录已失效，请重新登录") }
        if response.status == 403 {
            throw PixivClientError(authorization
                ? "令牌交换被拒绝（HTTP 403），尚未完成绑定。请稍后重新登录"
                : "Pixiv 拒绝了当前请求（HTTP 403），请稍后重试")
        }
        if response.status == 404 { throw PixivClientError("作品不存在或当前账号无法访问") }
        guard (200..<300).contains(response.status) else { throw PixivClientError("Pixiv 暂时无法完成请求，请重试") }
    }
    private struct TokenEnvelope: Decodable {
        let value: Token
        private enum CodingKeys: String, CodingKey { case response }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decodeIfPresent(Token.self, forKey: .response) ?? Token(from: decoder)
        }
    }
    private struct Token: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: TokenUser
    }
    private struct TokenUser: Decodable { let id: PixivIdentifier; let name: String }

    private func clearResources() {
        cursors.removeAll(); resources.removeAll(); resourceOrder.removeAll()
        mediaCache.removeAll()
        mediaTasks.values.forEach { $0.cancel() }; mediaTasks.removeAll()
        animationTasks.values.forEach { $0.cancel() }; animationTasks.removeAll()
        for job in jobs.values { if let output = job.output { try? FileManager.default.removeItem(at: output) } }
        jobs.removeAll()
    }
    private static func readURL(_ path: String) throws -> String {
        let raw = path.hasPrefix("/") ? "https://app-api.pixiv.net" + path : path
        guard let url = URLComponents(string: raw), url.scheme == "https", url.host == "app-api.pixiv.net", url.port == nil, url.user == nil, url.password == nil, url.fragment == nil, PixivAPIEndpoint.readPaths.contains(url.path) else {
            throw PixivClientError("Pixiv 分页地址无效，请刷新列表")
        }
        return raw
    }
    private static func identifier(_ value: String?) throws -> String {
        guard let value, !value.isEmpty, value.count <= 19, value.first != "0", value.utf8.allSatisfy({ (48...57).contains($0) }) else { throw PixivClientError("作品或画师 ID 无效") }
        return value
    }
    private func app(_ path: String, form: [String: String]? = nil) async throws -> (Data, String) {
        let url: String
        if form == nil { url = try Self.readURL(path) }
        else {
            guard PixivAPIEndpoint.writePaths.contains(path) else { throw PixivClientError("不支持的 Pixiv 操作") }
            url = "https://app-api.pixiv.net" + path
        }
        var account = try await token()
        for attempt in 0..<2 {
            var request = PixivHTTPRequest(url: url)
            request.headers = Self.headers(); request.headers["Authorization"] = "Bearer " + account.access
            if let form { request.method = "POST"; request.headers["Content-Type"] = "application/x-www-form-urlencoded"; request.body = Self.form(form) }
            let response = try await transport.send(request)
            try Task.checkCancellation()
            guard credentials?.version == account.version else { throw CancellationError() }
            let rejected = response.status == 401 || (response.status == 400 && String(decoding: response.data, as: UTF8.self).lowercased().contains("oauth"))
            if rejected && attempt == 0 { account = try await token(rejected: account.access); continue }
            if rejected { throw PixivClientError("Pixiv 登录已失效，请重新登录") }
            try Self.validate(response)
            return (response.data, account.version)
        }
        throw PixivClientError("Pixiv 登录已失效，请重新登录")
    }
    public func works(params: [String: String] = [:]) async throws -> ArtworkListResponse {
        let account = try required()
        let filter = Self.form(params.filter { $0.key != "cursor" })
        let path: String
        if let cursor = params["cursor"], !cursor.isEmpty {
            guard let value = cursors[cursor], value.expires > Date(), value.version == account.version, value.filter == filter else { throw PixivClientError("列表已失效，请刷新后继续浏览") }
            path = value.path
        } else {
            switch params["view"] ?? "recommended" {
            case "recommended": path = "/v1/illust/recommended?filter=for_ios&include_ranking_label=true"
            case "ranking":
                let mode = params["ranking"] ?? "day"
                guard ["day", "week", "month", "day_male", "day_female"].contains(mode) else { throw PixivClientError("不支持的排行榜") }
                path = "/v1/illust/ranking?mode=" + mode
            case "search":
                let query = (params["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty, query.count <= 200 else { throw PixivClientError("请输入 1–200 字的关键词") }
                path = "/v1/search/illust?" + Self.form(["word": query, "search_target": "partial_match_for_tags", "sort": "date_desc"])
            case "artist": path = "/v1/user/illusts?type=illust&user_id=" + (try Self.identifier(params["authorId"]))
            case "bookmarks", "privateBookmarks": path = "/v1/user/bookmarks/illust?user_id=" + account.accountID + "&restrict=" + (params["view"] == "privateBookmarks" ? "private" : "public")
            case "following": path = "/v2/illust/follow?restrict=all"
            case "related": path = "/v2/illust/related?illust_id=" + (try Self.identifier(params["relatedId"]))
            default: throw PixivClientError("不支持的图片列表")
            }
        }
        let (data, version) = try await app(path)
        let result = try Self.decoder().decode(PixivWorkList.self, from: data)
        let restricted = params["r18"] ?? "0"
        guard ["0", "1", "2"].contains(restricted) else { throw PixivClientError("内容筛选无效") }
        let items = try (result.illusts ?? []).filter {
            $0.visible != false && (restricted == "2" || (($0.xRestrict ?? 0) > 0) == (restricted == "1")) && (params["excludeAI"] == "false" || $0.illustAiType != 2)
        }.map { try map($0, version: version, detail: false) }
        var next: String?
        if let url = result.nextUrl, !url.isEmpty {
            let valid = try Self.readURL(url)
            cursors = cursors.filter { $0.value.expires > Date() }
            if cursors.count >= 128 { cursors.removeAll() }
            let id = UUID().uuidString
            cursors[id] = Cursor(path: valid, filter: filter, version: version, expires: Date().addingTimeInterval(7200)); next = id
        }
        return ArtworkListResponse(items: items, nextCursor: next)
    }
    public func detail(id: String) async throws -> BrowserArtwork {
        let (data, version) = try await app("/v1/illust/detail?illust_id=" + Self.identifier(id))
        let result = try Self.decoder().decode(PixivWorkList.self, from: data)
        guard let work = result.illust, work.visible != false else { throw PixivClientError("作品不存在或当前账号无法访问") }
        return try map(work, version: version, detail: true)
    }
    public func artists() async throws -> [ArtworkArtist] {
        let (data, version) = try await app("/v1/user/recommended")
        return try Self.decoder().decode(PixivWorkList.self, from: data).userPreviews?.map { artist($0.user, version: version) } ?? []
    }
    public func spotlights() async throws -> [ArtworkSpotlight] {
        let (data, version) = try await app("/v1/spotlight/articles?category=all")
        return try Self.decoder().decode(PixivWorkList.self, from: data).spotlightArticles?.compactMap { article in
            guard let url = URL(string: article.articleUrl), url.scheme == "https", url.host == "www.pixivision.net" else { return nil }
            return ArtworkSpotlight(id: article.id.value, title: article.title, thumbnailUrl: register(article.thumbnail, version: version), url: article.articleUrl)
        } ?? []
    }
    public func bookmark(id: String, enabled: Bool, visibility: String = "public") async throws {
        guard ["public", "private"].contains(visibility) else { throw PixivClientError("收藏公开范围无效") }
        var fields = ["illust_id": try Self.identifier(id)]
        if enabled { fields["restrict"] = visibility }
        _ = try await app(enabled ? "/v2/illust/bookmark/add" : "/v1/illust/bookmark/delete", form: fields)
    }
    public func follow(id: String, enabled: Bool) async throws {
        var fields = ["user_id": try Self.identifier(id)]
        if enabled { fields["restrict"] = "public" }
        _ = try await app(enabled ? "/v1/user/follow/add" : "/v1/user/follow/delete", form: fields)
    }
    private func register(_ value: String?, version: String) -> String? {
        guard let value, let url = URLComponents(string: value), url.scheme == "https", ["i.pximg.net", "s.pximg.net", "i-cf.pximg.net"].contains(url.host ?? ""), url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { return nil }
        let id = UUID().uuidString
        resources[id] = Media(url: value, version: version); resourceOrder.append(id)
        while resourceOrder.count > 4096 { resources.removeValue(forKey: resourceOrder.removeFirst()) }
        return "pixiv-local://media/" + id
    }
    public func media(_ path: String) async throws -> Data {
        try Task.checkCancellation()
        let account = try required()
        if let url = URL(string: path), url.scheme == "pixiv-local", url.host == "animation" {
            guard let job = jobs[url.lastPathComponent], job.version == account.version, job.status == "ready", let output = job.output else { throw PixivClientError("动图状态已失效，请重试") }
            return try Data(contentsOf: output, options: .mappedIfSafe)
        }
        guard let url = URL(string: path), url.scheme == "pixiv-local", url.host == "media", let resource = resources[url.lastPathComponent], resource.version == account.version else { throw PixivClientError("图片状态已失效，请重新打开作品") }
        // The public capability changes when a feed is refreshed; the validated origin URL does not.
        // Validate the capability and binding BEFORE consulting any cached bytes.
        let cacheKey = account.version + ":" + resource.url
        if let data = mediaCache.value(for: cacheKey) { return data }
        let task: Task<Data, Error>
        if let existing = mediaTasks[cacheKey] { task = existing }
        else {
            task = Task { try await self.downloadMedia(resource, cacheKey: cacheKey) }
            mediaTasks[cacheKey] = task
        }
        // Scrolling offscreen cancels the view, not another view's shared download. The transport
        // still has its bounded deadline; a completed download remains reusable on the return scroll.
        let data = try await task.value
        try Task.checkCancellation()
        guard credentials?.version == account.version else { throw CancellationError() }
        return data
    }

    private func downloadMedia(_ resource: Media, cacheKey: String) async throws -> Data {
        defer { mediaTasks.removeValue(forKey: cacheKey) }
        let selected = imageHost()
        let custom = selected == .custom ? try PixivImageHost.normalizedCustomHost(customImageHost()) : nil
        var request = PixivHTTPRequest(url: selected.resourceURL(resource.url, customHost: custom))
        if let host = URL(string: request.url)?.host,
           !["i.pximg.net", "s.pximg.net", "i-cf.pximg.net", "i.pixiv.re"].contains(host) {
            request.image_mirror_host = custom
        }
        request.max_bytes = 40 * 1024 * 1024
        request.headers = ["Referer": "https://www.pixiv.net/", "User-Agent": "PixivIOSApp/5.8.0"]
        let result = try await transport.send(request)
        try Task.checkCancellation()
        guard credentials?.version == resource.version else { throw CancellationError() }
        if request.url != resource.url && !(200..<300).contains(result.status) {
            throw PixivClientError("图片图床返回 HTTP \(result.status)，请重试或在图片设置中切换图床")
        }
        try Self.validate(result)
        let mime = result.contentType.split(separator: ";").first.map(String.init) ?? ""
        guard ["image/jpeg", "image/png", "image/gif", "image/webp", "image/avif"].contains(mime) else { throw PixivClientError("图片格式不可用") }
        mediaCache.insert(result.data, for: cacheKey)
        return result.data
    }
    public func animation(workID: String) throws -> ArtworkAnimation {
        let account = try required()
        _ = try Self.identifier(workID)
        if let existing = jobs.values.first(where: { $0.workID == workID && $0.version == account.version && $0.status != "failed" }) {
            return try animationStatus(id: existing.id)
        }
        guard jobs.values.filter({ $0.status == "running" || $0.status == "pending" }).count < 2 else { throw PixivClientError("正在处理其他动图，请稍后重试") }
        if jobs.count >= 3, let oldest = jobs.values.filter({ $0.status != "running" && $0.status != "pending" }).min(by: { $0.created < $1.created }) {
            if let output = oldest.output { try? FileManager.default.removeItem(at: output) }; jobs.removeValue(forKey: oldest.id)
        }
        let id = UUID().uuidString
        jobs[id] = AnimationJob(id: id, workID: workID, version: account.version, created: Date())
        animationTasks[id] = Task { await self.renderAnimation(id: id) }
        return try animationStatus(id: id)
    }
    public func animationStatus(id: String) throws -> ArtworkAnimation {
        let account = try required()
        guard let job = jobs[id], job.version == account.version else { throw PixivClientError("动图任务已失效，请重试") }
        return ArtworkAnimation(id: id, status: job.status, mediaUrl: job.output == nil ? nil : "pixiv-local://animation/" + id, message: job.message)
    }
    private func renderAnimation(id: String) async {
        guard let job = jobs[id] else { return }
        jobs[id]?.status = "running"
        defer { animationTasks.removeValue(forKey: id) }
        do {
            let (data, version) = try await app("/v1/ugoira/metadata?illust_id=" + job.workID)
            guard version == job.version else { throw CancellationError() }
            let result = try Self.decoder().decode(PixivUgoiraEnvelope.self, from: data).ugoiraMetadata
            guard let ticket = register(result.zipUrls.medium, version: version), let url = URL(string: ticket), let media = resources[url.lastPathComponent] else { throw PixivClientError("动图资源地址不可用") }
            var request = PixivHTTPRequest(url: media.url)
            request.headers = ["Referer": "https://www.pixiv.net/"]; request.max_bytes = 100 * 1024 * 1024
            let zip = try await transport.send(request)
            try Self.validate(zip); try Task.checkCancellation()
            guard credentials?.version == version else { throw CancellationError() }
            let output = try await animationRenderer.render(zip: zip.data, frames: result.frames)
            guard credentials?.version == version, jobs[id] != nil, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: output); throw CancellationError()
            }
            jobs[id]?.output = output; jobs[id]?.status = "ready"
        } catch {
            jobs[id]?.status = "failed"
            jobs[id]?.message = error is CancellationError ? "动图处理已取消，请重试" : error.localizedDescription
        }
    }
    private func artist(_ value: PixivUser, version: String) -> ArtworkArtist {
        ArtworkArtist(id: value.id.value, name: value.name, avatarUrl: register(value.profileImageUrls?.medium, version: version), followed: value.isFollowed)
    }
    private func map(_ work: PixivWork, version: String, detail: Bool) throws -> BrowserArtwork {
        let count = max(1, work.pageCount ?? 1)
        guard count <= 1000 else { throw PixivClientError("作品页数超出当前支持范围") }
        if detail && count > 1 && (work.metaPages?.count ?? 0) < count { throw PixivClientError("作品分页信息不完整，请重试") }
        let pages = (0..<(detail ? count : 1)).map { index -> ArtworkPage in
            let urls = work.metaPages?.indices.contains(index) == true ? work.metaPages![index].imageUrls : work.imageUrls
            return ArtworkPage(index: index, pid: work.id.value, width: work.width ?? 0, height: work.height ?? 0,
                thumbnailUrl: register(urls?.medium ?? urls?.squareMedium, version: version), previewUrl: register(urls?.large ?? urls?.medium, version: version),
                originalUrl: detail ? register(urls?.original ?? work.metaSinglePage?.originalImageUrl, version: version) : nil, bookmarked: nil)
        }
        return BrowserArtwork(source: .pixiv, id: work.id.value, pid: work.id.value, title: work.title, artist: artist(work.user, version: version),
            kind: work.type ?? "illust", pageCount: count, pages: pages, tags: work.tags?.map(\.name) ?? [], caption: Self.caption(work.caption),
            createdAt: work.createDate, views: work.totalView, bookmarks: work.totalBookmarks, bookmarked: work.isBookmarked ?? false,
            restricted: (work.xRestrict ?? 0) > 0, aiGenerated: work.illustAiType == 2)
    }
    private static func caption(_ html: String?) -> String? {
        guard let html else { return nil }
        let normalized = html.replacingOccurrences(of: "<br>", with: "<br/>").replacingOccurrences(of: "&nbsp;", with: "&#160;")
        let delegate = PixivCaptionParser()
        let parser = XMLParser(data: Data(("<caption>" + normalized + "</caption>").utf8))
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        return parser.parse() ? delegate.text : html
    }
}

struct PixivIdentifier: Decodable, Sendable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { value = string }
        else { value = String(try container.decode(Int64.self)) }
    }
}

private struct PixivImages: Decodable { let medium: String?; let squareMedium: String?; let large: String?; let original: String? }
private struct PixivUser: Decodable { let id: PixivIdentifier; let name: String; let profileImageUrls: PixivImages?; let isFollowed: Bool? }
private struct PixivWork: Decodable {
    struct Page: Decodable { let imageUrls: PixivImages? }
    struct Single: Decodable { let originalImageUrl: String? }
    struct Tag: Decodable { let name: String }
    let id: PixivIdentifier; let title: String; let user: PixivUser
    let type: String?; let width: Int?; let height: Int?; let pageCount: Int?; let imageUrls: PixivImages?
    let metaPages: [Page]?; let metaSinglePage: Single?; let tags: [Tag]?; let caption: String?
    let createDate: String?; let totalView: Int?; let totalBookmarks: Int?; let isBookmarked: Bool?
    let xRestrict: Int?; let illustAiType: Int?; let visible: Bool?
}
private struct PixivWorkList: Decodable {
    struct Preview: Decodable { let user: PixivUser }
    struct Spotlight: Decodable { let id: PixivIdentifier; let title: String; let thumbnail: String?; let articleUrl: String }
    let illusts: [PixivWork]?; let illust: PixivWork?; let nextUrl: String?
    let userPreviews: [Preview]?; let spotlightArticles: [Spotlight]?
}
private struct PixivUgoiraEnvelope: Decodable {
    struct Metadata: Decodable { let zipUrls: PixivImages; let frames: [PixivAnimationFrame] }
    let ugoiraMetadata: Metadata
}
/// Actor-confined LRU: no URLs or image content are written to disk.
struct PixivMediaCache {
    private let byteLimit: Int
    private let countLimit: Int
    private var entries: [String: Data] = [:]
    private var order: [String] = []
    private(set) var byteCount = 0

    init(byteLimit: Int = 64 * 1024 * 1024, countLimit: Int = 256) {
        self.byteLimit = max(0, byteLimit); self.countLimit = max(0, countLimit)
    }
    mutating func value(for key: String) -> Data? {
        guard let data = entries[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return data
    }
    mutating func insert(_ data: Data, for key: String) {
        guard !data.isEmpty, data.count <= byteLimit, countLimit > 0 else { return }
        if let previous = entries.removeValue(forKey: key) { byteCount -= previous.count }
        order.removeAll { $0 == key }
        while byteCount + data.count > byteLimit || entries.count >= countLimit {
            let oldest = order.removeFirst()
            byteCount -= entries.removeValue(forKey: oldest)?.count ?? 0
        }
        entries[key] = data; order.append(key); byteCount += data.count
    }
    mutating func removeAll() { entries.removeAll(); order.removeAll(); byteCount = 0 }
}

private final class PixivCaptionParser: NSObject, XMLParserDelegate {
    var text = ""
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "br" { text += "\n" }
    }
}
