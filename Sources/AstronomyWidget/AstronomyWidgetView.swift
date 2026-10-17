import AstronomyCore
import SwiftUI

struct AstronomyWidgetView: View {
    @ObservedObject var model: AstronomyViewModel
    @State private var isShowingDatePicker = false

    private static let formatter = AstronomyTextFormatter()

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
                dateNavigator
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

    /// 表示日の切り替え（前日・翌日・カレンダー・今日へ戻る）です。
    private var dateNavigator: some View {
        HStack(spacing: 4 * model.textScale) {
            dayStepButton(systemImage: "chevron.left", help: "前の日") { model.shiftDay(by: -1) }
            Button {
                isShowingDatePicker.toggle()
            } label: {
                Text(Self.formatter.fullDate(model.selectedDay))
                    .font(widgetFont(19, weight: .semibold, design: .rounded))
                    .tracking(-0.3)
                    .foregroundStyle(model.isShowingToday ? Color.primary : Color.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .buttonStyle(.plain)
            .help("日付を選ぶ")
            .popover(isPresented: $isShowingDatePicker, arrowEdge: .bottom) {
                datePickerPopover
            }
            dayStepButton(systemImage: "chevron.right", help: "次の日") { model.shiftDay(by: 1) }
            if !model.isShowingToday {
                Button("今日") { model.showToday() }
                    .buttonStyle(.plain)
                    .font(widgetFont(11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.16), in: Capsule())
                    .help("今日の表示に戻る")
            }
        }
    }

    private func dayStepButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(widgetFont(11, weight: .bold))
                .frame(width: 20 * model.textScale, height: 20 * model.textScale)
                .background(.white.opacity(0.105), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var datePickerPopover: some View {
        VStack(alignment: .trailing, spacing: 8) {
            DatePicker(
                "表示する日",
                selection: Binding(get: { model.selectedDay }, set: { model.selectDay($0) }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            Button("今日") {
                model.showToday()
                isShowingDatePicker = false
            }
        }
        .padding(12)
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
                twilightRow(title: dayTitle(model.selectedDay, fallback: "当日"), day: model.today)
                Divider().overlay(.white.opacity(0.14))
                twilightRow(title: dayTitle(model.nextDay, fallback: "翌日"), day: model.tomorrow)
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
                    Text(Self.formatter.shortDate(date))
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

    private func startCause(_ interval: DateInterval, in night: DarkNight) -> String? {
        Self.formatter.startCause(interval, in: night)
    }

    private func endCause(_ interval: DateInterval, in night: DarkNight) -> String? {
        Self.formatter.endCause(interval, in: night)
    }

    private func nightRangeTitle(_ night: DarkNight) -> String {
        Self.formatter.nightRangeTitle(night)
    }

    private func nightTime(_ date: Date, in night: DarkNight) -> String {
        Self.formatter.nightTime(date, in: night)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        Self.formatter.durationText(duration)
    }

    /// 「今日」「明日」などの見出しです。離れた日は fallback（当日・翌日）を使います。
    private func dayTitle(_ day: Date, fallback: String) -> String {
        ObservationDay.relativeTitle(for: day, now: model.now) ?? fallback
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
        Self.formatter.coordinate(latitude: model.activeLocation.latitude, longitude: model.activeLocation.longitude)
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
        Self.formatter.time(date)
    }

    private func previousDayBadge(_ note: MoonEventNote) -> String? {
        Self.formatter.previousDayBadge(note)
    }

    private func moonTime(_ date: Date?, _ note: MoonEventNote) -> String {
        Self.formatter.moonTime(date, note)
    }

    private func moonTransit(_ events: DailyBodyEvents) -> String {
        Self.formatter.transit(events)
    }

    private func transit(_ events: DailyBodyEvents) -> String {
        Self.formatter.transit(events)
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
