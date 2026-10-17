import Foundation

/// ウィジェットの表示文字列を作ります。
/// macOS 10.12 版でも使えるよう、`Date.formatted` ではなく `DateFormatter` を使います。
public final class AstronomyTextFormatter: @unchecked Sendable {
    public let calendar: Calendar
    private let timeFormatter: DateFormatter
    private let fullDateFormatter: DateFormatter
    private let shortDateFormatter: DateFormatter

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        fullDateFormatter = DateFormatter()
        fullDateFormatter.calendar = calendar
        fullDateFormatter.timeZone = calendar.timeZone
        fullDateFormatter.locale = locale
        fullDateFormatter.dateStyle = .full
        fullDateFormatter.timeStyle = .none

        shortDateFormatter = DateFormatter()
        shortDateFormatter.calendar = calendar
        shortDateFormatter.timeZone = calendar.timeZone
        shortDateFormatter.locale = locale
        shortDateFormatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
    }

    // MARK: - 日付・時刻

    public func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return timeFormatter.string(from: date)
    }

    /// 「2026年10月17日 土曜日」のような日付です。
    public func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    /// 「10月17日(土)」のような短い日付です。
    public func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)分" }
        return "\(hours)時間" + String(format: "%02d分", rest)
    }

    /// 「35.6895°N, 139.6917°E」のような緯度経度です。
    public func coordinate(latitude: Double, longitude: Double, fractionDigits: Int = 2) -> String {
        let format = "%.\(fractionDigits)f°%@, %.\(fractionDigits)f°%@"
        return String(
            format: format,
            abs(latitude), latitude >= 0 ? "N" : "S",
            abs(longitude), longitude >= 0 ? "E" : "W"
        )
    }

    // MARK: - 月

    /// 翌日以降にまたぐ場合に、時刻へ直接付ける接頭辞です。
    public func dayPrefix(_ note: MoonEventNote) -> String {
        guard case .occursDaysLater(let days) = note else { return "" }
        return days == 1 ? "翌" : "\(days)日後"
    }

    /// 前日にのぼった月であることを、時刻の横へ小さく添えます。
    public func previousDayBadge(_ note: MoonEventNote) -> String? {
        guard case .roseOnPreviousDay = note else { return nil }
        return "（前日）"
    }

    public func moonTime(_ date: Date?, _ note: MoonEventNote) -> String {
        guard date != nil else { return "—" }
        return dayPrefix(note) + time(date)
    }

    /// 南中時刻と南中高度です。月の場合は「翌」などの接頭辞も付けます。
    public func transit(_ events: DailyBodyEvents) -> String {
        guard let date = events.transit, let altitude = events.transitAltitude else { return "—" }
        return dayPrefix(events.transitNote) + "\(time(date))（\(String(format: "%.1f", altitude))°）"
    }

    // MARK: - 暗夜

    /// 「10/6〜7の夜」のように、どの夜の暗夜かを示します。
    public func nightRangeTitle(_ night: DarkNight) -> String {
        let month = calendar.component(.month, from: night.date)
        let day = calendar.component(.day, from: night.date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: night.date) else { return "\(month)/\(day)" }
        let nextMonth = calendar.component(.month, from: next)
        let nextDay = calendar.component(.day, from: next)
        let nextText = nextMonth == month ? "\(nextDay)" : "\(nextMonth)/\(nextDay)"
        return "\(month)/\(day)〜\(nextText)の夜"
    }

    /// 対象日の翌日以降の時刻には「翌」を付けます。
    public func nightTime(_ date: Date, in night: DarkNight) -> String {
        let isNextDay = calendar.startOfDay(for: date) > night.date
        return (isNextDay ? "翌" : "") + time(date)
    }

    /// 暗夜の開始が「夕の天文薄明終了」と「月の入」のどちらによるかを返します。
    public func startCause(_ interval: DateInterval, in night: DarkNight) -> String? {
        if interval.start <= night.window.start { return nil }
        let byTwilight = night.astronomicalNight.contains { abs($0.start.timeIntervalSince(interval.start)) < 1 }
        return byTwilight ? "薄明終了" : "月の入"
    }

    /// 暗夜の終了が「朝の天文薄明開始」と「月の出」のどちらによるかを返します。
    public func endCause(_ interval: DateInterval, in night: DarkNight) -> String? {
        if interval.end >= night.window.end { return nil }
        let byTwilight = night.astronomicalNight.contains { abs($0.end.timeIntervalSince(interval.end)) < 1 }
        return byTwilight ? "薄明開始" : "月の出"
    }
}

/// 表示する日付（観測日）に関する計算です。
public enum ObservationDay {
    /// 月齢・月の概形を求める時刻です。
    /// 今日を表示しているときは現在時刻、それ以外の日はその日の正午とします。
    public static func moonPhaseMoment(for day: Date, now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        if start == calendar.startOfDay(for: now) { return now }
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    /// 表示日の 0 時から `days` 日ずらした日の 0 時を返します。
    public static func shifted(_ day: Date, by days: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }

    /// 今日・明日、またはそれ以外の日を表す見出しを返します。
    public static func relativeTitle(for day: Date, now: Date, calendar: Calendar = .current) -> String? {
        let start = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)
        let difference = calendar.dateComponents([.day], from: today, to: start).day ?? 0
        switch difference {
        case 0: return "今日"
        case 1: return "明日"
        case -1: return "昨日"
        default: return nil
        }
    }
}
