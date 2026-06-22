import Foundation

final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    private let defaults = UserDefaults.standard
    private let apiURLKey = "apiURL"
    private let apiKeyKey = "apiKey"
    private let conflictStrategyKey = "conflictStrategy"
    private let notifyOnSuccessKey = "notifyOnSuccess"
    private let notifyOnFailureKey = "notifyOnFailure"
    private let notifyOnConflictKey = "notifyOnConflict"
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let lastSyncTimeKey = "lastSyncTime"
    private let recurringCatchUpHoursKey = "recurringCatchUpHours"

    @Published var apiURL: String {
        didSet {
            defaults.set(apiURL, forKey: apiURLKey)
        }
    }

    @Published var apiKey: String {
        didSet {
            if apiKey.isEmpty {
                SecureStorage.shared.delete("apiKey")
            } else {
                SecureStorage.shared.save(apiKey, forKey: "apiKey")
            }
        }
    }

    @Published var conflictStrategy: ConflictStrategy {
        didSet {
            defaults.set(conflictStrategy.rawValue, forKey: conflictStrategyKey)
        }
    }

    @Published var notifyOnSuccess: Bool {
        didSet {
            defaults.set(notifyOnSuccess, forKey: notifyOnSuccessKey)
        }
    }

    @Published var notifyOnFailure: Bool {
        didSet {
            defaults.set(notifyOnFailure, forKey: notifyOnFailureKey)
        }
    }

    @Published var notifyOnConflict: Bool {
        didSet {
            defaults.set(notifyOnConflict, forKey: notifyOnConflictKey)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: hasCompletedOnboardingKey)
        }
    }

    var lastSyncTime: Date? {
        get { defaults.object(forKey: lastSyncTimeKey) as? Date }
        set { defaults.set(newValue, forKey: lastSyncTimeKey) }
    }

    @Published var recurringCatchUpHours: Int {
        didSet {
            let clamped = max(0, min(168, recurringCatchUpHours))
            if clamped != recurringCatchUpHours {
                recurringCatchUpHours = clamped
                return
            }
            defaults.set(clamped, forKey: recurringCatchUpHoursKey)
        }
    }

    private init() {
        self.apiURL = defaults.string(forKey: apiURLKey) ?? "https://cloud.zectrix.com/open/v1"
        self.apiKey = SecureStorage.shared.get("apiKey") ?? ""

        let strategyRaw = defaults.string(forKey: conflictStrategyKey) ?? ConflictStrategy.timestampPriority.rawValue
        self.conflictStrategy = ConflictStrategy(rawValue: strategyRaw) ?? .timestampPriority

        self.notifyOnSuccess = defaults.object(forKey: notifyOnSuccessKey) as? Bool ?? true
        self.notifyOnFailure = defaults.object(forKey: notifyOnFailureKey) as? Bool ?? true
        self.notifyOnConflict = defaults.object(forKey: notifyOnConflictKey) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: hasCompletedOnboardingKey)
        let stored = defaults.object(forKey: recurringCatchUpHoursKey) as? Int ?? 72
        self.recurringCatchUpHours = max(0, min(168, stored))
    }

    func resetToDefaults() {
        apiURL = "https://cloud.zectrix.com/open/v1"
        apiKey = ""
        conflictStrategy = .timestampPriority
        notifyOnSuccess = true
        notifyOnFailure = true
        notifyOnConflict = true
        recurringCatchUpHours = 72
    }

    func resetSyncRecords() {
        let logStore = SyncLogStore()
        let records = logStore.fetchAllRecords()
        for record in records {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let logFile = appSupport.appendingPathComponent("InkSync/sync_logs.json")
            try? fileManager.removeItem(at: logFile)
        }
    }
}