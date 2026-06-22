import SwiftUI
import EventKit

struct RecurringReminderEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var isEnabled: Bool
    @State private var recurrenceType: RecurrenceType
    @State private var weeklyDays: Set<Weekday>
    @State private var monthlyDays: Set<Int>
    @State private var customInterval: Int
    @State private var customUnit: RecurrenceRule.RecurrenceUnit
    @State private var triggerHour: Int
    @State private var triggerMinute: Int
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var duplicateStrategy: AdvancedOptions.DuplicateStrategy
    @State private var autoComplete: Bool
    @State private var tagsText: String
    @State private var showingAdvanced: Bool = false

    private let existingRule: RecurringReminder?
    private let eventKitManager: EventKitManager
    private let mappingManager: MappingManager
    let onSave: (RecurringReminder) -> Void
    let onCancel: () -> Void

    enum RecurrenceType: String, CaseIterable, Identifiable {
        case daily, weekly, monthly, weekdays, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily: return "每天"
            case .weekly: return "每周"
            case .monthly: return "每月"
            case .weekdays: return "工作日"
            case .custom: return "自定义"
            }
        }
    }

    init(
        rule: RecurringReminder?,
        eventKitManager: EventKitManager,
        mappingManager: MappingManager,
        onSave: @escaping (RecurringReminder) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingRule = rule
        self.eventKitManager = eventKitManager
        self.mappingManager = mappingManager
        self.onSave = onSave
        self.onCancel = onCancel

        _title = State(initialValue: rule?.title ?? "")
        _notes = State(initialValue: rule?.notes ?? "")
        _isEnabled = State(initialValue: rule?.isEnabled ?? true)
        _triggerHour = State(initialValue: rule?.triggerTime.hour ?? 9)
        _triggerMinute = State(initialValue: rule?.triggerTime.minute ?? 0)
        _startDate = State(initialValue: rule?.startDate ?? Date())
        _hasEndDate = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: rule?.endDate ?? Date().addingTimeInterval(86400 * 30))
        _duplicateStrategy = State(initialValue: rule?.advancedOptions.duplicateStrategy ?? .skip)
        _autoComplete = State(initialValue: rule?.advancedOptions.autoComplete ?? false)
        _tagsText = State(initialValue: rule?.advancedOptions.tags.joined(separator: ", ") ?? "")

        switch rule?.recurrenceRule {
        case .daily, .none:
            _recurrenceType = State(initialValue: .daily)
            _weeklyDays = State(initialValue: [])
            _monthlyDays = State(initialValue: [])
            _customInterval = State(initialValue: 3)
            _customUnit = State(initialValue: .day)
        case .weekdays:
            _recurrenceType = State(initialValue: .weekdays)
            _weeklyDays = State(initialValue: [])
            _monthlyDays = State(initialValue: [])
            _customInterval = State(initialValue: 3)
            _customUnit = State(initialValue: .day)
        case .weekly(let days):
            _recurrenceType = State(initialValue: .weekly)
            _weeklyDays = State(initialValue: days)
            _monthlyDays = State(initialValue: [])
            _customInterval = State(initialValue: 3)
            _customUnit = State(initialValue: .day)
        case .monthly(let days):
            _recurrenceType = State(initialValue: .monthly)
            _weeklyDays = State(initialValue: [])
            _monthlyDays = State(initialValue: days)
            _customInterval = State(initialValue: 3)
            _customUnit = State(initialValue: .day)
        case .custom(let interval, let unit):
            _recurrenceType = State(initialValue: .custom)
            _weeklyDays = State(initialValue: [])
            _monthlyDays = State(initialValue: [])
            _customInterval = State(initialValue: interval)
            _customUnit = State(initialValue: unit)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingRule == nil ? "新建周期备忘" : "编辑周期备忘")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("标题") {
                        TextField("标题", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    section("内容") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                            .font(.body)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    }

                    section("周期类型") {
                        Picker("", selection: $recurrenceType) {
                            ForEach(RecurrenceType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        if recurrenceType == .weekly {
                            weekdayPicker
                        } else if recurrenceType == .monthly {
                            monthlyDayPicker
                        } else if recurrenceType == .custom {
                            customPicker
                        }
                    }

                    section("触发时间") {
                        HStack {
                            Picker("时", selection: $triggerHour) {
                                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                            .frame(width: 80)
                            Text(":")
                            Picker("分", selection: $triggerMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                            .frame(width: 80)
                        }
                    }

                    section("生效范围") {
                        HStack {
                            Text("开始：")
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                            Spacer()
                        }
                        HStack {
                            Toggle("结束日期", isOn: $hasEndDate)
                            if hasEndDate {
                                DatePicker("", selection: $endDate, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }

                    advancedSection
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existingRule == nil ? "保存" : "更新") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || !isValid)
            }
            .padding(16)
        }
        .frame(width: 480, height: 560)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.rawValue) { day in
                Toggle(isOn: Binding(
                    get: { weeklyDays.contains(day) },
                    set: { isOn in
                        if isOn { weeklyDays.insert(day) }
                        else { weeklyDays.remove(day) }
                    }
                )) {
                    Text(day.shortLabel)
                }
                .toggleStyle(.button)
            }
        }
    }

    private var monthlyDayPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选择日期（可多选，支持「最后一天」）")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(1...31, id: \.self) { day in
                    Toggle(isOn: Binding(
                        get: { monthlyDays.contains(day) },
                        set: { isOn in
                            if isOn { monthlyDays.insert(day) }
                            else { monthlyDays.remove(day) }
                        }
                    )) {
                        Text("\(day)日")
                    }
                }
                Divider()
                Toggle(isOn: Binding(
                    get: { monthlyDays.contains(99) },
                    set: { isOn in
                        if isOn { monthlyDays.insert(99) }
                        else { monthlyDays.remove(99) }
                    }
                )) {
                    Text("最后一天")
                }
            } label: {
                HStack {
                    Text(monthlyDays.isEmpty ? "选择日期" : monthlyDaysLabel)
                        .foregroundStyle(monthlyDays.isEmpty ? Color.secondary : Color.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var monthlyDaysLabel: String {
        let normalDays = monthlyDays.filter { $0 != 99 }.sorted()
        let hasLastDay = monthlyDays.contains(99)
        var parts: [String] = normalDays.map { "\($0)日" }
        if hasLastDay { parts.append("最后一天") }
        return parts.joined(separator: "、")
    }

    private var customPicker: some View {
        HStack {
            Text("每")
            TextField("", value: $customInterval, format: .number)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $customUnit) {
                ForEach(RecurrenceRule.RecurrenceUnit.allCases, id: \.self) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .frame(width: 100)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showingAdvanced.toggle() }
            } label: {
                HStack {
                    Text("高级选项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: showingAdvanced ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if showingAdvanced {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("若当日已存在同名备忘：")
                        Picker("", selection: $duplicateStrategy) {
                            ForEach(AdvancedOptions.DuplicateStrategy.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .frame(width: 130)
                        .labelsHidden()
                    }
                    Toggle("生成后自动标记完成", isOn: $autoComplete)
                    HStack {
                        Text("标签（逗号分隔）")
                        TextField("", text: $tagsText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        switch recurrenceType {
        case .weekly: return !weeklyDays.isEmpty
        case .monthly: return !monthlyDays.isEmpty
        default: return true
        }
    }

    private func save() {
        let rule: RecurrenceRule
        switch recurrenceType {
        case .daily: rule = .daily
        case .weekdays: rule = .weekdays
        case .weekly: rule = .weekly(days: weeklyDays)
        case .monthly: rule = .monthly(days: monthlyDays)
        case .custom: rule = .custom(interval: max(1, customInterval), unit: customUnit)
        }

        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let new = RecurringReminder(
            id: existingRule?.id ?? UUID(),
            title: title,
            notes: notes.isEmpty ? nil : notes,
            isEnabled: isEnabled,
            recurrenceRule: rule,
            triggerTime: TriggerTime(hour: triggerHour, minute: triggerMinute),
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            advancedOptions: AdvancedOptions(
                duplicateStrategy: duplicateStrategy,
                autoComplete: autoComplete,
                tags: tags
            ),
            createdAt: existingRule?.createdAt ?? Date(),
            updatedAt: Date(),
            lastGeneratedAt: existingRule?.lastGeneratedAt,
            nextScheduledAt: existingRule?.nextScheduledAt
        )
        onSave(new)
    }
}