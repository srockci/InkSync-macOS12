import Foundation
import EventKit

@MainActor
final class RecurringEngine: ObservableObject {
    @Published private(set) var rules: [RecurringReminder] = []
    @Published private(set) var todayGeneratedCount: Int = 0
    @Published private(set) var lastTriggerTime: Date?

    private let store: RecurringReminderStore
    private let logger: RecurringGenerationLogger
    private let scheduler: RecurrenceScheduler
    private let eventKitManager: EventKitManager
    private let mappingManager: MappingManager
    private let notificationManager: NotificationManager
    private let appConfig: AppConfig

    private var timer: Timer?
    private var isCatchingUp = false
    private let checkInterval: TimeInterval = 15
    private let graceWindowMinutes: Int = 5

    init(
        store: RecurringReminderStore = .shared,
        logger: RecurringGenerationLogger = .shared,
        scheduler: RecurrenceScheduler = RecurrenceScheduler(),
        eventKitManager: EventKitManager,
        mappingManager: MappingManager,
        notificationManager: NotificationManager = .shared,
        appConfig: AppConfig = .shared
    ) {
        self.store = store
        self.logger = logger
        self.scheduler = scheduler
        self.eventKitManager = eventKitManager
        self.mappingManager = mappingManager
        self.notificationManager = notificationManager
        self.appConfig = appConfig
        self.rules = store.loadAll()
        updateTodayCount()
    }

    func mappingManagerForUI() -> MappingManager { mappingManager }

