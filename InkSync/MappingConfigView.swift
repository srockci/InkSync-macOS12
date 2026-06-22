import SwiftUI
import EventKit

struct MappingConfigView: View {
    @ObservedObject var mappingManager: MappingManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📟 设备与列表映射")
                .font(.headline)

            if mappingManager.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("加载中...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            } else if let error = mappingManager.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
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

                unassignedListsSection
            }
        }
        .padding()
        .onAppear {
            mappingManager.loadAvailableLists()
            Task {
                await mappingManager.loadDevices()
            }
        }
    }

    private var unassignedListsSection: some View {
        let unassigned = mappingManager.config.unassignedLists(
            allListIds: mappingManager.availableLists.map { $0.calendarIdentifier }
        )

        return Group {
            if !unassigned.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未分配列表")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(unassigned.map { id in
                        mappingManager.availableLists.first { $0.calendarIdentifier == id }?.title ?? id
                    }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.top, 8)
            }
        }
    }
}

struct DeviceMappingRow: View {
    let device: Device
    let assignedLists: [String]
    let availableLists: [EKCalendar]
    let onAssign: (String) -> Void
    let onUnassign: (String) -> Void

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(device.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(device.alias)
                    .font(.subheadline.weight(.medium))

                if let lastSync = device.lastSyncTime {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(lastSync, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                Text("同步列表:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                FlowLayout(spacing: 4) {
                    ForEach(assignedLists, id: \.self) { listId in
                        if let list = availableLists.first(where: { $0.calendarIdentifier == listId }) {
                            ListTag(
                                title: list.title,
                                onRemove: { onUnassign(listId) }
                            )
                        }
                    }

                    Button {
                        showingPicker = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("添加")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("选择列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)

                            if availableLists.isEmpty {
                                Text("暂无可用列表")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(12)
                            } else {
                                ForEach(availableLists, id: \.calendarIdentifier) { list in
                                    Button(list.title) {
                                        onAssign(list.calendarIdentifier)
                                        showingPicker = false
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                        .frame(minWidth: 180)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ListTag: View {
    let title: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .cornerRadius(4)
    }
}

#Preview {
    MappingConfigView(
        mappingManager: MappingManager(
            eventKitManager: EventKitManager(),
            apiClient: MockAPIClient()
        )
    )
    .frame(width: 400, height: 500)
}