import Foundation

struct RecurringReminder: Codable, Identifiable {
    let id: UUID
    var title: String
    var notes: String?
    var isEnabled: Bool

    var recurrenceRule: RecurrenceRule
    var triggerTime: TriggerTime

    var startDate: Date
    var endDate: Date?

    var syncTargets: SyncTargets
    var advancedOptions: AdvancedOptions

    var createdAt: Date
    var updatedAt: Date
    var lastGeneratedAt: Date?
    var nextScheduledAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        isEnabled: Bool = true,
        recurrenceRule: RecurrenceRule = .daily,
        triggerTime: TriggerTime = TriggerTime(hour: 9, minute: 0),
        startDate: Date = Date(),
        endDate: Date? = nil,
        syncTargets: SyncTargets = SyncTargets(),
        advancedOptions: AdvancedOptions = AdvancedOptions(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastGeneratedAt: Date? = nil,
        nextScheduledAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isEnabled = isEnabled
        self.recurrenceRule = recurrenceRule
        self.triggerTime = triggerTime
        self.startDate = startDate
        self.endDate = endDate
        self.syncTargets = syncTargets
        self.advancedOptions = advancedOptions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastGeneratedAt = lastGeneratedAt
        self.nextScheduledAt = nextScheduledAt
    }

    var summary: String {
        recurrenceRule.summary
    }
}

struct TriggerTime: Codable, Equatable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct SyncTargets: Codable, Equatable {
    var appleReminders: Bool
    var inkScreenCloud: Bool

    init(appleReminders: Bool = true, inkScreenCloud: Bool = true) {
        self.appleReminders = appleReminders
        self.inkScreenCloud = inkScreenCloud
    }

    var none: Bool { !appleReminders && !inkScreenCloud }
}

struct AdvancedOptions: Codable, Equatable {
    var duplicateStrategy: DuplicateStrategy
    var autoComplete: Bool
    var tags: [String]

    enum DuplicateStrategy: String, Codable, CaseIterable {
        case skip
        case overwrite
        case appendNumber

        var label: String {
            switch self {
            case .skip: return "跳过生成"
            case .overwrite: return "覆盖已有"
            case .appendNumber: return "追加序号"
            }
        }
    }

    init(
        duplicateStrategy: DuplicateStrategy = .skip,
        autoComplete: Bool = false,
        tags: [String] = []
    ) {
        self.duplicateStrategy = duplicateStrategy
        self.autoComplete = autoComplete
        self.tags = tags
    }
}