import Foundation
import CryptoKit

final class SecureStorage {
    static let shared = SecureStorage()

    private let key: SymmetricKey
    private let fileURL: URL

    init() {
        let keyData = Self.deriveKey()
        self.key = SymmetricKey(data: keyData)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("InkSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("secrets.dat")
    }

    private static func deriveKey() -> Data {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.inksync.app"
        let salt = "InkSync.v1".data(using: .utf8)!
        let inputKey = SymmetricKey(data: bundleId.data(using: .utf8)!)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: inputKey, salt: salt, outputByteCount: 32).withUnsafeBytes { Data($0) }
    }

    func save(_ value: String, forKey key: String) {
        var all = readAll()
        all[key] = value
        writeAll(all)
    }

    func get(_ key: String) -> String? {
        readAll()[key]
    }

    func delete(_ key: String) {
        var all = readAll()
        all.removeValue(forKey: key)
        writeAll(all)
    }

    private struct Blob: Codable {
        var items: [String: String]
    }

    private func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let sealed = try? ChaChaPoly.SealedBox(combined: data),
              let plaintext = try? ChaChaPoly.open(sealed, using: key),
              let blob = try? JSONDecoder().decode(Blob.self, from: plaintext) else {
            return [:]
        }
        return blob.items
    }

    private func writeAll(_ items: [String: String]) {
        guard let plaintext = try? JSONEncoder().encode(Blob(items: items)),
              let sealed = try? ChaChaPoly.seal(plaintext, using: key) else {
            return
        }
        try? sealed.combined.write(to: fileURL, options: .atomic)
    }
}