import Foundation

public enum CelestialBody: Sendable {
    case sun
    case moon
}

public struct AstronomyCalculator: Sendable {
    public static let synodicMonth = 29.530588853

    public init() {}

    public func dailyAstronomy(
        for date: Date,
        location: ObserverLocation,
        calendar: Calendar = .current
    ) -> DailyAstronomy {
        let localCalendar = calendar
        let start = localCalendar.startOfDay(for: date)
        let end = localCalendar.date(byAdding: .day, value: 1, to: start)!

        let sunEvents = bodyEvents(.sun, start: start, end: end, location: location)
        let moonEvents = bodyEvents(.moon, start: start, end: end, location: location)
        let twilight = twilightEvents(start: start, end: end, location: location)
        return DailyAstronomy(date: start, sun: sunEvents, moon: moonEvents, astronomicalTwilight: twilight)
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
        let threshold: (Date) -> Double = { date in
            switch body {
            case .sun:
                return -0.833
            case .moon:
                let distance = moonCoordinate(at: date).distance
                let parallax = radiansToDegrees(asin(min(1, 1 / max(1, distance))))
                return -0.5667 - 0.2725 * parallax
            }
        }
        let crossings = findCrossings(start: start, end: end, step: 300) { date in
            altitude(of: body, at: date, location: location) - threshold(date)
        }
        let rise = crossings.first(where: { $0.direction == .rising })?.date
        let set = crossings.first(where: { $0.direction == .setting })?.date
        let transit = maximumTime(start: start, end: end) { date in
            altitude(of: body, at: date, location: location)
        }
        let transitAltitude = transit.map { altitude(of: body, at: $0, location: location, includeRefraction: true) }
        return DailyBodyEvents(rise: rise, transit: transit, set: set, transitAltitude: transitAltitude)
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

        var low = samples[index - 1].0
        var high = samples[index + 1].0
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
