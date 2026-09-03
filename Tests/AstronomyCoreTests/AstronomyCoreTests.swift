import XCTest
@testable import AstronomyCore

final class AstronomyCoreTests: XCTestCase {
    private let calculator = AstronomyCalculator()
    private let tokyo = ObserverLocation(latitude: 35.6812, longitude: 139.7671, name: "東京")

    func testJulianEpochSunCoordinate() {
        let date = ISO8601DateFormatter().date(from: "2000-01-01T12:00:00Z")!
        let sun = calculator.sunCoordinate(at: date)
        XCTAssertEqual(sun.declination * 180 / .pi, -23.03, accuracy: 0.15)
        XCTAssertEqual(sun.eclipticLongitude, 280.37, accuracy: 0.15)
    }

    func testSummerSolsticeTokyoEventsAreOrdered() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = ISO8601DateFormatter().date(from: "2026-06-21T03:00:00Z")!
        let daily = calculator.dailyAstronomy(for: date, location: tokyo, calendar: calendar)

        XCTAssertNotNil(daily.sun.rise)
        XCTAssertNotNil(daily.sun.transit)
        XCTAssertNotNil(daily.sun.set)
        XCTAssertLessThan(daily.sun.rise!, daily.sun.transit!)
        XCTAssertLessThan(daily.sun.transit!, daily.sun.set!)
        XCTAssertEqual(daily.sun.transitAltitude!, 77.7, accuracy: 0.8)
        XCTAssertLessThan(daily.astronomicalTwilight.morning!, daily.sun.rise!)
        XCTAssertGreaterThan(daily.astronomicalTwilight.evening!, daily.sun.set!)
    }

    func testMoonPhaseIsNormalized() {
        let date = ISO8601DateFormatter().date(from: "2026-08-22T00:00:00Z")!
        let phase = calculator.moonPhase(at: date)
        XCTAssertGreaterThanOrEqual(phase.fraction, 0)
        XCTAssertLessThan(phase.fraction, 1)
        XCTAssertGreaterThanOrEqual(phase.age, 0)
        XCTAssertLessThan(phase.age, AstronomyCalculator.synodicMonth)
        XCTAssertGreaterThanOrEqual(phase.illuminatedFraction, 0)
        XCTAssertLessThanOrEqual(phase.illuminatedFraction, 1)
    }

    func testTokyoEventsAgainstIndependentEphemeris() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = ISO8601DateFormatter().date(from: "2026-08-22T00:00:00Z")!
        let daily = calculator.dailyAstronomy(for: date, location: tokyo, calendar: calendar)

        // PyEphem 4.2（XEphem系）による同地点・同日の独立計算値と照合します。
        assertTime(daily.sun.rise, isNear: "2026-08-21T20:04:43Z", toleranceMinutes: 3)
        assertTime(daily.sun.transit, isNear: "2026-08-22T02:43:56Z", toleranceMinutes: 3)
        assertTime(daily.sun.set, isNear: "2026-08-22T09:22:35Z", toleranceMinutes: 3)
        assertTime(daily.moon.rise, isNear: "2026-08-22T05:34:40Z", toleranceMinutes: 12)
        assertTime(daily.moon.transit, isNear: "2026-08-22T10:13:55Z", toleranceMinutes: 12)
        assertTime(daily.moon.set, isNear: "2026-08-22T14:53:07Z", toleranceMinutes: 12)
        assertTime(daily.astronomicalTwilight.morning, isNear: "2026-08-21T18:31:42Z", toleranceMinutes: 3)
        assertTime(daily.astronomicalTwilight.evening, isNear: "2026-08-22T10:55:15Z", toleranceMinutes: 3)
    }

    func testPolarNightHasNoSunrise() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Arctic/Longyearbyen")!
        let date = ISO8601DateFormatter().date(from: "2026-12-21T12:00:00Z")!
        let location = ObserverLocation(latitude: 78.2232, longitude: 15.6469, name: "ロングイェールビーン")
        let daily = calculator.dailyAstronomy(for: date, location: location, calendar: calendar)
        XCTAssertNil(daily.sun.rise)
        XCTAssertNil(daily.sun.set)
        XCTAssertNotNil(daily.astronomicalTwilight.morning)
        XCTAssertNotNil(daily.astronomicalTwilight.evening)
        XCTAssertLessThan(daily.astronomicalTwilight.morning!, daily.astronomicalTwilight.evening!)
    }

    /// 2026年9月3日の東京は、月の出21:19に対して南中3:58・月の入11:28が前日にのぼった月のものになります。
    func testMoonModesOnDayWhereEventsBelongToPreviousMoon() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = ISO8601DateFormatter().date(from: "2026-09-03T03:00:00Z")!

        let withinDay = calculator.dailyAstronomy(
            for: date,
            location: tokyo,
            calendar: calendar,
            moonMode: .withinDay
        ).moon
        XCTAssertNotNil(withinDay.rise)
        XCTAssertNotNil(withinDay.transit)
        XCTAssertNotNil(withinDay.set)
        // 南中と月の入は月の出より前に起きるため、前日にのぼった月と判定されます。
        XCTAssertLessThan(withinDay.transit!, withinDay.rise!)
        XCTAssertLessThan(withinDay.set!, withinDay.rise!)
        XCTAssertEqual(withinDay.transitNote, .roseOnPreviousDay)
        XCTAssertEqual(withinDay.setNote, .roseOnPreviousDay)

        let risenThatDay = calculator.dailyAstronomy(
            for: date,
            location: tokyo,
            calendar: calendar,
            moonMode: .risenThatDay
        ).moon
        // 月の出は同じで、南中と月の入はその月を追いかけた翌日の時刻になります。
        XCTAssertEqual(risenThatDay.rise, withinDay.rise)
        XCTAssertNotNil(risenThatDay.transit)
        XCTAssertNotNil(risenThatDay.set)
        XCTAssertLessThan(risenThatDay.rise!, risenThatDay.transit!)
        XCTAssertLessThan(risenThatDay.transit!, risenThatDay.set!)
        XCTAssertEqual(risenThatDay.transitNote, .occursDaysLater(1))
        XCTAssertEqual(risenThatDay.setNote, .occursDaysLater(1))
        XCTAssertNotNil(risenThatDay.transitAltitude)

        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        XCTAssertEqual(calendar.startOfDay(for: risenThatDay.transit!), nextDay)
        XCTAssertEqual(calendar.startOfDay(for: risenThatDay.set!), nextDay)
    }

    /// 南中・月の入がその日のうちに収まる日は、どちらのモードでも同じ結果になります。
    func testMoonModesAgreeWhenEventsFollowTheSameDayRise() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = ISO8601DateFormatter().date(from: "2026-08-22T00:00:00Z")!

        let withinDay = calculator.dailyAstronomy(
            for: date,
            location: tokyo,
            calendar: calendar,
            moonMode: .withinDay
        ).moon
        let risenThatDay = calculator.dailyAstronomy(
            for: date,
            location: tokyo,
            calendar: calendar,
            moonMode: .risenThatDay
        ).moon

        XCTAssertEqual(risenThatDay.rise, withinDay.rise)
        XCTAssertEqual(
            risenThatDay.transit!.timeIntervalSince(withinDay.transit!),
            0,
            accuracy: 60
        )
        XCTAssertEqual(risenThatDay.set!.timeIntervalSince(withinDay.set!), 0, accuracy: 60)
        XCTAssertEqual(withinDay.transitNote, .none)
        XCTAssertEqual(withinDay.setNote, .none)
        XCTAssertEqual(risenThatDay.transitNote, .none)
        XCTAssertEqual(risenThatDay.setNote, .none)
    }

    private func assertTime(
        _ actual: Date?,
        isNear expectedText: String,
        toleranceMinutes: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual, let expected = ISO8601DateFormatter().date(from: expectedText) else {
            XCTFail("時刻を取得または解釈できません", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.timeIntervalSince(expected), 0, accuracy: toleranceMinutes * 60, file: file, line: line)
    }
}
