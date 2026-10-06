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

    /// 2026年8月22日の東京：月の入（23:53）から朝の天文薄明開始（翌3:34）までが暗夜です。
    func testDarkNightStartsAtMoonset() {
        let daily = darkNight("2026-08-22T03:00:00Z")
        XCTAssertEqual(daily.status, .dark)
        XCTAssertEqual(daily.darkIntervals.count, 1)
        // PyEphem 4.2 による独立計算値と照合します。
        assertTime(daily.darkIntervals.first?.start, isNear: "2026-08-22T14:53:00Z", toleranceMinutes: 12)
        assertTime(daily.darkIntervals.first?.end, isNear: "2026-08-22T18:34:30Z", toleranceMinutes: 3)
        // 夕の天文薄明終了は暗夜の開始より前（月が出ている時間）です。
        XCTAssertLessThan(daily.astronomicalNight.first!.start, daily.darkIntervals.first!.start)
    }

    /// 2026年10月6日の東京：夕の天文薄明終了（18:43）から月の出（翌1:46）までが暗夜です。
    func testDarkNightEndsAtMoonrise() {
        let daily = darkNight("2026-10-06T03:00:00Z")
        XCTAssertEqual(daily.status, .dark)
        XCTAssertEqual(daily.darkIntervals.count, 1)
        assertTime(daily.darkIntervals.first?.start, isNear: "2026-10-06T09:43:00Z", toleranceMinutes: 3)
        assertTime(daily.darkIntervals.first?.end, isNear: "2026-10-06T16:46:30Z", toleranceMinutes: 12)
        XCTAssertEqual(daily.totalDuration / 60, 424, accuracy: 12)
    }

    /// 新月の夜は、天文薄明の外がすべて暗夜になります。
    func testDarkNightCoversWholeAstronomicalNightAtNewMoon() {
        let daily = darkNight("2026-10-10T03:00:00Z")
        XCTAssertEqual(daily.status, .dark)
        XCTAssertEqual(daily.darkIntervals, daily.astronomicalNight)
        assertTime(daily.darkIntervals.first?.start, isNear: "2026-10-10T09:37:30Z", toleranceMinutes: 3)
        assertTime(daily.darkIntervals.first?.end, isNear: "2026-10-10T19:19:00Z", toleranceMinutes: 3)
    }

    /// 満月の夜は、天文薄明の外でもずっと月が出ているため暗夜がありません。
    func testDarkNightIsAbsentAtFullMoon() {
        let daily = darkNight("2026-10-26T03:00:00Z")
        XCTAssertEqual(daily.status, .moonlitAllNight)
        XCTAssertTrue(daily.darkIntervals.isEmpty)
        XCTAssertFalse(daily.astronomicalNight.isEmpty)
        XCTAssertEqual(daily.totalDuration, 0)
    }

    /// 夏至前後の高緯度では天文薄明が終わらず、暗夜がありません。
    func testDarkNightIsAbsentWhenTwilightNeverEnds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
        let london = ObserverLocation(latitude: 51.5074, longitude: -0.1278, name: "ロンドン")
        let daily = calculator.darkNight(for: date, location: london, calendar: calendar)
        XCTAssertEqual(daily.status, .noAstronomicalNight)
        XCTAssertTrue(daily.darkIntervals.isEmpty)
    }

    /// 暗夜の区間は、天文薄明の外かつ月が地平線下であることを区間内の各時刻で確かめます。
    func testDarkIntervalsSatisfyBothConditions() {
        let daily = darkNight("2026-09-03T03:00:00Z")
        XCTAssertFalse(daily.darkIntervals.isEmpty)
        for interval in daily.darkIntervals {
            var date = interval.start.addingTimeInterval(120)
            while date < interval.end.addingTimeInterval(-120) {
                XCTAssertLessThan(calculator.altitude(of: .sun, at: date, location: tokyo), -18)
                XCTAssertLessThan(calculator.altitude(of: .moon, at: date, location: tokyo), 0)
                date.addTimeInterval(600)
            }
        }
        assertTime(daily.darkIntervals.first?.start, isNear: "2026-09-03T10:34:30Z", toleranceMinutes: 3)
        assertTime(daily.darkIntervals.first?.end, isNear: "2026-09-03T12:19:30Z", toleranceMinutes: 12)
    }

    private func darkNight(_ dateText: String) -> DarkNight {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = ISO8601DateFormatter().date(from: dateText)!
        return calculator.darkNight(for: date, location: tokyo, calendar: calendar)
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
