enum ImageUnlockTrigger: Equatable {
    case previewSettled
    case userRequestedHighResolution
}

enum ImageUnlockPolicy {
    static func shouldConsume(trigger: ImageUnlockTrigger, isAlreadyUnlocked: Bool) -> Bool {
        guard !isAlreadyUnlocked else { return false }
        return trigger == .userRequestedHighResolution
    }
}
