import Foundation

enum SyncRecordType: String, Codable {
    case push
    case pull
    case conflict
    case noChange
    case failure
}

struct SyncRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let deviceId: String
    let type: SyncRecordType
    let details: String
    let itemCount: Int
}

enum ConflictStrategy: String, Codable, CaseIterable {
    case timestampPriority = "timestamp"
    case applePriority = "apple"
    case devicePriority = "device"

    var displayName: String {
        switch self {
        case .timestampPriority: return "时间戳优先"
        case .applePriority: return "Apple Reminders 优先"
        case .devicePriority: return "设备优先"
        }
    }
}

struct DiffResult {
    var toPush: [TodoItem] = []
    var toPull: [TodoItem] = []
    var conflicts: [(local: TodoItem, remote: TodoItem)] = []

    var hasChanges: Bool {
        !toPush.isEmpty || !toPull.isEmpty || !conflicts.isEmpty
    }

    var totalChanges: Int {
        toPush.count + toPull.count + conflicts.count
    }
}

func calculateDiff(local: [TodoItem], remote: [TodoItem]) -> DiffResult {
    let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })

    var result = DiffResult()
    let allIds = Set(localDict.keys).union(remoteDict.keys)

    for id in allIds {
        switch (localDict[id], remoteDict[id]) {
        case (.some(let l), .none):
            result.toPush.append(l)
        case (.none, .some(let r)):
            result.toPull.append(r)
        case (.some(let l), .some(let r)):
            if l.lastModified > r.lastModified {
                result.toPush.append(l)
            } else if r.lastModified > l.lastModified {
                result.toPull.append(r)
            }
        case (.none, .none):
            break
        }
    }

    return result
}

func detectConflicts(local: [TodoItem], remote: [TodoItem], lastSyncTime: Date?) -> [(local: TodoItem, remote: TodoItem)] {
    guard let lastSync = lastSyncTime else { return [] }

    let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })

    var conflicts: [(TodoItem, TodoItem)] = []

    for id in Set(localDict.keys).intersection(remoteDict.keys) {
        if let l = localDict[id], let r = remoteDict[id] {
            if l.lastModified > lastSync && r.lastModified > lastSync {
                conflicts.append((l, r))
            }
        }
    }

    return conflicts
}

func resolveConflicts(_ conflicts: [(local: TodoItem, remote: TodoItem)], strategy: ConflictStrategy) -> [TodoItem] {
    return conflicts.map { local, remote in
        switch strategy {
        case .timestampPriority:
            return local.lastModified > remote.lastModified ? local : remote
        case .applePriority:
            return local
        case .devicePriority:
            return remote
        }
    }
}