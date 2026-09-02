public enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(UserFacingError)

    public static func failed(_ message: String) -> Self {
        .failed(UserFacingError(message: message))
    }
}
