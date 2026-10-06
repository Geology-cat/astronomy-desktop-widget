import AstronomyCore
import SwiftUI

struct AstronomyWidgetView: View {
    @ObservedObject var model: AstronomyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11 * model.textScale) {
            header
            HStack(alignment: .top, spacing: 10 * model.textScale) {
                sunCard
                moonCard
            }
            twilightCard
            darkNightCard
            if let notice = model.locationNotice {
                noticeRow(notice)
            }
        }
        .padding(14 * min(model.textScale, 1.15))
        .frame(width: widgetWidth)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .padding(16)
        .environment(\.colorScheme, .dark)
    }

    // 日付・地点・月齢バッジ・設定ボタンを 1 行にまとめたヘッダー
    private var header: some View {
        HStack(alignment: .center, spacing: 10 * model.textScale) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.now, format: .dateTime.year().month(.wide).day().weekday(.wide))
                    .font(widgetFont(21, weight: .semibold, design: .rounded))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text(model.activeLocation.name)
                    Text(coordinateText)
                        .foregroundStyle(.secondary)
                }
                .font(widgetFont(13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            moonBadge
            settingsButton
        }
    }

    // 月相の図と月齢はカードから外に出して、ヘッダーの一等地に置く
    private var moonBadge: some View {
        HStack(spacing: 7 * model.textScale) {
            MoonPhaseView(phase: model.moonPhase.fraction)
                .frame(width: 36 * model.textScale, height: 36 * model.textScale)
            VStack(alignment: .leading, spacing: 0) {
                Text("月齢")
                    .font(widgetFont(11))
                    .foregroundStyle(.secondary)
                Text(model.moonPhase.age, format: .number.precision(.fractionLength(1)))
                    .font(widgetFont(19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9 * min(model.textScale, 1.15))
        .padding(.vertical, 5 * min(model.textScale, 1.15))
        .background(.white.opacity(0.105), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var settingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .openAstronomySettings, object: nil)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(widgetFont(14, weight: .semibold))
                .frame(width: 32 * model.textScale, height: 32 * model.textScale)
                .background(.white.opacity(0.105), in: Circle())
        }
        .buttonStyle(.plain)
        .help("設定")
    }

    private var sunCard: some View {
        EventCard(title: "太陽", systemImage: "sun.max.fill", tint: .orange, textScale: model.textScale) {
            if let events = model.today?.sun {
                EventRow(label: "日の出", value: time(events.rise), textScale: model.textScale)
                EventRow(label: "南中", value: transit(events), textScale: model.textScale)
                EventRow(label: "日の入", value: time(events.set), textScale: model.textScale)
            } else {
                placeholder
            }
        }
    }

    private var moonCard: some View {
        EventCard(
            title: "月",
            systemImage: "moon.stars.fill",
            tint: Color(red: 0.76, green: 0.81, blue: 1.0),
            textScale: model.textScale
        ) {
            if let events = model.today?.moon {
                EventRow(label: "月の出", value: time(events.rise), textScale: model.textScale)
                EventRow(
                    label: "南中",
                    value: moonTransit(events),
                    note: previousDayBadge(events.transitNote),
                    textScale: model.textScale
                )
                EventRow(
                    label: "月の入",
                    value: moonTime(events.set, events.setNote),
                    note: previousDayBadge(events.setNote),
                    textScale: model.textScale
                )
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
    }

    private var twilightCard: some View {
        VStack(alignment: .leading, spacing: 9 * model.textScale) {
            Label("天文薄明", systemImage: "sparkles")
                .font(widgetFont(15, weight: .semibold))
                .foregroundStyle(Color(red: 0.70, green: 0.75, blue: 1.0))
            Grid(
                alignment: .leading,
                horizontalSpacing: 10 * model.textScale,
                verticalSpacing: 8 * model.textScale
            ) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    twilightHeader("朝の薄明開始")
                    twilightHeader("夕の薄明終了")
                }
                twilightRow(title: "今日", day: model.today)
                Divider().overlay(.white.opacity(0.14))
                twilightRow(title: "明日", day: model.tomorrow)
            }
        }
        .padding(12 * min(model.textScale, 1.15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.105), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func twilightRow(title: String, day: DailyAstronomy?) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(widgetFont(13, weight: .semibold))
                if let date = day?.date {
                    Text(date, format: .dateTime.month().day().weekday(.abbreviated))
                        .font(widgetFont(11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            twilightTime(systemImage: "sunrise.fill", value: time(day?.astronomicalTwilight.morning))
            twilightTime(systemImage: "sunset.fill", value: time(day?.astronomicalTwilight.evening))
        }
    }

    private func twilightHeader(_ text: String) -> some View {
        Text(text)
            .font(widgetFont(11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func twilightTime(systemImage: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(widgetFont(16, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 暗夜

    private static let darkNightTint = Color(red: 0.68, green: 0.60, blue: 1.0)

    /// 今日の夕方から明日の朝にかけて、太陽も月も影響しない時間帯を示すカードです。
    private var darkNightCard: some View {
        VStack(alignment: .leading, spacing: 9 * model.textScale) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label("暗夜", systemImage: "moon.zzz.fill")
                    .font(widgetFont(15, weight: .semibold))
                    .foregroundStyle(Self.darkNightTint)
                if let night = model.tonight {
                    Text(nightRangeTitle(night))
                        .font(widgetFont(11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let night = model.tonight, night.status == .dark {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("計")
                            .font(widgetFont(11))
                            .foregroundStyle(.secondary)
                        Text(durationText(night.totalDuration))
                            .font(widgetFont(15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                }
            }

            if let night = model.tonight {
                darkNightContent(night)
            } else {
                placeholder
            }
        }
        .padding(12 * min(model.textScale, 1.15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.105), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func darkNightContent(_ night: DarkNight) -> some View {
        switch night.status {
        case .dark:
            VStack(alignment: .leading, spacing: 6 * model.textScale) {
                ForEach(Array(night.darkIntervals.enumerated()), id: \.offset) { _, interval in
                    darkIntervalRow(interval, in: night)
                }
            }
            darkNightTimeline(night)
        case .moonlitAllNight:
            darkNightMessage(systemImage: "moon.fill", text: "一晩中月が出ているため、暗夜はありません")
            darkNightTimeline(night)
        case .noAstronomicalNight:
            darkNightMessage(systemImage: "sun.haze.fill", text: "天文薄明が終わらないため、暗夜はありません")
        }
    }

    /// 暗夜 1 区間分の行です。開始・終了が薄明と月のどちらで決まったかを添えます。
    private func darkIntervalRow(_ interval: DateInterval, in night: DarkNight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * model.textScale) {
            darkBoundary(time: nightTime(interval.start, in: night), cause: startCause(interval, in: night))
            Image(systemName: "arrow.right")
                .font(widgetFont(11, weight: .semibold))
                .foregroundStyle(.secondary)
            darkBoundary(time: nightTime(interval.end, in: night), cause: endCause(interval, in: night))
            Spacer(minLength: 4)
            if night.darkIntervals.count > 1 {
                Text(durationText(interval.duration))
                    .font(widgetFont(12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func darkBoundary(time: String, cause: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(time)
                .font(widgetFont(17, weight: .medium))
                .monospacedDigit()
            if let cause {
                Text(cause)
                    .font(widgetFont(11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func darkNightMessage(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .font(widgetFont(13))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// 夜（夕の天文薄明終了〜朝の天文薄明開始）全体に対する、暗夜と月明かりの配置を示します。
    @ViewBuilder
    private func darkNightTimeline(_ night: DarkNight) -> some View {
        if let first = night.astronomicalNight.first, let last = night.astronomicalNight.last {
            let span = DateInterval(start: first.start, end: last.end)
            VStack(spacing: 4 * model.textScale) {
                DarkNightTimeline(
                    span: span,
                    astronomicalNight: night.astronomicalNight,
                    darkIntervals: night.darkIntervals,
                    now: model.now,
                    darkTint: Self.darkNightTint
                )
                .frame(height: 9 * model.textScale)
                HStack(spacing: 8) {
                    Text(nightTime(span.start, in: night))
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    legend(color: Self.darkNightTint, text: "暗夜")
                    legend(color: DarkNightTimeline.moonlitColor, text: "月明かり")
                    Spacer(minLength: 4)
                    Text(nightTime(span.end, in: night))
                        .monospacedDigit()
                }
                .font(widgetFont(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6 * model.textScale, height: 6 * model.textScale)
            Text(text)
        }
    }

    /// 暗夜の開始が「夕の天文薄明終了」と「月の入」のどちらによるかを返します。
    private func startCause(_ interval: DateInterval, in night: DarkNight) -> String? {
        if interval.start <= night.window.start { return nil }
        let byTwilight = night.astronomicalNight.contains { abs($0.start.timeIntervalSince(interval.start)) < 1 }
        return byTwilight ? "薄明終了" : "月の入"
    }

    /// 暗夜の終了が「朝の天文薄明開始」と「月の出」のどちらによるかを返します。
    private func endCause(_ interval: DateInterval, in night: DarkNight) -> String? {
        if interval.end >= night.window.end { return nil }
        let byTwilight = night.astronomicalNight.contains { abs($0.end.timeIntervalSince(interval.end)) < 1 }
        return byTwilight ? "薄明開始" : "月の出"
    }

    /// 「10/6〜7」のように、どの夜の暗夜かを示します。
    private func nightRangeTitle(_ night: DarkNight) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: night.date)
        let day = calendar.component(.day, from: night.date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: night.date) else { return "\(month)/\(day)" }
        let nextMonth = calendar.component(.month, from: next)
        let nextDay = calendar.component(.day, from: next)
        let nextText = nextMonth == month ? "\(nextDay)" : "\(nextMonth)/\(nextDay)"
        return "\(month)/\(day)〜\(nextText)の夜"
    }

    /// 対象日の翌日以降の時刻には「翌」を付けます。
    private func nightTime(_ date: Date, in night: DarkNight) -> String {
        let isNextDay = Calendar.current.startOfDay(for: date) > night.date
        return (isNextDay ? "翌" : "") + time(date)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)分" }
        return "\(hours)時間" + String(format: "%02d分", rest)
    }

    private func noticeRow(_ notice: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "location.slash")
            Text(notice)
        }
        .font(widgetFont(12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 2)
    }

    private var coordinateText: String {
        String(format: "%.2f°, %.2f°", model.activeLocation.latitude, model.activeLocation.longitude)
    }

    private var widgetWidth: CGFloat {
        420 + (model.textScale - 1) * 180
    }

    private func widgetFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * model.textScale, weight: weight, design: design)
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// 翌日以降にまたぐ場合に、時刻へ直接付ける接頭辞です。
    private func dayPrefix(_ note: MoonEventNote) -> String {
        guard case .occursDaysLater(let days) = note else { return "" }
        return days == 1 ? "翌" : "\(days)日後"
    }

    /// 前日にのぼった月であることを、時刻の横へ小さく添えます。
    private func previousDayBadge(_ note: MoonEventNote) -> String? {
        guard case .roseOnPreviousDay = note else { return nil }
        return "（前日）"
    }

    private func moonTime(_ date: Date?, _ note: MoonEventNote) -> String {
        guard date != nil else { return "—" }
        return dayPrefix(note) + time(date)
    }

    private func moonTransit(_ events: DailyBodyEvents) -> String {
        guard let date = events.transit, let altitude = events.transitAltitude else { return "—" }
        let value = "\(time(date))（\(altitude.formatted(.number.precision(.fractionLength(1))))°）"
        return dayPrefix(events.transitNote) + value
    }

    private func transit(_ events: DailyBodyEvents) -> String {
        guard let date = events.transit, let altitude = events.transitAltitude else { return "—" }
        return "\(time(date))（\(altitude.formatted(.number.precision(.fractionLength(1))))°）"
    }
}

private struct EventCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let textScale: CGFloat
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, tint: Color, textScale: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.textScale = textScale
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * textScale) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17 * textScale, weight: .semibold))
                .foregroundStyle(tint)
            content
        }
        .padding(12 * min(textScale, 1.15))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.105), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EventRow: View {
    let label: String
    let value: String
    var note: String?
    let textScale: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let note {
                // 数字の列は右揃えのまま保ちたいので、注記は時刻の左へ小さく置きます。
                Text(note)
                    .font(.system(size: 11 * textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 15 * textScale))
    }
}

/// 夜（天文薄明の外）を 1 本の帯で表し、月明かりの区間と暗夜の区間を塗り分けます。
private struct DarkNightTimeline: View {
    static let moonlitColor = Color(red: 0.98, green: 0.89, blue: 0.62).opacity(0.55)

    let span: DateInterval
    let astronomicalNight: [DateInterval]
    let darkIntervals: [DateInterval]
    let now: Date
    let darkTint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .leading) {
                // 夜の間は、暗夜でなければ月が出ています。
                Rectangle().fill(Self.moonlitColor)
                // 高緯度などで夜の途中に天文薄明が挟まる場合は、その区間を薄く抜きます。
                ForEach(Array(twilightGaps.enumerated()), id: \.offset) { _, gap in
                    segment(gap, width: width, height: height).fill(Color.white.opacity(0.12))
                }
                ForEach(Array(darkIntervals.enumerated()), id: \.offset) { _, interval in
                    segment(interval, width: width, height: height)
                        .fill(
                            LinearGradient(
                                colors: [darkTint.opacity(0.85), darkTint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                if span.contains(now) {
                    // 現在時刻の位置に小さな目印を置きます。
                    Capsule()
                        .fill(.white)
                        .frame(width: 2, height: height)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .offset(x: fraction(now) * width - 1)
                }
            }
        }
        .clipShape(Capsule())
    }

    private var twilightGaps: [DateInterval] {
        zip(astronomicalNight, astronomicalNight.dropFirst()).compactMap { previous, next in
            next.start > previous.end ? DateInterval(start: previous.end, end: next.start) : nil
        }
    }

    private func segment(_ interval: DateInterval, width: CGFloat, height: CGFloat) -> some Shape {
        let start = fraction(interval.start) * width
        let end = fraction(interval.end) * width
        return Rectangle()
            .size(width: max(1, end - start), height: height)
            .offset(x: start)
    }

    private func fraction(_ date: Date) -> CGFloat {
        guard span.duration > 0 else { return 0 }
        let value = date.timeIntervalSince(span.start) / span.duration
        return CGFloat(min(1, max(0, value)))
    }
}
