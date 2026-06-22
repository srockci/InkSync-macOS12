import Foundation

enum SyncStatus {
    case idle
    case syncing
    case failed
    case conflict
}

struct Device: Identifiable, Codable {
    let id: String
    let alias: String
    let lastSyncTime: Date?
    let isOnline: Bool
    let syncedLists: [String]
}

@MainActor
final class AppState: ObservableObject {
    @Published var syncStatus: SyncStatus = .idle
    @Published var nextSyncTime: Date?
    @Published var devices: [Device] = [
        Device(
            id: "dev1",
            alias: "书房墨水屏",
            lastSyncTime: Date().addingTimeInterval(-120),
            isOnline: true,
            syncedLists: ["工作", "个人"]
        ),
        Device(
            id: "dev2",
            alias: "办公室墨水屏",
            lastSyncTime: Date().addingTimeInterval(-300),
            isOnline: true,
            syncedLists: ["家庭"]
        )
    ]

    init() {
        nextSyncTime = Date().addingTimeInterval(180)
    }

    var onlineDeviceCount: Int {
        devices.filter(\.isOnline).count
    }

    var statusDescription: String {
        switch syncStatus {
        case .idle:
            return "✅ 正常运行"
        case .syncing:
            return "🔄 同步中..."
        case .failed:
            return "⚠️ 同步失败"
        case .conflict:
            return "• 存在冲突"
        }
    }
}
