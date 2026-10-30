import Foundation

enum CheckFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily
    case everyTwoDays
    case everySevenDays
    case everyFifteenDays
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .everyTwoDays: "Every 2 days"
        case .everySevenDays: "Every 7 days"
        case .everyFifteenDays: "Every 15 days"
        case .monthly: "On the 1st of every month"
        }
    }

    /// Days between runs; nil for the calendar-based monthly schedule.
    var dayInterval: Int? {
        switch self {
        case .daily: 1
        case .everyTwoDays: 2
        case .everySevenDays: 7
        case .everyFifteenDays: 15
        case .monthly: nil
        }
    }
}

/// When the scheduled check (and automatic update) runs.
struct UpdateSchedule: Sendable {
    var frequency: CheckFrequency
    /// Time of day, in minutes after midnight.
    var minuteOfDay: Int

    /// The next run after the last one; before the first run, the first
    /// occurrence after `anchor` (when scheduling started). Runs missed while the
    /// Mac was asleep or off fall in the past, so they happen as soon as it wakes.
    func nextRun(after lastRun: Date?, anchor: Date, calendar: Calendar = .current) -> Date {
        if let lastRun {
            switch frequency.dayInterval {
            case let days?:
                let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: lastRun))!
                return at(timeOn: day, calendar)
            case nil:
                return firstOfMonth(after: lastRun, calendar)
            }
        }
        switch frequency.dayInterval {
        case .some:
            let today = at(timeOn: anchor, calendar)
            return today > anchor ? today : at(timeOn: calendar.date(byAdding: .day, value: 1, to: anchor)!, calendar)
        case nil:
            return firstOfMonth(after: anchor, calendar)
        }
    }

    private func at(timeOn day: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)!
    }

    /// The 1st of the month at the scheduled time, strictly after `date`.
    private func firstOfMonth(after date: Date, _ calendar: Calendar) -> Date {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let thisMonth = at(timeOn: monthStart, calendar)
        if thisMonth > date { return thisMonth }
        return at(timeOn: calendar.date(byAdding: .month, value: 1, to: monthStart)!, calendar)
    }
}
