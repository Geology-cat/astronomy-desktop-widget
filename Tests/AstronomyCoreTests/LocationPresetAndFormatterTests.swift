import XCTest
@testable import AstronomyCore

final class LocationPresetAndFormatterTests: XCTestCase {
    private var tokyoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testPresetsCoverAllPrefecturesWithSeveralHokkaidoCities() {
        let prefectures = Set(LocationPreset.all.map(\.prefecture))
        XCTAssertEqual(prefectures.count, 47)
        XCTAssertGreaterThanOrEqual(LocationPreset.all.filter { $0.prefecture == "北海道" }.count, 5)
        XCTAssertEqual(Set(LocationPreset.all.map(\.id)).count, LocationPreset.all.count, "識別子が重複しています")
    }

    func testPresetCoordinatesAreInsideJapan() {
        for preset in LocationPreset.all {
            XCTAssertTrue((24...46).contains(preset.latitude), "\(preset.title) の緯度が範囲外です")
            XCTAssertTrue((122...146).contains(preset.longitude), "\(preset.title) の経度が範囲外です")
        }
    }

    func testGroupedPresetsKeepEveryPreset() {
        let grouped = LocationPreset.groupedByRegion
        XCTAssertEqual(grouped.first?.region, "北海道")
        XCTAssertEqual(grouped.reduce(0) { $0 + $1.presets.count }, LocationPreset.all.count)
    }

    func testMoonPhaseMomentUsesNowOnlyForToday() {
        let calendar = tokyoCalendar
        let now = ISO8601DateFormatter().date(from: "2026-10-17T12:34:00Z")!  // 日本時間 21:34
        let today = calendar.startOfDay(for: now)
        XCTAssertEqual(ObservationDay.moonPhaseMoment(for: today, now: now, calendar: calendar), now)

        let nextDay = ObservationDay.shifted(today, by: 1, calendar: calendar)
        let moment = ObservationDay.moonPhaseMoment(for: nextDay, now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: moment), 18)
        XCTAssertEqual(calendar.component(.hour, from: moment), 12)
    }

    func testRelativeTitle() {
        let calendar = tokyoCalendar
        let now = ISO8601DateFormatter().date(from: "2026-10-17T03:00:00Z")!
        let today = calendar.startOfDay(for: now)
        XCTAssertEqual(ObservationDay.relativeTitle(for: today, now: now, calendar: calendar), "今日")
        XCTAssertEqual(ObservationDay.relativeTitle(for: ObservationDay.shifted(today, by: 1, calendar: calendar), now: now, calendar: calendar), "明日")
        XCTAssertNil(ObservationDay.relativeTitle(for: ObservationDay.shifted(today, by: 5, calendar: calendar), now: now, calendar: calendar))
    }

    func testFormatterTexts() {
        let formatter = AstronomyTextFormatter(calendar: tokyoCalendar, locale: Locale(identifier: "ja_JP"))
        XCTAssertEqual(formatter.durationText(3 * 3600 + 5 * 60), "3時間05分")
        XCTAssertEqual(formatter.durationText(42 * 60), "42分")
        XCTAssertEqual(formatter.coordinate(latitude: 35.6895, longitude: 139.6917, fractionDigits: 4), "35.6895°N, 139.6917°E")
        XCTAssertEqual(formatter.coordinate(latitude: -33.9, longitude: -70.6), "33.90°S, 70.60°W")
        XCTAssertEqual(formatter.dayPrefix(.occursDaysLater(1)), "翌")
        XCTAssertEqual(formatter.previousDayBadge(.roseOnPreviousDay), "（前日）")
        XCTAssertEqual(formatter.time(nil), "—")
        let date = ISO8601DateFormatter().date(from: "2026-10-17T03:00:00Z")!
        XCTAssertEqual(formatter.time(date), "12:00")
    }
}
