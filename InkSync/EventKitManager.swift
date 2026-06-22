import EventKit
import Foundation

@MainActor
final class EventKitManager: ObservableObject {
    let eventStore = EKEventStore()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private var changeObserver: NSObjectProtocol?

    init() {
        refreshAuthorizationStatus()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    var isAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
        }
        return authorizationStatus == .authorized
    }

    var isAccessDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async throws -> Bool {
        let granted: Bool

        if #available(macOS 14.0, *) {
            granted = try await eventStore.requestFullAccessToReminders()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }

        refreshAuthorizationStatus()
        return granted
    }

    func fetchCalendars() -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return eventStore.calendars(for: .reminder)
    }

    func fetchReminders(from calendarIds: [String]) async -> [EKReminder] {
        guard isAuthorized else { return [] }

        let calendars = fetchCalendars().filter { calendarIds.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForReminders(in: calendars)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func fetchTodoItems(from calendarIds: [String]) async -> [TodoItem] {
        let reminders = await fetchReminders(from: calendarIds)
        let calendarNames = Dictionary(
            uniqueKeysWithValues: fetchCalendars().map { ($0.calendarIdentifier, $0.title) }
        )

        return reminders.map { reminder in
            let listId = reminder.calendar.calendarIdentifier
            let listName = calendarNames[listId] ?? reminder.calendar.title
            return reminder.toTodoItem(listId: listId, listName: listName)
        }
    }

    func createReminder(
        title: String,
        notes: String?,
        dueDate: Date?,
        calendarId: String
    ) throws -> EKReminder {
        try ensureAuthorized()

        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw EventKitError.calendarNotFound
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar

        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        try eventStore.save(reminder, commit: true)
        return reminder
    }

    func updateReminder(_ reminder: EKReminder) throws {
        try ensureAuthorized()
        try eventStore.save(reminder, commit: true)
    }

    func deleteReminder(_ reminder: EKReminder) throws {
        try ensureAuthorized()
        try eventStore.remove(reminder, commit: true)
    }

    func toggleCompletion(_ reminder: EKReminder) throws {
        try ensureAuthorized()
        reminder.isCompleted.toggle()
        try eventStore.save(reminder, commit: true)
    }

    func setCompleted(_ completed: Bool, forReminderId id: String) async throws {
        try ensureAuthorized()
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            return
        }
        reminder.isCompleted = completed
        try eventStore.save(reminder, commit: true)
    }

    @discardableResult
    func createReminder(
        title: String,
        notes: String? = nil,
        listId: String,
        dueDate: Date? = nil
    ) async throws -> TodoItem {
        try ensureAuthorized()
        guard let calendar = eventStore.calendar(withIdentifier: listId) else {
            throw EventKitError.calendarNotFound
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        try eventStore.save(reminder, commit: true)
        return TodoItem(
            id: reminder.calendarItemIdentifier,
            title: title,
            notes: notes,
            isCompleted: false,
            dueDate: dueDate,
            dueTime: nil,
            priority: 0,
            listId: listId,
            listName: calendar.title,
            lastModified: Date(),
            source: .local
        )
    }

    func saveTodo(_ todo: TodoItem) async throws {
        try ensureAuthorized()

        if let existingReminder = eventStore.calendarItem(withIdentifier: todo.id) as? EKReminder {
            existingReminder.title = todo.title
            existingReminder.notes = todo.notes
            existingReminder.isCompleted = todo.isCompleted
            if let dueDate = todo.dueDate {
                existingReminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }
            try eventStore.save(existingReminder, commit: true)
        } else {
            guard let calendar = eventStore.calendar(withIdentifier: todo.listId) else {
                throw EventKitError.calendarNotFound
            }

            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = todo.title
            reminder.notes = todo.notes
            reminder.isCompleted = todo.isCompleted
            reminder.calendar = calendar

            if let dueDate = todo.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }

            try eventStore.save(reminder, commit: true)
        }
    }

    func startMonitoringChanges(callback: @escaping () -> Void) {
        stopMonitoringChanges()

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { _ in
            callback()
        }
    }

    func stopMonitoringChanges() {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }

    private func ensureAuthorized() throws {
        refreshAuthorizationStatus()
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
    }
}
