import SwiftUI

struct SyncLogView: View {
    @State private var logStore = SyncLogStore()
    @State private var showAllRecords = false
    @State private var exportURL: URL?
    @State private var showingExportSuccess = false
    @State private var refreshTrigger: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logList
            Divider()
            footerButtons
        }
        .frame(width: 480, height: 500)
        .onAppear {
            logStore = SyncLogStore()
            refreshTrigger += 1
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            refreshTrigger += 1
        }
        .alert("导出成功", isPresented: $showingExportSuccess) {
            Button("打开文件") {
                if let url = exportURL {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("关闭", role: .cancel) {}
        } message: {
            Text("同步日志已导出到桌面")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("同步记录")
                    .font(.headline)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("显示全部", isOn: $showAllRecords)
                .toggleStyle(.switch)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        if !showAllRecords {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M月d日"
            let today = logStore.fetchTodayRecords()
            return "\(dateFormatter.string(from: Date())) - \(today.count) 条记录"
        } else {
            return "全部历史记录"
        }
    }

    private var logList: some View {
        let records = showAllRecords ? logStore.fetchAllRecords() : logStore.fetchTodayRecords()
        let _ = refreshTrigger

        return Group {
            if records.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无同步记录")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedRecords(records), id: \.0) { dateKey, dayRecords in
                            Section {
                                ForEach(dayRecords) { record in
                                    SyncRecordRow(record: record)
                                }
                            } header: {
                                Text(dateKey)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                    }
                }
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            Spacer()

            Button("导出日志...") {
                exportLog()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func groupedRecords(_ records: [SyncRecord]) -> [(String, [SyncRecord])] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let grouped = Dictionary(grouping: records) { record in
            dateFormatter.string(from: record.timestamp)
        }

        return grouped.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    private func exportLog() {
        if let url = logStore.exportToCSV() {
            exportURL = url
            let destURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: destURL)
            showingExportSuccess = true
        }
    }
}

struct SyncRecordRow: View {
    let record: SyncRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                typeIcon

                Text(typeLabel)
                    .font(.caption)
                    .foregroundStyle(typeColor)

                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                if record.itemCount > 0 {
                    Text("\(record.itemCount) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !record.details.isEmpty && record.details != "无变更" {
                Text(record.details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 58)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.timestamp)
    }

    private var typeIcon: Image {
        switch record.type {
        case .push:
            return Image(systemName: "arrow.up.circle.fill")
        case .pull:
            return Image(systemName: "arrow.down.circle.fill")
        case .conflict:
            return Image(systemName: "exclamationmark.triangle.fill")
        case .noChange:
            return Image(systemName: "checkmark.circle.fill")
        case .failure:
            return Image(systemName: "xmark.circle.fill")
        }
    }

    private var typeLabel: String {
        switch record.type {
        case .push:
            return "推送"
        case .pull:
            return "拉取"
        case .conflict:
            return "冲突"
        case .noChange:
            return "无变更"
        case .failure:
            return "失败"
        }
    }

    private var typeColor: Color {
        switch record.type {
        case .push:
            return .blue
        case .pull:
            return .green
        case .conflict:
            return .orange
        case .noChange:
            return .secondary
        case .failure:
            return .red
        }
    }

    private var deviceName: String {
        return record.deviceId
    }
}

final class SyncLogWindowController: NSWindowController {
    convenience init() {
        let logView = SyncLogView()
        let hostingController = NSHostingController(rootView: logView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "同步记录"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()

        self.init(window: window)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}