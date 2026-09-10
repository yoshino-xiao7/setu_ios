import Foundation

public struct UserFacingError: Error, Hashable, Sendable {
    public let title: String
    public let message: String
    public let action: UserFacingErrorAction?
    public let diagnosticCode: String?

    public init(message: String) {
        self.init(title: "加载失败", message: message, action: .retry, diagnosticCode: nil)
    }

    public init(title: String, message: String, action: UserFacingErrorAction?, diagnosticCode: String?) {
        self.title = title
        self.message = message
        self.action = action
        self.diagnosticCode = diagnosticCode
    }
}

public enum UserFacingErrorAction: Hashable, Sendable {
    case retry
    case signIn
    case goBack
    case reviewInput
    case refresh
    case wait
    case viewPoints

    public var buttonTitle: String {
        switch self {
        case .retry: "重试"
        case .signIn: "重新登录"
        case .goBack: "返回"
        case .reviewInput: "检查填写内容"
        case .refresh: "刷新"
        case .wait: "稍后再试"
        case .viewPoints: "查看积分明细"
        }
    }
}

public enum UserFacingErrorMapper {
    public static func map(_ error: Error) -> UserFacingError {
        if let musicError = error as? MusicV2ServerError {
            return map(musicError)
        }

        if let urlError = error as? URLError {
            return map(urlError)
        }

        if let apiError = error as? APIError {
            return map(apiError)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return map(URLError(URLError.Code(rawValue: nsError.code)))
        }

        return UserFacingError(
            title: "操作没有完成",
            message: "遇到了一点问题，请稍后重试。",
            action: .retry,
            diagnosticCode: nil
        )
    }

    private static func map(_ server: MusicV2ServerError) -> UserFacingError {
        let diagnostic = diagnosticCode(requestID: server.requestID, traceID: server.error.traceId)
        if server.status == 401 {
            return UserFacingError(
                title: "登录已过期",
                message: "请重新登录，完成后可以继续当前操作。",
                action: .signIn,
                diagnosticCode: diagnostic
            )
        }
        switch server.error.code {
        case .invalidRequest:
            return UserFacingError(title: "请求内容需要调整", message: server.error.message, action: .reviewInput, diagnosticCode: diagnostic)
        case .forbidden:
            return UserFacingError(title: "当前账号无法执行此操作", message: server.error.message, action: .goBack, diagnosticCode: diagnostic)
        case .resourceNotFound:
            return UserFacingError(title: "音乐内容不存在", message: server.error.message, action: .goBack, diagnosticCode: diagnostic)
        case .trackNotPlayable:
            return UserFacingError(title: "当前歌曲无法播放", message: server.error.message, action: .goBack, diagnosticCode: diagnostic)
        case .upstreamAuthInvalid:
            // This is the provider account, never the Setu user's SID session.
            return UserFacingError(title: "音乐服务暂时不可用", message: server.error.message, action: .wait, diagnosticCode: diagnostic)
        case .upstreamRateLimited, .rateLimited:
            return UserFacingError(title: "音乐请求有点频繁", message: server.error.message, action: .wait, diagnosticCode: diagnostic)
        case .upstreamUnavailable, .internalError:
            return UserFacingError(title: "音乐服务暂时不可用", message: server.error.message, action: .retry, diagnosticCode: diagnostic)
        case .unauthorized:
            // FINAL uses HTTP status, not an untrusted/unknown code alone, as the sign-in boundary.
            return UserFacingError(title: "请求没有完成", message: server.error.message, action: .retry, diagnosticCode: diagnostic)
        case .unknown:
            return UserFacingError(title: "音乐请求没有完成", message: "遇到未知的音乐服务错误，请稍后重试。", action: .retry, diagnosticCode: diagnostic)
        }
    }

    private static func map(_ error: URLError) -> UserFacingError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            UserFacingError(
                title: "网络似乎断开了",
                message: "请检查网络连接后重试。",
                action: .retry,
                diagnosticCode: nil
            )
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            UserFacingError(
                title: "连接有点慢",
                message: "暂时无法连接服务，请稍后重试。",
                action: .retry,
                diagnosticCode: nil
            )
        case .cancelled:
            UserFacingError(
                title: "操作已取消",
                message: "没有产生任何更改。",
                action: nil,
                diagnosticCode: nil
            )
        default:
            UserFacingError(
                title: "网络请求失败",
                message: "请检查网络连接后重试。",
                action: .retry,
                diagnosticCode: nil
            )
        }
    }

    private static func map(_ error: APIError) -> UserFacingError {
        switch error {
        case .invalidURL, .invalidResponse:
            return UserFacingError(
                title: "服务暂时不可用",
                message: "请稍后重试。",
                action: .retry,
                diagnosticCode: nil
            )
        case .httpStatus(let status, let backendMessage, let requestID, let traceID, let code):
            let diagnosticCode = diagnosticCode(requestID: requestID, traceID: traceID)
            if [400, 409, 422].contains(status), isPointsError(backendMessage) {
                return UserFacingError(
                    title: "积分不足",
                    message: "当前积分不足以完成此操作，请先查看积分获取方式。",
                    action: .viewPoints,
                    diagnosticCode: diagnosticCode
                )
            }
            if code == "MODULE_FAVORITE_LIMIT" {
                return UserFacingError(
                    title: "收藏已满",
                    message: backendMessage ?? "每个模块最多收藏 500 个。",
                    action: .goBack,
                    diagnosticCode: diagnosticCode
                )
            }
            switch status {
            case 400, 422:
                return UserFacingError(
                    title: "提交内容需要调整",
                    message: "请检查填写内容后重试。",
                    action: .reviewInput,
                    diagnosticCode: diagnosticCode
                )
            case 401:
                return UserFacingError(
                    title: "登录已过期",
                    message: "请重新登录，完成后可以继续当前操作。",
                    action: .signIn,
                    diagnosticCode: diagnosticCode
                )
            case 403:
                return UserFacingError(
                    title: "当前账号无法执行此操作",
                    message: "你可以返回上一页或使用其他账号。",
                    action: .goBack,
                    diagnosticCode: diagnosticCode
                )
            case 404:
                return UserFacingError(
                    title: "内容不存在",
                    message: "它可能已经被移除，请返回列表查看其他内容。",
                    action: .goBack,
                    diagnosticCode: diagnosticCode
                )
            case 409:
                return UserFacingError(
                    title: "内容状态已变化",
                    message: "刷新后即可继续操作。",
                    action: .refresh,
                    diagnosticCode: diagnosticCode
                )
            case 429:
                return UserFacingError(
                    title: "操作有点频繁",
                    message: "请稍等片刻后再试。",
                    action: .wait,
                    diagnosticCode: diagnosticCode
                )
            case 500...599:
                return UserFacingError(
                    title: "服务暂时开小差",
                    message: "请稍后重试。",
                    action: .retry,
                    diagnosticCode: diagnosticCode
                )
            default:
                return UserFacingError(
                    title: "请求没有完成",
                    message: "请稍后重试。",
                    action: .retry,
                    diagnosticCode: diagnosticCode
                )
            }
        }
    }

    private static func diagnosticCode(requestID: String?, traceID: String?) -> String? {
        let values = [requestID, traceID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private static func isPointsError(_ message: String?) -> Bool {
        guard let message else { return false }
        let normalized = message.lowercased()
        return normalized.contains("积分")
            || normalized.contains("余额")
            || normalized.contains("insufficient points")
    }
}
