import Foundation

enum RecurrenceRule: Codable, Equatable {
    case daily
    case weekly(days: Set<Weekday>)
    case monthly(days: Set<Int>)
    case weekdays
    case custom(interval: Int, unit: RecurrenceUnit)

    enum RecurrenceUnit: String, Codable, CaseIterable {
        case minute
        case hour
        case day
        case week
        case month

        var label: String {
            switch self {
            case .minute: return "分钟"
            case .hour: return "小时"
            case .day: return "天"
            case .week: return "周"
            case .month: return "月"
            }
        }
    }

    var summary: String {
        switch self {
        case .daily:
            return "每天"
        case .weekdays:
            return "工作日"
        case .weekly(let days):
            let sorted = days.sorted { $0.rawValue < $1.rawValue }
            return sorted.map { $0.shortLabel }.joined(separator: "、")
        case .monthly(let days):
            let sorted = days.sorted()
            let labels = sorted.map { d -> String in
                if d == 99 { return "最后一天" }
                return "\(d)日"
            }
            return "每月" + labels.joined(separator: "、")
        case .custom(let n, let unit):
            return "每\(n) \(unit.label)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, days, interval, unit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode("daily", forKey: .type)
        case .weekdays:
            try container.encode("weekdays", forKey: .type)
        case .weekly(let days):
            try container.encode("weekly", forKey: .type)
            try container.encode(days.sorted { $0.rawValue < $1.rawValue }, forKey: .days)
        case .monthly(let days):
            try container.encode("monthly", forKey: .type)
            try container.encode(days.sorted(), forKey: .days)
        case .custom(let interval, let unit):
            try container.encode("custom", forKey: .type)
            try container.encode(interval, forKey: .interval)
            try container.encode(unit, forKey: .unit)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "daily":
            self = .daily
        case "weekdays":
            self = .weekdays
        case "weekly":
            let days = try container.decode(Set<Weekday>.self, forKey: .days)
            self = .weekly(days: days)
        case "monthly":
            let days = try container.decode(Set<Int>.self, forKey: .days)
            self = .monthly(days: days)
        case "custom":
            let interval = try container.decode(Int.self, forKey: .interval)
            let unit = try container.decode(RecurrenceUnit.self, forKey: .unit)
            self = .custom(interval: interval, unit: unit)
        default:
            self = .daily
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var shortLabel: String {
        switch self {
        case .sunday: return "日"
        case .monday: return "一"
        case .tuesday: return "二"
        case .wednesday: return "三"
        case .thursday: return "四"
        case .friday: return "五"
        case .saturday: return "六"
        }
    }

    var fullLabel: String {
        switch self {
        case .sunday: return "周日"
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}