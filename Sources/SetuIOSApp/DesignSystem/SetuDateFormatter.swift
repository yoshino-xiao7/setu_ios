import Foundation

enum SetuDateDisplayStyle {
    case compact
    case full
}

enum SetuDateFormatter {
    static func string(from rawValue: String?, style: SetuDateDisplayStyle = .compact) -> String {
        guard let rawValue else { return "时间未知" }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let date = parse(trimmed) else { return "时间未知" }

        switch style {
        case .compact:
            return compactString(from: date)
        case .full:
            return date.formatted(
                .dateTime
                    .year()
                    .month()
                    .day()
                    .hour()
                    .minute()
            )
        }
    }

    private static func compactString(from date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) {
            return "今天 \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(time)"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
        return date.formatted(.dateTime.year().month().day())
    }

    private static func parse(_ value: String) -> Date? {
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
