import SwiftUI
import EventKit

struct RecurringRemindersView: View {
    @ObservedObject var engine: RecurringEngine
    @State private var editingRule: RecurringReminder?
    @State private var showingNewRule = false
    @State private var selection: Set<UUID> = []
    var onOpenLog: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            table
            Divider()
            footer
        }
        .frame(width: 720, height: 480)
        .sheet(isPresented: $showingNewRule) {
            RecurringReminderEditView(
                rule: nil,
                eventKitManager: EventKitManager(),
                mappingManager: engine.mappingManagerForUI(),
                onSave: { newRule in
                    engine.addRule(newRule)
                    showingNewRule = false
                },
                onCancel: { showingNewRule = false }
            )
        }
        .sheet(item: $editingRule) { rule in
            RecurringReminderEditView(
                rule: rule,
                eventKitManager: EventKitManager(),
                mappingManager: engine.mappingManagerForUI(),
                onSave: { updated in
                    engine.updateRule(updated)
                    editingRule = nil
                },
                onCancel: { editingRule = nil }
            )
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("标题").frame(maxWidth: .infinity, alignment: .leading)
                Text("周期").frame(width: 140, alignment: .leading)
                Text("状态").frame(width: 90, alignment: .leading)
                Text("下次").frame(width: 140, alignment: .leading)
                Spacer().frame(width: 40)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            if engine.rules.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("暂无周期规则")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("点击 + 创建第一条规则")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(engine.rules) { rule in
                            RecurringReminderRowView(
                                rule: rule,
                                isSelected: selection.contains(rule.id),
                                onToggle: { engine.setEnabled(rule.id, enabled: $0) },
                                onEdit: { editingRule = rule },
                                onSelect: { selected in
                                    if selected { selection.insert(rule.id) }
                                    else { selection.remove(rule.id) }
                                }
                            )
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showingNewRule = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("新增")

            Button {
                engine.deleteRules(Array(selection))
                selection.removeAll()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(selection.isEmpty ? Color.secondary : Color.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)
            .help("删除选中")

            Spacer()

            if !selection.isEmpty {
                Button("批量暂停") {
                    for id in selection { engine.setEnabled(id, enabled: false) }
                }
                Button(role: .destructive) {
                    engine.deleteRules(Array(selection))
                    selection.removeAll()
                } label: {
                    Text("批量删除")
                }
                .foregroundStyle(.red)
            }

            Spacer()

            Text("共 \(engine.rules.count) 条规则")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("查看生成日志") {
                onOpenLog()
            }
        }
        .padding(16)
    }
}

struct RecurringReminderRowView: View {
    let rule: RecurringReminder
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: 50)

            Text(rule.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(rule.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            statusBadge
                .frame(width: 90, alignment: .leading)

            Text(nextTriggerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .frame(width: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(!isSelected) }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var statusBadge: some View {
        Text(rule.isEnabled ? "已启用" : "已暂停")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rule.isEnabled ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundStyle(rule.isEnabled ? .green : .orange)
            .clipShape(Capsule())
    }

    private var nextTriggerText: String {
        guard let next = rule.nextScheduledAt else { return "--" }
        let interval = next.timeIntervalSinceNow
        if interval <= 0 { return "即将触发" }
        if interval < 60 { return "小于 1 分钟" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: next, relativeTo: Date())
    }
}