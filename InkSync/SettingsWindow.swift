import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var appConfig: AppConfig
    @ObservedObject var mappingManager: MappingManager
    @ObservedObject var syncEngine: SyncEngine
    let apiClient: APIClient
    var onDismiss: () -> Void = {}

    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isVerifying = false

    enum ConnectionStatus {
        case idle, success, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    apiConfigSection
                    deviceMappingSection
                    syncRulesSection
                    notificationPrefsSection
                    recurringSection
                    actionButtons
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 600)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
            Text("设置")
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var apiConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("云端账户", systemImage: "link")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("API 地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://cloud.zectrix.com/open/v1", text: $appConfig.apiURL)
                    .textFieldStyle(.roundedBorder)

                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("输入 API Key", text: $appConfig.apiKey)
                    .textContentType(nil)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("获取设备") {
                        verifyConnection()
                    }
                    .disabled(isVerifying || appConfig.apiKey.isEmpty)

                    if isVerifying {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    switch connectionStatus {
                    case .idle:
                        EmptyView()
                    case .success:
                        Label("正常", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    case .failed(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var deviceMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("设备与列表映射", systemImage: "rectangle.connected.to.line.below")
                .font(.headline)

            if mappingManager.devices.isEmpty {
                HStack {
                    ProgressView()
                    Text("加载设备中...")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ForEach(mappingManager.devices) { device in
                    DeviceMappingRow(
                        device: device,
                        assignedLists: mappingManager.config.lists(for: device.id),
                        availableLists: mappingManager.availableLists(for: device.id),
                        onAssign: { mappingManager.assignList($0, to: device.id) },
                        onUnassign: { mappingManager.unassignList($0, from: device.id) }
                    )
                }

                let unassigned = mappingManager.config.unassignedLists(
                    allListIds: mappingManager.availableLists.map { $0.calendarIdentifier }
                )
                if !unassigned.isEmpty {
                    let unassignedNames = unassigned.compactMap { id in
                        mappingManager.availableLists.first { $0.calendarIdentifier == id }?.title
                    }.joined(separator: ", ")
                    Text("未分配列表: \(unassignedNames)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var syncRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("同步规则", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("冲突解决策略")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(ConflictStrategy.allCases, id: \.self) { strategy in
                    HStack {
                        RadioButton(
                            title: strategy.displayName,
                            isSelected: appConfig.conflictStrategy == strategy
                        ) {
                            appConfig.conflictStrategy = strategy
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var notificationPrefsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("通知偏好", systemImage: "bell")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("同步成功通知", isOn: $appConfig.notifyOnSuccess)
                Toggle("同步失败通知", isOn: $appConfig.notifyOnFailure)
                Toggle("冲突解决通知", isOn: $appConfig.notifyOnConflict)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var recurringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("周期备忘", systemImage: "arrow.clockwise.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("补发窗口（小时）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Stepper(value: $appConfig.recurringCatchUpHours, in: 0...168, step: 12) {
                        Text("\(appConfig.recurringCatchUpHours) 小时")
                            .frame(width: 80, alignment: .leading)
                    }
                    Text(catchUpHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("当 Mac 长时间休眠/关机后唤醒时，自动补发窗口内错过的周期备忘。设为 0 关闭补发。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private var catchUpHint: String {
        switch appConfig.recurringCatchUpHours {
        case 0: return "已关闭"
        case 1..<24: return "约 \(appConfig.recurringCatchUpHours) 小时"
        case 24: return "1 天"
        case 48: return "2 天"
        case 72: return "3 天（推荐）"
        case 96: return "4 天"
        case 120: return "5 天"
        case 144: return "6 天"
        case 168: return "7 天（上限）"
        default:
            let days = appConfig.recurringCatchUpHours / 24
            let hours = appConfig.recurringCatchUpHours % 24
            if hours == 0 { return "\(days) 天" }
            return "\(days) 天 \(hours) 小时"
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("保存并立即生效") {
                saveAndApply()
            }
            .buttonStyle(.borderedProminent)

            Button("重置同步记录") {
                appConfig.resetSyncRecords()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private func verifyConnection() {
        isVerifying = true
        connectionStatus = .idle

        Task {
            let client = RealAPIClient(apiKey: appConfig.apiKey)
            do {
                let devices = try await client.fetchDevices()
                await MainActor.run {
                    mappingManager.devices = devices
                    connectionStatus = devices.isEmpty
                        ? .failed("未获取到设备")
                        : .success
                    isVerifying = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed("获取失败: \(error.localizedDescription)")
                    isVerifying = false
                }
            }
        }
    }

    private func saveAndApply() {
        mappingManager.saveConfig()
        syncEngine.stopPolling()
        syncEngine.startPolling()
        onDismiss()
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsDeviceMappingRow: View {
    let device: Device
    let assignedLists: [String]
    let availableLists: [EKCalendar]
    let onAssign: (String) -> Void
    let onUnassign: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(device.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(device.alias)
                    .font(.subheadline.weight(.medium))

                Spacer()

                if device.isOnline {
                    Text("在线")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("离线")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Text("同步:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)

                FlowLayout(spacing: 4) {
                    ForEach(assignedLists, id: \.self) { listId in
                        if let list = availableLists.first(where: { $0.calendarIdentifier == listId }) {
                            HStack(spacing: 4) {
                                Text(list.title)
                                    .font(.caption)
                                Button(action: { onUnassign(listId) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }

                    Menu {
                        ForEach(availableLists, id: \.calendarIdentifier) { list in
                            Button(list.title) {
                                onAssign(list.calendarIdentifier)
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("添加")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init(
        appConfig: AppConfig,
        mappingManager: MappingManager,
        syncEngine: SyncEngine,
        apiClient: APIClient
    ) {
        let window = NSWindow()
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable]

        let settingsView = SettingsView(
            appConfig: appConfig,
            mappingManager: mappingManager,
            syncEngine: syncEngine,
            apiClient: apiClient,
            onDismiss: { [weak window] in
                window?.close()
            }
        )

        let hostingController = NSHostingController(rootView: settingsView)
        window.contentViewController = hostingController
        window.center()

        self.init(window: window)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}