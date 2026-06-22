import SwiftUI
import AppKit

struct RecurringLogView: View {
    @State private var logs: [GenerationLog] = []
    @State private var filterTarget: FilterTarget = .all
    @State private var filterMonth: Date = Date()

    enum FilterTarget: String, CaseIterable, Identifiable {
        case all, success, failed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部"
            case .success: return "成功"
            case .failed: return "失败"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 480)
        .onAppear { reload() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
    }

    private var header: some View {
        HStack {
            Text("周期备忘生成日志")
                .font(.headline)
            Spacer()
            HStack {
                Picker("状态", selection: $filterTarget) {
                    ForEach(FilterTarget.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 110)

                DatePicker("日期", selection: $filterMonth, displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 120)

                Button("导出日志") { exportLogs() }
            }
        }
        .padding(16)
        .onChange(of: filterTarget) { _ in reload() }
        .onChange(of: filterMonth) { _ in reload() }
    }

    private var content: some View {
        Group {
            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("暂无日志")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLogs) { log in
                            LogRowView(log: log)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("今日生成: \(todayCount) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("成功: \(successCount)")
                .font(.caption)
                .foregroundStyle(.green)
            Text("失败: \(failedCount)")
                .font(.caption)
                .foregroundStyle(.red)
            Text("补发: \(catchupCount)")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("待重试: \(retryCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var filteredLogs: [GenerationLog] {
        logs.filter { log in
            let calendar = Calendar.current
            let logMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: log.actualTime)) ?? Date()
            let filterMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: filterMonth)) ?? Date()
            guard logMonth == filterMonthStart else { return false }

            switch filterTarget {
            case .all: return true
            case .success: return log.success
            case .failed: return !log.success
            }
        }
    }

    private var todayCount: Int {
        logs.filter { Calendar.current.isDateInToday($0.actualTime) }.count
    }

    private var successCount: Int {
        logs.filter { $0.success }.count
    }

    private var failedCount: Int {
        logs.filter { !$0.success }.count
    }

    private var catchupCount: Int {
        logs.filter { $0.isCatchup }.count
    }

    private var retryCount: Int { 0 }

    private func reload() {
        logs = RecurringGenerationLogger.shared.loadAll()
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "recurring_logs.csv"
        let csv = generateCSV()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func generateCSV() -> String {
        var lines = ["时间,规则标题,状态,补发,错误信息"]
        for log in logs {
            let time = ISO8601DateFormatter().string(from: log.actualTime)
            let escapedTitle = log.ruleTitle.replacingOccurrences(of: ",", with: ";")
            let status = log.success ? "成功" : "失败"
            let catchup = log.isCatchup ? "是" : "否"
            let error = (log.errorMessage ?? "").replacingOccurrences(of: ",", with: ";")
            lines.append("\(time),\(escapedTitle),\(status),\(catchup),\(error)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct LogRowView: View {
    let log: GenerationLog

    var body: some View {
        HStack {
            Text(timeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(log.ruleTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(log.success ? "已生成" : (log.errorMessage ?? "失败"))
                .font(.caption)
                .foregroundStyle(log.success ? Color.secondary : Color.red)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: log.actualTime)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if log.isCatchup {
                Text("补发")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(Color.orange)
                    .clipShape(Capsule())
            }
            let (text, color) = badgeInfo
            Text(text)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }

    private var badgeInfo: (String, Color) {
        log.success ? ("成功", .green) : ("失败", .red)
    }
}