import Foundation

public enum CelestialBody: Sendable {
    case sun
    case moon
}

public struct AstronomyCalculator: Sendable {
    public static let synodicMonth = 29.530588853

    public init() {}

    /// その日にのぼった月を追う際に、南中・月の入を探す時間の上限です。
    private static let moonTrackingWindow: TimeInterval = 36 * 3_600

    public func dailyAstronomy(
        for date: Date,
        location: ObserverLocation,
        calendar: Calendar = .current,
        moonMode: MoonDayMode = .withinDay
    ) -> DailyAstronomy {
        let localCalendar = calendar
        let start = localCalendar.startOfDay(for: date)
        let end = localCalendar.date(byAdding: .day, value: 1, to: start)!

        let sunEvents = bodyEvents(.sun, start: start, end: end, location: location)
        let moon = moonEvents(
            start: start,
            end: end,
            location: location,
            mode: moonMode,
            calendar: localCalendar
        )
        let twilight = twilightEvents(start: start, end: end, location: location)
        return DailyAstronomy(date: start, sun: sunEvents, moon: moon, astronomicalTwilight: twilight)
    }

    /// その日の夕方から翌朝にかけての暗夜を求めます。
    ///
    /// 対象日の正午から翌日の正午までを探索し、
    /// 「夕の天文薄明終了〜朝の天文薄明開始」の区間から、月が地平線上にある区間（月の出〜月の入）を除きます。
    /// 月の出入りの判定は、表示している月の出・月の入と同じ基準（上縁＋大気差）を使います。
    public func darkNight(
        for date: Date,
        location: ObserverLocation,
        calendar: Calendar = .current
    ) -> DarkNight {
        let start = calendar.startOfDay(for: date)
        let nextStart = calendar.date(byAdding: .day, value: 1, to: start)!
        // 夏時間の切り替え日でもずれないよう、加算ではなく「その日の12時」を指定します。
        let windowStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start)
            ?? start.addingTimeInterval(12 * 3_600)
        let windowEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: nextStart)
            ?? nextStart.addingTimeInterval(12 * 3_600)

        // 太陽中心高度が −18° 未満（天文薄明の外）なら正になります。
        let astronomicalNight = positiveIntervals(start: windowStart, end: windowEnd) { date in
            -18 - altitude(of: .sun, at: date, location: location)
        }
        // 月が出入りの基準高度より下（地平線下）なら正になります。
        let moonDown = positiveIntervals(start: windowStart, end: windowEnd) { date in
            horizonThreshold(.moon, at: date) - altitude(of: .moon, at: date, location: location)
        }

        return DarkNight(
            date: start,
            window: DateInterval(start: windowStart, end: windowEnd),
            astronomicalNight: astronomicalNight,
            darkIntervals: intersection(astronomicalNight, moonDown)
        )
    }

    public func moonPhase(at date: Date) -> MoonPhase {
        let sunLongitude = sunCoordinate(at: date).eclipticLongitude
        let moonLongitude = moonCoordinate(at: date).eclipticLongitude
        let elongation = normalizedDegrees(moonLongitude - sunLongitude)
        let fraction = elongation / 360
        let age = fraction * Self.synodicMonth
        let illumination = (1 - cos(degreesToRadians(elongation))) / 2
        return MoonPhase(fraction: fraction, age: age, illuminatedFraction: illumination)
    }

    public func altitude(
        of body: CelestialBody,
        at date: Date,
        location: ObserverLocation,
        includeRefraction: Bool = false
    ) -> Double {
        let coordinate = coordinate(of: body, at: date)
        let geocentric = geocentricAltitude(coordinate: coordinate, at: date, location: location)
        var topocentric = geocentric

        if body == .moon {
            let horizontalParallax = asin(min(1, 1 / max(1, coordinate.distance)))
            topocentric = atan2(
                sin(geocentric) - sin(horizontalParallax),
                cos(geocentric)
            )
        }

        var degrees = radiansToDegrees(topocentric)
        if includeRefraction, degrees > -1 {
            degrees += atmosphericRefraction(altitudeDegrees: degrees)
        }
        return degrees
    }

    public func sunCoordinate(at date: Date) -> EquatorialCoordinate {
        let jd = julianDate(date)
        let t = (jd - 2_451_545.0) / 36_525
        let meanLongitude = normalizedDegrees(280.46646 + t * (36_000.76983 + 0.0003032 * t))
        let meanAnomaly = normalizedDegrees(357.52911 + t * (35_999.05029 - 0.0001537 * t))
        let anomalyRadians = degreesToRadians(meanAnomaly)
        let equationOfCenter = sin(anomalyRadians) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * anomalyRadians) * (0.019993 - 0.000101 * t)
            + sin(3 * anomalyRadians) * 0.000289
        let trueLongitude = meanLongitude + equationOfCenter
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(degreesToRadians(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(degreesToRadians(omega))
        let lambda = degreesToRadians(apparentLongitude)
        let epsilon = degreesToRadians(obliquity)
        let rightAscension = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let declination = asin(sin(epsilon) * sin(lambda))
        return EquatorialCoordinate(
            rightAscension: normalizedRadians(rightAscension),
            declination: declination,
            distance: 1,
            eclipticLongitude: normalizedDegrees(apparentLongitude)
        )
    }

    public func moonCoordinate(at date: Date) -> EquatorialCoordinate {
        // Paul Schlyter の低精度軌道要素に主要摂動項を加えた実用計算です。
        let d = julianDate(date) - 2_451_543.5
        let ascendingNode = normalizedDegrees(125.1228 - 0.0529538083 * d)
        let inclination = 5.1454
        let argumentOfPerigee = normalizedDegrees(318.0634 + 0.1643573223 * d)
        let eccentricity = 0.0549
        let meanAnomaly = normalizedDegrees(115.3654 + 13.0649929509 * d)

        let m = degreesToRadians(meanAnomaly)
        var eccentricAnomaly = m + eccentricity * sin(m) * (1 + eccentricity * cos(m))
        for _ in 0..<6 {
            eccentricAnomaly -= (eccentricAnomaly - eccentricity * sin(eccentricAnomaly) - m)
                / (1 - eccentricity * cos(eccentricAnomaly))
        }

        let xv = cos(eccentricAnomaly) - eccentricity
        let yv = sqrt(1 - eccentricity * eccentricity) * sin(eccentricAnomaly)
        let trueAnomaly = atan2(yv, xv)
        var distance = sqrt(xv * xv + yv * yv) * 60.2666

        let node = degreesToRadians(ascendingNode)
        let inclinationRadians = degreesToRadians(inclination)
        let orbitalLongitude = trueAnomaly + degreesToRadians(argumentOfPerigee)
        let x = distance * (cos(node) * cos(orbitalLongitude) - sin(node) * sin(orbitalLongitude) * cos(inclinationRadians))
        let y = distance * (sin(node) * cos(orbitalLongitude) + cos(node) * sin(orbitalLongitude) * cos(inclinationRadians))
        let z = distance * sin(orbitalLongitude) * sin(inclinationRadians)

        var longitude = radiansToDegrees(atan2(y, x))
        var latitude = radiansToDegrees(atan2(z, sqrt(x * x + y * y)))

        let sunMeanLongitude = normalizedDegrees(282.9404 + 0.0000470935 * d + 356.0470 + 0.9856002585 * d)
        let sunMeanAnomaly = normalizedDegrees(356.0470 + 0.9856002585 * d)
        let moonMeanLongitude = normalizedDegrees(ascendingNode + argumentOfPerigee + meanAnomaly)
        let elongation = normalizedDegrees(moonMeanLongitude - sunMeanLongitude)
        let argumentOfLatitude = normalizedDegrees(moonMeanLongitude - ascendingNode)

        longitude += -1.274 * sine(meanAnomaly - 2 * elongation)
            + 0.658 * sine(2 * elongation)
            - 0.186 * sine(sunMeanAnomaly)
            - 0.059 * sine(2 * meanAnomaly - 2 * elongation)
            - 0.057 * sine(meanAnomaly - 2 * elongation + sunMeanAnomaly)
            + 0.053 * sine(meanAnomaly + 2 * elongation)
            + 0.046 * sine(2 * elongation - sunMeanAnomaly)
            + 0.041 * sine(meanAnomaly - sunMeanAnomaly)
            - 0.035 * sine(elongation)
            - 0.031 * sine(meanAnomaly + sunMeanAnomaly)
            - 0.015 * sine(2 * argumentOfLatitude - 2 * elongation)
            + 0.011 * sine(meanAnomaly - 4 * elongation)

        latitude += -0.173 * sine(argumentOfLatitude - 2 * elongation)
            - 0.055 * sine(meanAnomaly - argumentOfLatitude - 2 * elongation)
            - 0.046 * sine(meanAnomaly + argumentOfLatitude - 2 * elongation)
            + 0.033 * sine(argumentOfLatitude + 2 * elongation)
            + 0.017 * sine(2 * meanAnomaly + argumentOfLatitude)

        distance += -0.58 * cosine(meanAnomaly - 2 * elongation) - 0.46 * cosine(2 * elongation)

        let longitudeRadians = degreesToRadians(longitude)
        let latitudeRadians = degreesToRadians(latitude)
        let eclipticX = cos(longitudeRadians) * cos(latitudeRadians)
        let eclipticY = sin(longitudeRadians) * cos(latitudeRadians)
        let eclipticZ = sin(latitudeRadians)
        let obliquity = degreesToRadians(23.4393 - 0.0000003563 * d)
        let equatorialX = eclipticX
        let equatorialY = eclipticY * cos(obliquity) - eclipticZ * sin(obliquity)
        let equatorialZ = eclipticY * sin(obliquity) + eclipticZ * cos(obliquity)

        return EquatorialCoordinate(
            rightAscension: normalizedRadians(atan2(equatorialY, equatorialX)),
            declination: atan2(equatorialZ, sqrt(equatorialX * equatorialX + equatorialY * equatorialY)),
            distance: distance,
            eclipticLongitude: normalizedDegrees(longitude)
        )
    }

    private func bodyEvents(
        _ body: CelestialBody,
        start: Date,
        end: Date,
        location: ObserverLocation
    ) -> DailyBodyEvents {
        let crossings = horizonCrossings(body, start: start, end: end, location: location)
        let rise = crossings.first(where: { $0.direction == .rising })?.date
        let set = crossings.first(where: { $0.direction == .setting })?.date
        let transit = maximumTime(start: start, end: end) { date in
            altitude(of: body, at: date, location: location)
        }
        let transitAltitude = transit.map { altitude(of: body, at: $0, location: location, includeRefraction: true) }
        return DailyBodyEvents(rise: rise, transit: transit, set: set, transitAltitude: transitAltitude)
    }

    /// 出入りの判定に使う見かけの地平線高度です。月は距離によって視差が変わります。
    private func horizonThreshold(_ body: CelestialBody, at date: Date) -> Double {
        switch body {
        case .sun:
            return -0.833
        case .moon:
            let distance = moonCoordinate(at: date).distance
            let parallax = radiansToDegrees(asin(min(1, 1 / max(1, distance))))
            return -0.5667 - 0.2725 * parallax
        }
    }

    private func horizonCrossings(
        _ body: CelestialBody,
        start: Date,
        end: Date,
        location: ObserverLocation
    ) -> [Crossing] {
        findCrossings(start: start, end: end, step: 300) { date in
            altitude(of: body, at: date, location: location) - horizonThreshold(body, at: date)
        }
    }

    /// 月の南中・月の入を、指定したモードに従って求めます。
    private func moonEvents(
        start: Date,
        end: Date,
        location: ObserverLocation,
        mode: MoonDayMode,
        calendar: Calendar
    ) -> DailyBodyEvents {
        switch mode {
        case .withinDay:
            let events = bodyEvents(.moon, start: start, end: end, location: location)
            // その日の月の出より前に起きる南中・月の入は、前日にのぼった月のものです。
            // その日に月の出がない場合も、のぼったのは前日以前になります。
            func note(_ date: Date?) -> MoonEventNote {
                guard let date else { return .none }
                guard let rise = events.rise, date >= rise else { return .roseOnPreviousDay }
                return .none
            }
            return DailyBodyEvents(
                rise: events.rise,
                transit: events.transit,
                set: events.set,
                transitAltitude: events.transitAltitude,
                transitNote: note(events.transit),
                setNote: note(events.set)
            )

        case .risenThatDay:
            let rise = horizonCrossings(.moon, start: start, end: end, location: location)
                .first(where: { $0.direction == .rising })?.date
            // その日に月の出がなければ、追いかける対象の月が存在しません。
            guard let rise else {
                return DailyBodyEvents(rise: nil, transit: nil, set: nil, transitAltitude: nil)
            }
            let searchEnd = rise.addingTimeInterval(Self.moonTrackingWindow)
            let set = horizonCrossings(.moon, start: rise, end: searchEnd, location: location)
                .first(where: { $0.direction == .setting })?.date
            let transit = firstMaximumTime(start: rise, end: set ?? searchEnd) { date in
                altitude(of: .moon, at: date, location: location)
            }
            let transitAltitude = transit.map {
                altitude(of: .moon, at: $0, location: location, includeRefraction: true)
            }
            // 月の出は必ず当日なので、当日から何日ずれたかだけを見ます。
            func note(_ date: Date?) -> MoonEventNote {
                guard let date else { return .none }
                let days = calendar.dateComponents(
                    [.day],
                    from: start,
                    to: calendar.startOfDay(for: date)
                ).day ?? 0
                return days > 0 ? .occursDaysLater(days) : .none
            }
            return DailyBodyEvents(
                rise: rise,
                transit: transit,
                set: set,
                transitAltitude: transitAltitude,
                transitNote: note(transit),
                setNote: note(set)
            )
        }
    }

    private func twilightEvents(start: Date, end: Date, location: ObserverLocation) -> TwilightEvents {
        let crossings = findCrossings(start: start, end: end, step: 300) { date in
            altitude(of: .sun, at: date, location: location) + 18
        }
        return TwilightEvents(
            morning: crossings.first(where: { $0.direction == .rising })?.date,
            evening: crossings.first(where: { $0.direction == .setting })?.date
        )
    }

    private enum CrossingDirection { case rising, setting }
    private struct Crossing { let date: Date; let direction: CrossingDirection }

    /// value が正となる区間を、ゼロ点（通過時刻）を境に切り出します。
    private func positiveIntervals(
        start: Date,
        end: Date,
        value: (Date) -> Double
    ) -> [DateInterval] {
        var result: [DateInterval] = []
        var openedAt: Date? = value(start) > 0 ? start : nil
        for crossing in findCrossings(start: start, end: end, step: 300, value: value) {
            switch crossing.direction {
            case .rising:
                if openedAt == nil { openedAt = crossing.date }
            case .setting:
                if let opened = openedAt, crossing.date > opened {
                    result.append(DateInterval(start: opened, end: crossing.date))
                }
                openedAt = nil
            }
        }
        if let opened = openedAt, end > opened {
            result.append(DateInterval(start: opened, end: end))
        }
        return result
    }

    /// 時刻順に並んだ 2 つの区間列の共通部分を求めます。
    private func intersection(_ lhs: [DateInterval], _ rhs: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        var i = 0
        var j = 0
        while i < lhs.count, j < rhs.count {
            let start = max(lhs[i].start, rhs[j].start)
            let end = min(lhs[i].end, rhs[j].end)
            // 計算誤差で生じる 1 分未満の断片は捨てます。
            if end.timeIntervalSince(start) >= 60 {
                result.append(DateInterval(start: start, end: end))
            }
            if lhs[i].end < rhs[j].end { i += 1 } else { j += 1 }
        }
        return result
    }

    private func findCrossings(
        start: Date,
        end: Date,
        step: TimeInterval,
        value: (Date) -> Double
    ) -> [Crossing] {
        var result: [Crossing] = []
        var leftDate = start
        var leftValue = value(leftDate)
        var rightDate = min(start.addingTimeInterval(step), end)

        while leftDate < end {
            let rightValue = value(rightDate)
            if leftValue == 0 || leftValue.sign != rightValue.sign {
                var low = leftDate
                var high = rightDate
                var lowValue = leftValue
                for _ in 0..<22 {
                    let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    let middleValue = value(middle)
                    if lowValue.sign == middleValue.sign {
                        low = middle
                        lowValue = middleValue
                    } else {
                        high = middle
                    }
                }
                let eventDate = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                result.append(Crossing(date: eventDate, direction: rightValue > leftValue ? .rising : .setting))
            }
            if rightDate >= end { break }
            leftDate = rightDate
            leftValue = rightValue
            rightDate = min(rightDate.addingTimeInterval(step), end)
        }
        return result
    }

    private func maximumTime(start: Date, end: Date, value: (Date) -> Double) -> Date? {
        let sampleStep: TimeInterval = 900
        var samples: [(Date, Double)] = []
        var date = start
        while date <= end {
            samples.append((date, value(date)))
            date = date.addingTimeInterval(sampleStep)
        }
        guard let index = samples.indices.max(by: { samples[$0].1 < samples[$1].1 }),
              index > samples.startIndex,
              index < samples.index(before: samples.endIndex) else { return nil }

        return refineMaximum(low: samples[index - 1].0, high: samples[index + 1].0, value: value)
    }

    /// start より後に最初に現れる極大を返します。窓の中に複数の南中があっても先頭を選びます。
    private func firstMaximumTime(start: Date, end: Date, value: (Date) -> Double) -> Date? {
        let sampleStep: TimeInterval = 900
        var previousDate = start
        var previousValue = value(previousDate)
        var currentDate = start.addingTimeInterval(sampleStep)
        guard currentDate < end else { return nil }
        var currentValue = value(currentDate)

        while true {
            let nextDate = currentDate.addingTimeInterval(sampleStep)
            guard nextDate <= end else { return nil }
            let nextValue = value(nextDate)
            // 左は真に増加していることを求め、start 直後の平坦部で誤検出しないようにします。
            if currentValue > previousValue, currentValue >= nextValue {
                return refineMaximum(low: previousDate, high: nextDate, value: value)
            }
            previousDate = currentDate
            previousValue = currentValue
            currentDate = nextDate
            currentValue = nextValue
        }
    }

    private func refineMaximum(low: Date, high: Date, value: (Date) -> Double) -> Date {
        var low = low
        var high = high
        for _ in 0..<32 {
            let span = high.timeIntervalSince(low)
            let first = low.addingTimeInterval(span / 3)
            let second = high.addingTimeInterval(-span / 3)
            if value(first) < value(second) {
                low = first
            } else {
                high = second
            }
        }
        return low.addingTimeInterval(high.timeIntervalSince(low) / 2)
    }

    private func coordinate(of body: CelestialBody, at date: Date) -> EquatorialCoordinate {
        switch body {
        case .sun: return sunCoordinate(at: date)
        case .moon: return moonCoordinate(at: date)
        }
    }

    private func geocentricAltitude(
        coordinate: EquatorialCoordinate,
        at date: Date,
        location: ObserverLocation
    ) -> Double {
        let latitude = degreesToRadians(location.latitude)
        let localSidereal = degreesToRadians(normalizedDegrees(greenwichSiderealTime(at: date) + location.longitude))
        var hourAngle = localSidereal - coordinate.rightAscension
        if hourAngle > .pi { hourAngle -= 2 * .pi }
        if hourAngle < -.pi { hourAngle += 2 * .pi }
        return asin(
            sin(latitude) * sin(coordinate.declination)
                + cos(latitude) * cos(coordinate.declination) * cos(hourAngle)
        )
    }

    private func atmosphericRefraction(altitudeDegrees: Double) -> Double {
        guard altitudeDegrees > -1 else { return 0 }
        let denominator = tan(degreesToRadians(altitudeDegrees + 10.3 / (altitudeDegrees + 5.11)))
        guard denominator.isFinite, abs(denominator) > 0.00001 else { return 0 }
        return (1.02 / denominator) / 60
    }

    private func greenwichSiderealTime(at date: Date) -> Double {
        let jd = julianDate(date)
        let t = (jd - 2_451_545.0) / 36_525
        return normalizedDegrees(
            280.46061837
                + 360.98564736629 * (jd - 2_451_545.0)
                + 0.000387933 * t * t
                - t * t * t / 38_710_000
        )
    }

    private func julianDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private func sine(_ degrees: Double) -> Double { sin(degreesToRadians(degrees)) }
    private func cosine(_ degrees: Double) -> Double { cos(degreesToRadians(degrees)) }
    private func degreesToRadians(_ value: Double) -> Double { value * .pi / 180 }
    private func radiansToDegrees(_ value: Double) -> Double { value * 180 / .pi }

    private func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

    private func normalizedRadians(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 2 * .pi)
        return result >= 0 ? result : result + 2 * .pi
    }
}
