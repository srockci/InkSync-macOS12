import Foundation

final class RecurringGenerationLogger {
    static let shared = RecurringGenerationLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "RecurringGenerationLogger", qos: .utility)
    private let retentionDays: Int = 30

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("InkSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("recurring_generation_logs.json")
    }

    func loadAll() -> [GenerationLog] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let logs = try? JSONDecoder().decode([GenerationLog].self, from: data) else {
                return []
            }
            return logs
        }
    }

    func append(_ log: GenerationLog) {
        var all = loadAll()
        all.insert(log, at: 0)
        pruneOldLogs(&all)
        saveAll(all)
    }

    func update(_ log: GenerationLog) {
        var all = loadAll()
        if let index = all.firstIndex(where: { $0.id == log.id }) {
            all[index] = log
            saveAll(all)
        }
    }

    func logs(for ruleId: UUID) -> [GenerationLog] {
        loadAll().filter { $0.ruleId == ruleId }
    }

    func clearAll() {
        saveAll([])
    }

    private func pruneOldLogs(_ logs: inout [GenerationLog]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        logs.removeAll { $0.actualTime < cutoff }
    }

    private func saveAll(_ logs: [GenerationLog]) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(logs) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}