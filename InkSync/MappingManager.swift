import Foundation
import EventKit
import Combine

@MainActor
final class MappingManager: ObservableObject {
    @Published var config: MappingConfig
    @Published var availableLists: [EKCalendar] = []
    @Published var devices: [Device] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showSettings = false

    private let eventKitManager: EventKitManager
    private let apiClient: APIClient

    private let configKey = "mappingConfig"

    init(eventKitManager: EventKitManager, apiClient: APIClient) {
        self.eventKitManager = eventKitManager
        self.apiClient = apiClient
        self.config = MappingConfig()
        loadConfig()
    }

    func loadAvailableLists() {
        availableLists = eventKitManager.fetchCalendars()
    }

    func loadDevices() async {
        isLoading = true
        errorMessage = nil

        do {
            devices = try await apiClient.fetchDevices()
        } catch {
            errorMessage = "加载设备失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func assignList(_ listId: String, to deviceId: String) {
        config.addMapping(deviceId: deviceId, listId: listId)
        objectWillChange.send()
        saveConfig()
    }

    func unassignList(_ listId: String, from deviceId: String) {
        config.removeMapping(deviceId: deviceId, listId: listId)
        objectWillChange.send()
        saveConfig()
    }

    func assignedListNames(for deviceId: String) -> [String] {
        let listIds = config.lists(for: deviceId)
        return listIds.compactMap { id in
            availableLists.first { $0.calendarIdentifier == id }?.title
        }
    }

    func availableLists(for deviceId: String) -> [EKCalendar] {
        return availableLists.filter { calendar in
            let assignedDevice = config.device(for: calendar.calendarIdentifier)
            return assignedDevice == nil || assignedDevice == deviceId
        }
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let config = try? JSONDecoder().decode(MappingConfig.self, from: data) {
            self.config = config
        }
    }

    func adaptToListChanges() {
        let currentListIds = availableLists.map { $0.calendarIdentifier }

        for (listId, deviceId) in config.listToDevice {
            if !currentListIds.contains(listId) {
                config.removeMapping(deviceId: deviceId, listId: listId)
            }
        }

        saveConfig()
    }
}