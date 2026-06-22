import Foundation

final class CloudIdStore {
    static let shared = CloudIdStore()

    private let key = "cloudIdMap"
    private let queue = DispatchQueue(label: "CloudIdStore", qos: .utility)
    private var cache: [String: String] = [:]

    private init() {
        load()
    }

    func cloudId(for localId: String) -> String? {
        queue.sync { cache[localId] }
    }

    func setCloudId(_ cloudId: String, for localId: String) {
        queue.sync {
            cache[localId] = cloudId
            save()
        }
    }

    func remove(localId: String) {
        queue.sync {
            cache.removeValue(forKey: localId)
            save()
        }
    }

    func clear() {
        queue.sync {
            cache.removeAll()
            save()
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}