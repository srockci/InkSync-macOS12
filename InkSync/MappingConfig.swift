import Foundation

struct MappingConfig: Codable {
    var deviceToLists: [String: [String]]
    var listToDevice: [String: String]

    init(deviceToLists: [String: [String]] = [:], listToDevice: [String: String] = [:]) {
        self.deviceToLists = deviceToLists
        self.listToDevice = listToDevice
    }

    func lists(for deviceId: String) -> [String] {
        return deviceToLists[deviceId] ?? []
    }

    func device(for listId: String) -> String? {
        return listToDevice[listId]
    }

    mutating func addMapping(deviceId: String, listId: String) {
        if let oldDevice = listToDevice[listId], oldDevice != deviceId {
            deviceToLists[oldDevice]?.removeAll { $0 == listId }
        }

        if deviceToLists[deviceId] == nil {
            deviceToLists[deviceId] = []
        }
        if !deviceToLists[deviceId]!.contains(listId) {
            deviceToLists[deviceId]!.append(listId)
        }

        listToDevice[listId] = deviceId
    }

    mutating func removeMapping(deviceId: String, listId: String) {
        deviceToLists[deviceId]?.removeAll { $0 == listId }
        if deviceToLists[deviceId]?.isEmpty == true {
            deviceToLists.removeValue(forKey: deviceId)
        }
        listToDevice.removeValue(forKey: listId)
    }

    func unassignedLists(allListIds: [String]) -> [String] {
        return allListIds.filter { listToDevice[$0] == nil }
    }
}