import Foundation

final class RecurringReminderStore {
    static let shared = RecurringReminderStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "RecurringReminderStore", qos: .utility)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("InkSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("recurring_reminders.json")
    }

    func loadAll() -> [RecurringReminder] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let rules = try? JSONDecoder().decode([RecurringReminder].self, from: data) else {
                return []
            }
            return rules
        }
    }

    func saveAll(_ rules: [RecurringReminder]) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(rules) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func add(_ rule: RecurringReminder) {
        var all = loadAll()
        all.append(rule)
        saveAll(all)
    }

    func update(_ rule: RecurringReminder) {
        var all = loadAll()
        if let index = all.firstIndex(where: { $0.id == rule.id }) {
            all[index] = rule
            saveAll(all)
        }
    }

    func delete(_ id: UUID) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        saveAll(all)
    }

    func deleteMany(_ ids: [UUID]) {
        var all = loadAll()
        all.removeAll { ids.contains($0.id) }
        saveAll(all)
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        var all = loadAll()
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index].isEnabled = enabled
            all[index].updatedAt = Date()
            saveAll(all)
        }
    }
}