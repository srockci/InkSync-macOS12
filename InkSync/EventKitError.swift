import Foundation

enum EventKitError: LocalizedError, Equatable {
    case notAuthorized
    case calendarNotFound
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未获得提醒事项访问权限"
        case .calendarNotFound:
            return "找不到指定的提醒事项列表"
        case .reminderNotFound:
            return "找不到指定的待办"
        }
    }
}
