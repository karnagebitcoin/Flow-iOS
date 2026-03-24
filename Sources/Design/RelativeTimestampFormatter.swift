import Foundation

enum RelativeTimestampFormatter {
    static func shortString(from date: Date, now: Date = Date()) -> String {
        let delta = max(Int(now.timeIntervalSince(date)), 0)

        if delta < 60 {
            return "1 min"
        }

        let minutes = delta / 60
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr"
        }

        let days = hours / 24
        if days < 7 {
            return "\(days) d"
        }

        let weeks = days / 7
        if weeks < 5 {
            return "\(weeks) wk"
        }

        let months = days / 30
        if months < 12 {
            return "\(months) mo"
        }

        let years = days / 365
        return "\(years) yr"
    }
}
