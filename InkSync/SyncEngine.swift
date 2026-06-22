import Foundation
import Combine

@MainActor
final class SyncEngine: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date?
    @Published var nextSyncTime: Date?
    @Published var currentSyncDevice: Device?
    @Published var syncProgress: String = ""

    private let eventKitManager: EventKitManager
    private let apiClient: APIClient
    private let mappingManager: MappingManager
    private let notificationManager: NotificationManager
    private let syncLogStore: SyncLogStore

    private var syncTimer: Timer?
    private let pollingInterval: TimeInterval = 300

    private var conflictStrategy: ConflictStrategy {
        let rawValue = UserDefaults.standard.string(forKey: "conflictStrategy") ?? ConflictStrategy.timestampPriority.rawValue
        return ConflictStrategy(rawValue: rawValue) ?? .timestampPriority
    }

    init(
        eventKitManager: EventKitManager,
        apiClient: APIClient,
        mappingManager: MappingManager,
        notificationManager: NotificationManager = .shared,
        syncLogStore: SyncLogStore = SyncLogStore()
    ) {
        self.eventKitManager = eventKitManager
        self.apiClient = apiClient
        self.mappingManager = mappingManager
        self.notificationManager = notificationManager
        self.syncLogStore = syncLogStore

        lastSyncTime = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date
        updateNextSyncTime()
    }

    deinit {
        syncTimer?.invalidate()
    }

    func startPolling() {
        stopPolling()
        syncTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll()
            }
        }
    }

    func stopPolling() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncProgress = "开始同步..."

        for device in mappingManager.devices {
            currentSyncDevice = device
            syncProgress = "同步 \(device.alias)..."

            do {
                try await sync(device: device)
            } catch {
                handleError(error, device: device)
            }
        }

        currentSyncDevice = nil
        lastSyncTime = Date()
        UserDefaults.standard.set(lastSyncTime, forKey: "lastSyncTime")
        updateNextSyncTime()

        isSyncing = false
        syncProgress = "同步完成"
    }

    func sync(device: Device) async throws {
        let listIds = mappingManager.config.lists(for: device.id)
        guard !listIds.isEmpty else {
            let record = SyncRecord(
                id: UUID(),
                timestamp: Date(),
                deviceId: device.id,
                type: .noChange,
                details: "该设备未分配任何列表",
                itemCount: 0
            )
            syncLogStore.addRecord(record)
            return
        }

        let localReminders = await eventKitManager.fetchReminders(from: listIds)
        let calendarNames = Dictionary(
            uniqueKeysWithValues: eventKitManager.fetchCalendars().map { ($0.calendarIdentifier, $0.title) }
        )
        let localTodos = localReminders.map { reminder -> TodoItem in
            let listId = reminder.calendar.calendarIdentifier
            let listName = calendarNames[listId] ?? reminder.calendar.title
            return reminder.toTodoItem(listId: listId, listName: listName)
        }

        syncProgress = "获取 \(device.alias) 远程数据..."
        var remoteTodos: [TodoItem] = []
        do {
            remoteTodos = try await apiClient.fetchTodos(deviceId: device.id, status: nil)
        } catch {
            throw error
        }

        syncProgress = "计算差异..."
        let diff = calculateDiff(local: localTodos, remote: remoteTodos)

        if !diff.hasChanges {
            let record = SyncRecord(
                id: UUID(),
                timestamp: Date(),
                deviceId: device.id,
                type: .noChange,
                details: "无变更",
                itemCount: 0
            )
            syncLogStore.addRecord(record)
            notificationManager.notifySyncCompleted(device: device, itemCount: 0)
            return
        }

        let conflicts = detectConflicts(local: localTodos, remote: remoteTodos, lastSyncTime: lastSyncTime)
        let resolved = resolveConflicts(conflicts, strategy: conflictStrategy)

        let localByTitle = Dictionary(grouping: localTodos, by: { $0.title.lowercased() })
            .mapValues { $0.first! }
        let remoteByTitle = Dictionary(grouping: remoteTodos, by: { $0.title.lowercased() })
            .mapValues { $0.first! }

        syncProgress = "拉取远程变更到 \(device.alias)..."
        var pulledCount = 0
        var pullErrors: [String] = []
        let targetListId = listIds.first
        for todo in remoteTodos {
            do {
                let key = todo.title.lowercased()
                if let existing = localByTitle[key] {
                    if existing.cloudId != todo.id {
                        CloudIdStore.shared.setCloudId(todo.id, for: existing.id)
                    }
                    if !existing.isCompleted && todo.isCompleted {
                        try await eventKitManager.setCompleted(true, forReminderId: existing.id)
                        pulledCount += 1
                    }
                } else if !todo.isCompleted, let targetListId {
                    var fixed = todo
                    fixed = TodoItem(
                        id: todo.id,
                        title: todo.title,
                        notes: todo.notes,
                        isCompleted: todo.isCompleted,
                        dueDate: todo.dueDate,
                        dueTime: todo.dueTime,
                        priority: todo.priority,
                        listId: targetListId,
                        listName: todo.listName,
                        lastModified: todo.lastModified,
                        source: todo.source
                    )
                    try await eventKitManager.saveTodo(fixed)
                    pulledCount += 1
                }
            } catch {
                pullErrors.append("\(todo.title): \(error.localizedDescription)")
            }
        }

        let refreshedLocalReminders = await eventKitManager.fetchReminders(from: listIds)
        let refreshedLocalTodos = refreshedLocalReminders.map { reminder -> TodoItem in
            let lid = reminder.calendar.calendarIdentifier
            var item = reminder.toTodoItem(listId: lid, listName: calendarNames[lid] ?? reminder.calendar.title)
            item.cloudId = CloudIdStore.shared.cloudId(for: item.id)
            return item
        }
        let refreshedLocalByTitle = Dictionary(grouping: refreshedLocalTodos, by: { $0.title.lowercased() })
            .mapValues { $0.first! }
        let remoteByCloudId = Dictionary(
            refreshedLocalTodos.compactMap { todo -> (String, TodoItem)? in
                guard let cid = todo.cloudId else { return nil }
                if let remote = remoteTodos.first(where: { $0.id == cid }) {
                    return (cid, remote)
                }
                return nil
            },
            uniquingKeysWith: { first, _ in first }
        )

        syncProgress = "推送本地变更到 \(device.alias)..."
        var pushedCount = 0
        var pushErrors: [String] = []
        var adoptedCloudIds: Set<String> = []
        for todo in refreshedLocalTodos {
            do {
                if let cid = todo.cloudId, let existing = remoteByCloudId[cid] {
                    let onlyCompletionChanged = existing.isCompleted != todo.isCompleted
                        && existing.title == todo.title
                        && existing.notes == todo.notes
                        && existing.dueDate == todo.dueDate
                        && existing.priority == todo.priority
                    if onlyCompletionChanged {
                        try await apiClient.markComplete(todoId: existing.id, completed: todo.isCompleted)
                        pushedCount += 1
                    } else {
                        let otherChanged = existing.title != todo.title
                            || existing.notes != todo.notes
                            || existing.dueDate != todo.dueDate
                            || existing.priority != todo.priority
                        if otherChanged {
                            let updated = TodoItem(
                                id: existing.id,
                                title: todo.title,
                                notes: todo.notes,
                                isCompleted: todo.isCompleted,
                                dueDate: todo.dueDate,
                                dueTime: todo.dueTime,
                                priority: todo.priority,
                                listId: todo.listId,
                                listName: todo.listName,
                                lastModified: todo.lastModified,
                                source: todo.source
                            )
                            _ = try await apiClient.updateTodo(updated)
                            pushedCount += 1
                            try await apiClient.markComplete(todoId: existing.id, completed: todo.isCompleted)
                        }
                    }
                } else if let existing = remoteByTitle[todo.title.lowercased()],
                          !adoptedCloudIds.contains(existing.id) {
                    CloudIdStore.shared.setCloudId(existing.id, for: todo.id)
                    adoptedCloudIds.insert(existing.id)
                    if existing.isCompleted != todo.isCompleted {
                        try await apiClient.markComplete(todoId: existing.id, completed: todo.isCompleted)
                    }
                    pushedCount += 1
                } else {
                    let created = try await apiClient.createTodo(todo, deviceId: device.id)
                    CloudIdStore.shared.setCloudId(created.id, for: todo.id)
                    pushedCount += 1
                }
            } catch {
                pushErrors.append("\(todo.title): \(error.localizedDescription)")
            }
        }

        let totalChanges = pushedCount + pulledCount + resolved.count
        let recordType: SyncRecordType = conflicts.isEmpty ? (pushedCount > 0 ? .push : .pull)
            : (conflicts.isEmpty == false ? .conflict : .noChange)

        var details = buildDetails(pushed: pushedCount, pulled: pulledCount, resolved: conflicts.count)
        if !pushErrors.isEmpty {
            details += "\n推送失败:\n" + pushErrors.prefix(5).joined(separator: "\n")
        }
        if !pullErrors.isEmpty {
            details += "\n拉取失败:\n" + pullErrors.prefix(5).joined(separator: "\n")
        }

        let record = SyncRecord(
            id: UUID(),
            timestamp: Date(),
            deviceId: device.id,
            type: recordType,
            details: details,
            itemCount: totalChanges
        )
        syncLogStore.addRecord(record)

        if !conflicts.isEmpty {
            notificationManager.notifyConflictResolved(device: device, count: resolved.count)
        } else {
            notificationManager.notifySyncCompleted(device: device, itemCount: totalChanges)
        }
    }

    private func handleError(_ error: Error, device: Device) {
        let record = SyncRecord(
            id: UUID(),
            timestamp: Date(),
            deviceId: device.id,
            type: .failure,
            details: error.localizedDescription,
            itemCount: 0
        )
        syncLogStore.addRecord(record)
        notificationManager.notifySyncFailed(device: device, error: error)
    }

    private func updateNextSyncTime() {
        nextSyncTime = Date().addingTimeInterval(pollingInterval)
    }

    private func buildDetails(pushed: Int, pulled: Int, resolved: Int) -> String {
        var parts: [String] = []
        if pushed > 0 { parts.append("推送\(pushed)") }
        if pulled > 0 { parts.append("拉取\(pulled)") }
        if resolved > 0 { parts.append("解决冲突\(resolved)") }
        return parts.isEmpty ? "无变更" : parts.joined(separator: ", ")
    }
}