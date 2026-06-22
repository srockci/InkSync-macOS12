import Foundation

final class RecurrenceScheduler {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func nextTriggerDate(for rule: RecurringReminder, after date: Date = Date()) -> Date? {
        guard rule.isEnabled else { return nil }
        if let end = rule.endDate, date > end { return nil }

        if case .custom(let interval, let unit) = rule.recurrenceRule,
           (unit == .minute || unit == .hour) {
            return nextCustomIntervalDate(for: rule, after: date, interval: interval, unit: unit)
        }

        let referenceDate = max(date, rule.startDate)
        var candidate = combineDate(referenceDate, with: rule.triggerTime)

        if candidate <= referenceDate {
            candidate = advanceOneUnit(from: candidate, rule: rule)
        }

        for _ in 0..<365 {
            if matches(rule: rule, date: candidate) {
                if let end = rule.endDate, candidate > end { return nil }
                return candidate
            }
            candidate = advanceOneDay(from: candidate)
        }
        return nil
    }

    private func nextCustomIntervalDate(
        for rule: RecurringReminder,
        after date: Date,
        interval: Int,
        unit: RecurrenceRule.RecurrenceUnit
    ) -> Date? {
        let component: Calendar.Component = (unit == .minute) ? .minute : .hour
        let base = rule.lastGeneratedAt ?? max(rule.startDate, date)
        var scheduled = calendar.date(byAdding: component, value: interval, to: base)
        while let next = scheduled, next <= date {
            scheduled = calendar.date(byAdding: component, value: interval, to: next)
        }
        if let end = rule.endDate, let s = scheduled, s > end { return nil }
        return scheduled
    }

    func rebuildSchedule(for rules: [RecurringReminder]) -> [RecurringReminder] {
        rules.map { rule in
            var updated = rule
            updated.nextScheduledAt = nextTriggerDate(for: rule)
            return updated
        }
    }

    func missedTriggers(for rule: RecurringReminder, from start: Date, to end: Date) -> [Date] {
        let actualStart = max(start, rule.startDate)
        if actualStart >= end { return [] }
        if let endDate = rule.endDate, actualStart > endDate { return [] }

        if case .custom(let interval, let unit) = rule.recurrenceRule {
            switch unit {
            case .minute, .hour:
                return []
            case .day, .week, .month:
                return missedCustomTriggers(rule: rule, interval: interval, unit: unit, from: actualStart, to: end)
            }
        }

        return missedCalendarTriggers(rule: rule, from: actualStart, to: end)
    }

    private func missedCustomTriggers(
        rule: RecurringReminder,
        interval: Int,
        unit: RecurrenceRule.RecurrenceUnit,
        from start: Date,
        to end: Date
    ) -> [Date] {
        let component: Calendar.Component
        switch unit {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        default: return []
        }

        var missed: [Date] = []
        let base = rule.lastGeneratedAt ?? rule.startDate
        guard var candidate = calendar.date(byAdding: component, value: interval, to: base) else {
            return []
        }

        var safety = 0
        while candidate <= end {
            if safety > 1000 { break }
            safety += 1
            if let endDate = rule.endDate, candidate > endDate { break }
            if candidate >= start {
                missed.append(candidate)
            }
            guard let next = calendar.date(byAdding: component, value: interval, to: candidate) else { break }
            candidate = next
        }
        return missed
    }

    private func missedCalendarTriggers(
        rule: RecurringReminder,
        from start: Date,
        to end: Date
    ) -> [Date] {
        var missed: [Date] = []
        var candidate = combineDate(start, with: rule.triggerTime)
        while candidate < start {
            candidate = advanceOneDay(from: candidate)
        }

        var safety = 0
        let maxIterations = 365 * 3
        while candidate <= end {
            if safety > maxIterations { break }
            safety += 1
            if let endDate = rule.endDate, candidate > endDate { break }
            if matches(rule: rule, date: candidate) {
                missed.append(candidate)
            }
            candidate = advanceOneDay(from: candidate)
        }
        return missed
    }

    private func combineDate(_ date: Date, with time: TriggerTime) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private func matches(rule: RecurringReminder, date: Date) -> Bool {
        if date < rule.startDate { return false }
        if let end = rule.endDate, date > end { return false }

        let day = calendar.component(.day, from: date)
        let weekday = calendar.component(.weekday, from: date)

        switch rule.recurrenceRule {
        case .daily:
            return true
        case .weekdays:
            return weekday >= 2 && weekday <= 6
        case .weekly(let days):
            return days.contains(Weekday(rawValue: weekday) ?? .sunday)
        case .monthly(let days):
            if days.contains(day) { return true }
            if days.contains(99) {
                let range = calendar.range(of: .day, in: .month, for: date) ?? 1..<32
                return day == range.upperBound - 1
            }
            return false
        case .custom(let interval, let unit):
            switch unit {
            case .minute, .hour:
                guard let last = rule.lastGeneratedAt else {
                    return calendar.isDate(date, inSameDayAs: combineDate(date, with: rule.triggerTime))
                }
                let component: Calendar.Component = (unit == .minute) ? .minute : .hour
                let scheduled = calendar.date(byAdding: component, value: interval, to: last)
                guard let scheduled = scheduled else { return false }
                return calendar.compare(date, to: scheduled, toGranularity: component) == .orderedSame
            case .day, .week, .month:
                guard let last = rule.lastGeneratedAt else { return true }
                let next: Date?
                switch unit {
                case .day: next = calendar.date(byAdding: .day, value: interval, to: last)
                case .week: next = calendar.date(byAdding: .weekOfYear, value: interval, to: last)
                case .month: next = calendar.date(byAdding: .month, value: interval, to: last)
                default: next = nil
                }
                guard let scheduled = next else { return false }
                return calendar.isDate(date, inSameDayAs: scheduled)
            }
        }
    }

    private func advanceOneDay(from date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private func advanceOneUnit(from date: Date, rule: RecurringReminder) -> Date {
        switch rule.recurrenceRule {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            return nextWeekday(from: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .custom:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
    }

    private func nextWeekday(from date: Date) -> Date {
        var candidate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        for _ in 0..<7 {
            let weekday = calendar.component(.weekday, from: candidate)
            if weekday >= 2 && weekday <= 6 {
                return candidate
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}