import Foundation

public struct ObserverLocation: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var name: String

    public init(latitude: Double, longitude: Double, name: String) {
        self.latitude = min(90, max(-90, latitude))
        self.longitude = min(180, max(-180, longitude))
        self.name = name
    }
}

public struct EquatorialCoordinate: Sendable {
    public let rightAscension: Double
    public let declination: Double
    public let distance: Double
    public let eclipticLongitude: Double
}

/// 月の南中・月の入を、どの月について表示するかを決めます。
public enum MoonDayMode: String, CaseIterable, Identifiable, Sendable {
    /// その日にのぼった月を追います。南中・月の入が翌日になることがあります。
    case risenThatDay
    /// その日のうちに起きる出来事を表示します。前日にのぼった月のものになることがあります。
    case withinDay

    public var id: String { rawValue }
}

/// 表示する時刻がどの月のものか、いつ起きるのかを補足します。
public enum MoonEventNote: Equatable, Sendable {
    /// その日にのぼった月の、その日のうちの出来事です。
    case none
    /// 前日にのぼった月の出来事です。
    case roseOnPreviousDay
    /// その日にのぼった月が、指定した日数だけ後に迎える出来事です。
    case occursDaysLater(Int)
}

public struct DailyBodyEvents: Equatable, Sendable {
    public var rise: Date?
    public var transit: Date?
    public var set: Date?
    public var transitAltitude: Double?
    public var transitNote: MoonEventNote
    public var setNote: MoonEventNote

    public init(
        rise: Date?,
        transit: Date?,
        set: Date?,
        transitAltitude: Double?,
        transitNote: MoonEventNote = .none,
        setNote: MoonEventNote = .none
    ) {
        self.rise = rise
        self.transit = transit
        self.set = set
        self.transitAltitude = transitAltitude
        self.transitNote = transitNote
        self.setNote = setNote
    }
}

public struct TwilightEvents: Equatable, Sendable {
    public var morning: Date?
    public var evening: Date?

    public init(morning: Date?, evening: Date?) {
        self.morning = morning
        self.evening = evening
    }
}

public struct DailyAstronomy: Equatable, Sendable {
    public var date: Date
    public var sun: DailyBodyEvents
    public var moon: DailyBodyEvents
    public var astronomicalTwilight: TwilightEvents

    public init(date: Date, sun: DailyBodyEvents, moon: DailyBodyEvents, astronomicalTwilight: TwilightEvents) {
        self.date = date
        self.sun = sun
        self.moon = moon
        self.astronomicalTwilight = astronomicalTwilight
    }
}

/// その日の夕方から翌朝にかけての暗夜（太陽も月も影響しない時間帯）です。
public struct DarkNight: Equatable, Sendable {
    /// 暗夜の有無を、理由も含めて表します。
    public enum Status: Equatable, Sendable {
        /// 暗夜があります。
        case dark
        /// 天文薄明が終わらない（太陽が −18° より下へ沈まない）ため、暗夜がありません。
        case noAstronomicalNight
        /// 天文薄明は終わるものの、その間ずっと月が出ているため暗夜がありません。
        case moonlitAllNight
    }

    /// 対象日の 0 時です。
    public var date: Date
    /// 探索した時間窓（対象日の正午〜翌日の正午）です。
    public var window: DateInterval
    /// 太陽中心高度が −18° 未満となる区間（夕の天文薄明終了〜朝の天文薄明開始）です。
    public var astronomicalNight: [DateInterval]
    /// 天文薄明の外で、かつ月が地平線下にある区間です。
    public var darkIntervals: [DateInterval]

    public init(date: Date, window: DateInterval, astronomicalNight: [DateInterval], darkIntervals: [DateInterval]) {
        self.date = date
        self.window = window
        self.astronomicalNight = astronomicalNight
        self.darkIntervals = darkIntervals
    }

    /// 暗夜の合計時間（秒）です。
    public var totalDuration: TimeInterval {
        darkIntervals.reduce(0) { $0 + $1.duration }
    }

    /// 天文薄明の外にある時間の合計（秒）です。
    public var astronomicalNightDuration: TimeInterval {
        astronomicalNight.reduce(0) { $0 + $1.duration }
    }

    public var status: Status {
        if astronomicalNight.isEmpty { return .noAstronomicalNight }
        if darkIntervals.isEmpty { return .moonlitAllNight }
        return .dark
    }
}

public struct MoonPhase: Equatable, Sendable {
    /// 0 が新月、0.5 が満月、1 の直前が次の新月です。
    public let fraction: Double
    public let age: Double
    public let illuminatedFraction: Double

    public init(fraction: Double, age: Double, illuminatedFraction: Double) {
        self.fraction = fraction
        self.age = age
        self.illuminatedFraction = illuminatedFraction
    }
}
