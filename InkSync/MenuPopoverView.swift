import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var eventKitManager: EventKitManager
    @ObservedObject var mappingManager: MappingManager
    @ObservedObject var syncEngine: SyncEngine
    @ObservedObject var recurringEngine: RecurringEngine
    var onSyncNow: () -> Void
    var onViewSyncLog: () -> Void
    var onOpenRecurringManager: () -> Void
    var onOpenRecurringLog: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if eventKitManager.isAccessDenied {
                permissionDeniedBanner
                Divider()
            }

            statusSection
            Divider()
            deviceSection
            Divider()
            actionButtons
            recurringSection
            footer
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await mappingManager.loadDevices()
        }
        .task {
            recurringEngine.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: syncEngine.isSyncing ? "hexagon.fill" : "hexagon")
                .foregroundStyle(syncEngine.isSyncing ? Color.accentColor : .secondary)
                .animation(.easeInOut(duration: 0.3), value: syncEngine.isSyncing)

            Text("InkSync")
                .font(.headline)

            Spacer()

            if syncEngine.isSyncing {
                Text(syncEngine.syncProgress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .id(syncEngine.syncProgress)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                Text(appState.statusDescription)
                    .font(.subheadline)
            }

            if let nextSync = syncEngine.nextSyncTime {
                Text("下次同步: \(nextSyncTimeText(nextSync))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var statusIcon: some View {
        Group {
            switch appState.syncStatus {
            case .idle:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .syncing:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            case .conflict:
                Image(systemName: "circle.badge.plus")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var permissionDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("无法访问提醒事项")
                    .font(.subheadline.weight(.medium))
            }

            Text("InkSync 需要访问「提醒事项」才能同步待办。请在系统设置中开启权限。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("打开系统设置") {
                SystemSettings.openRemindersPrivacy()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📟 设备 (\(mappingManager.devices.count)台)")
                .font(.subheadline.weight(.medium))

            ForEach(mappingManager.devices) { device in
                DeviceMappingPopoverRow(
                    device: device,
                    assignedListNames: mappingManager.assignedListNames(for: device.id)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onSyncNow) {
                HStack {
                    if syncEngine.isSyncing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                    Text(syncEngine.isSyncing ? "同步中..." : "立即同步")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(syncEngine.isSyncing)

            Button(action: onViewSyncLog) {
                Text("查看记录")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var recurringSection: some View {
        HStack {
            Button {
                onOpenRecurringManager()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                    Text("周期备忘")
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Spacer()

            if recurringEngine.todayGeneratedCount > 0 {
                Text("今日: \(recurringEngine.todayGeneratedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Button("设置...", action: onOpenSettings)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

            Spacer()

            Button("退出 InkSync", action: onQuit)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func nextSyncTimeText(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = Locale.current
        relativeFormatter.unitsStyle = .abbreviated

        let time = timeFormatter.string(from: date)
        let relative = relativeFormatter.localizedString(for: date, relativeTo: Date())

        return "\(time) (\(relative))"
    }
}

private struct DeviceMappingPopoverRow: View {
    let device: Device
    let assignedListNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("├──")
                    .foregroundStyle(.tertiary)
                    .font(.caption)

                Text(device.alias)
                    .font(.subheadline)

                if device.isOnline {
                    Text("✅")
                        .font(.caption)
                }

                Spacer()

                if let lastSync = device.lastSyncTime {
                    Text(relativeSyncText(lastSync))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                Text("│   └─ 同步: ")
                    .foregroundStyle(.tertiary)
                    .font(.caption)

                if assignedListNames.isEmpty {
                    Text("未分配")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(assignedListNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 8)
        }
    }

    private func relativeSyncText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    MenuPopoverView(
        appState: AppState(),
        eventKitManager: EventKitManager(),
        mappingManager: MappingManager(eventKitManager: EventKitManager(), apiClient: MockAPIClient()),
        syncEngine: SyncEngine(
            eventKitManager: EventKitManager(),
            apiClient: MockAPIClient(),
            mappingManager: MappingManager(eventKitManager: EventKitManager(), apiClient: MockAPIClient())
        ),
        recurringEngine: RecurringEngine(
            eventKitManager: EventKitManager(),
            mappingManager: MappingManager(eventKitManager: EventKitManager(), apiClient: MockAPIClient())
        ),
        onSyncNow: {},
        onViewSyncLog: {},
        onOpenRecurringManager: {},
        onOpenRecurringLog: {},
        onOpenSettings: {},
        onQuit: {}
    )
    .frame(width: 320, height: 460)
}