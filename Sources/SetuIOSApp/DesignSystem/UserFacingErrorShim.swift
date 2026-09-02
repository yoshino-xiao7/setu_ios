import SetuIOSCore

// 用户可读错误映射的唯一实现在 SetuIOSCore（Core/Errors/UserFacingError.swift）。
// 此垫片仅为 App 内既有调用点保持同名可见，勿在此添加新逻辑。
typealias UserFacingError = SetuIOSCore.UserFacingError
typealias UserFacingErrorAction = SetuIOSCore.UserFacingErrorAction
typealias UserFacingErrorMapper = SetuIOSCore.UserFacingErrorMapper