    func start() {
        stop()
        rebuildSchedule()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndTrigger()
            }
        }
        checkAndTrigger()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reload() {
        rules = store.loadAll()
        rebuildSchedule()
        updateTodayCount()
    }

    func addRule(_ rule: RecurringReminder) {
        var updated = rule
        updated.nextScheduledAt = scheduler.nextTriggerDate(for: updated)
        store.add(updated)
        rules = store.loadAll()
        updateTodayCount()
    }

    func updateRule(_ rule: RecurringReminder) {
        var updated = rule
        updated.updatedAt = Date()
        updated.nextScheduledAt = scheduler.nextTriggerDate(for: updated)
        store.update(updated)
        rules = store.loadAll()
        updateTodayCount()
    }

    func deleteRule(_ id: UUID) {
        store.delete(id)
        rules = store.loadAll()
        updateTodayCount()
    }

    func deleteRules(_ ids: [UUID]) {
        store.deleteMany(ids)
        rules = store.loadAll()
        updateTodayCount()
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        store.setEnabled(id, enabled: enabled)
        rules = store.loadAll()
    }

    func catchUpOnLaunchOrWake() {
        let hours = max(0, appConfig.recurringCatchUpHours)
        guard hours > 0 else { return }
        Task { @MainActor in
            await catchUpForMissedTriggers(maxLookbackHours: hours)
        }
    }

    private func rebuildSchedule() {
        let rebuilt = scheduler.rebuildSchedule(for: rules)
        for rule in rebuilt {
            store.update(rule)
        }
        rules = store.loadAll()
    }

    private func checkAndTrigger() {
        let now = Date()
        let graceStart = now.addingTimeInterval(-TimeInterval(graceWindowMinutes * 60))
        let tolerance: TimeInterval = 1.0

        for rule in rules where rule.isEnabled {
            guard let next = rule.nextScheduledAt else { continue }
            if next <= now.addingTimeInterval(tolerance) && next >= graceStart {
                trigger(rule: rule)
            }
        }

        rebuildSchedule()
        lastTriggerTime = now
        updateTodayCount()

        if hasMissedTriggerWithinCatchUpWindow(now: now) && !isCatchingUp {
            catchUpOnLaunchOrWake()
        }
    }

    private func hasMissedTriggerWithinCatchUpWindow(now: Date) -> Bool {
        let hours = max(0, appConfig.recurringCatchUpHours)
        guard hours > 0 else { return false }
        let catchUpStart = now.addingTimeInterval(-TimeInterval(hours * 3600))
        return rules.contains { rule in
            guard rule.isEnabled, let next = rule.nextScheduledAt else { return false }
            return next < now && next >= catchUpStart
        }
    }

    private func trigger(rule: RecurringReminder) {
        guard let scheduled = rule.nextScheduledAt else { return }
        Task { @MainActor in
            _ = await generateReminder(rule: rule, scheduledTime: scheduled, isCatchup: false)
        }
    }

    func catchUpForMissedTriggers(maxLookbackHours: Int) async {
        guard maxLookbackHours > 0 else { return }
        if isCatchingUp { return }
        isCatchingUp = true
        defer { isCatchingUp = false }

        let now = Date()
        let lookbackStart = now.addingTimeInterval(-TimeInterval(maxLookbackHours * 3600))

        var totalRecovered = 0
        var totalFailed = 0

        for rule in rules where rule.isEnabled {
            if case .custom(_, let unit) = rule.recurrenceRule,
               (unit == .minute || unit == .hour) {
                continue
            }

            guard let next = rule.nextScheduledAt, next <= now else { continue }
            guard next >= lookbackStart else {
                var updated = rule
                updated.nextScheduledAt = scheduler.nextTriggerDate(for: updated, after: now)
                store.update(updated)
                continue
            }

            let missedTimes = scheduler.missedTriggers(for: rule, from: lookbackStart, to: now)
            if missedTimes.isEmpty {
                var updated = rule
                updated.nextScheduledAt = scheduler.nextTriggerDate(for: updated, after: now)
                store.update(updated)
                continue
            }

            for missedTime in missedTimes {
                let log = await generateReminder(
                    rule: rule,
                    scheduledTime: missedTime,
                    isCatchup: true
                )
                if log.success {
                    totalRecovered += 1
                } else {
                    totalFailed += 1
                }
            }

            var updated = rule
            updated.nextScheduledAt = scheduler.nextTriggerDate(for: updated, after: now)
            store.update(updated)
        }

        rules = store.loadAll()
        updateTodayCount()

        if totalRecovered > 0 {
            notificationManager.notifyCatchupRecovered(recovered: totalRecovered, failed: totalFailed)
        }
    }

    @discardableResult
    private func generateReminder(
        rule: RecurringReminder,
        scheduledTime: Date,
        isCatchup: Bool
    ) async -> GenerationLog {
        let listIds = mappingManager.config.lists(for: deviceIdForRule(rule))
        let targetList = listIds.first

        let tags = rule.advancedOptions.tags
        let taggedTitle = tags.isEmpty ? rule.title : rule.title + " " + tags.map { "#\($0)" }.joined(separator: " ")

        var log = GenerationLog(
            ruleId: rule.id,
            ruleTitle: rule.title,
            scheduledTime: scheduledTime,
            actualTime: Date(),
            isCatchup: isCatchup
        )

        if let targetList {
            do {
                let reminder = try await eventKitManager.createReminder(
                    title: taggedTitle,
                    notes: rule.notes,
                    listId: targetList,
                    dueDate: scheduledTime
                )
                if rule.advancedOptions.autoComplete {
                    try? await eventKitManager.setCompleted(true, forReminderId: reminder.id)
                }
                log.createdItemId = reminder.id
                log.success = true
            } catch {
                log.errorMessage = error.localizedDescription
            }
        } else {
            log.errorMessage = "未配置同步列表"
        }

        logger.append(log)

        var updated = rule
        updated.lastGeneratedAt = Date()
        updated.nextScheduledAt = scheduler.nextTriggerDate(for: updated, after: updated.lastGeneratedAt ?? Date())
        store.update(updated)
        rules = store.loadAll()
        updateTodayCount()

        if !isCatchup {
            sendNotification(for: log)
        }
        return log
    }

    private func deviceIdForRule(_ rule: RecurringReminder) -> String {
        mappingManager.devices.first?.id ?? ""
    }

    private func sendNotification(for log: GenerationLog) {
        if log.success {
            notificationManager.notifyRecurringSuccess(title: log.ruleTitle, targets: 1)
        } else {
            notificationManager.notifyRecurringFailure(title: log.ruleTitle)
        }
    }

    private func updateTodayCount() {
        let logs = logger.loadAll()
        let calendar = Calendar.current
        todayGeneratedCount = logs.filter { calendar.isDateInToday($0.actualTime) }.count
    }
}
