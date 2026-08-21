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

public struct DailyBodyEvents: Equatable, Sendable {
    public var rise: Date?
    public var transit: Date?
    public var set: Date?
    public var transitAltitude: Double?

    public init(rise: Date?, transit: Date?, set: Date?, transitAltitude: Double?) {
        self.rise = rise
        self.transit = transit
        self.set = set
        self.transitAltitude = transitAltitude
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
