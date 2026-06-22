import Foundation

final class SyncLogStore {
    private let fileManager = FileManager.default
    private var logFileURL: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let inkSyncDir = appSupport.appendingPathComponent("InkSync", isDirectory: true)

        try? fileManager.createDirectory(at: inkSyncDir, withIntermediateDirectories: true)

        logFileURL = inkSyncDir.appendingPathComponent("sync_logs.json")
    }

    func addRecord(_ record: SyncRecord) {
        var records = fetchAllRecords()
        records.insert(record, at: 0)
        records = pruneOldRecords(records)
        saveRecords(records)
    }

    func fetchRecords(from startDate: Date, to endDate: Date) -> [SyncRecord] {
        return fetchAllRecords().filter { record in
            record.timestamp >= startDate && record.timestamp <= endDate
        }
    }

    func fetchTodayRecords() -> [SyncRecord] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return fetchRecords(from: startOfDay, to: endOfDay)
    }

    func fetchAllRecords() -> [SyncRecord] {
        guard fileManager.fileExists(atPath: logFileURL.path),
              let data = try? Data(contentsOf: logFileURL),
              let records = try? JSONDecoder().decode([SyncRecord].self, from: data) else {
            return []
        }
        return records
    }

    func exportToCSV() -> URL? {
        let records = fetchAllRecords()
        var csv = "ID,Timestamp,DeviceID,Type,Details,ItemCount\n"

        let dateFormatter = ISO8601DateFormatter()

        for record in records {
            let timestamp = dateFormatter.string(from: record.timestamp)
            let escapedDetails = record.details.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(record.id),\(timestamp),\(record.deviceId),\(record.type.rawValue),\"\(escapedDetails)\",\(record.itemCount)\n"
        }

        let tempDir = fileManager.temporaryDirectory
        let csvURL = tempDir.appendingPathComponent("sync_export_\(Int(Date().timeIntervalSince1970)).csv")

        do {
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
            return csvURL
        } catch {
            return nil
        }
    }

    private func saveRecords(_ records: [SyncRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: logFileURL, options: .atomic)
    }

    private func pruneOldRecords(_ records: [SyncRecord]) -> [SyncRecord] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return records.filter { $0.timestamp >= thirtyDaysAgo }
    }
}