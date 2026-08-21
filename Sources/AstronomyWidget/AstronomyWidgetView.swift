import AstronomyCore
import SwiftUI

struct AstronomyWidgetView: View {
    @ObservedObject var model: AstronomyViewModel

    var body: some View {
        VStack(spacing: 14 * model.textScale) {
            header
            HStack(alignment: .top, spacing: 12) {
                sunCard
                moonCard
            }
            twilightCard
            footer
        }
        .padding(18 * min(model.textScale, 1.15))
        .frame(width: widgetWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .padding(24)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.now, format: .dateTime.year().month(.wide).day().weekday(.wide))
                    .font(widgetFont(20, weight: .semibold, design: .rounded))
                    .tracking(-0.3)
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                    Text(model.activeLocation.name)
                    Text(coordinateText)
                        .foregroundStyle(.secondary)
                }
                .font(widgetFont(11))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                NotificationCenter.default.post(name: .openAstronomySettings, object: nil)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(widgetFont(13, weight: .semibold))
                    .frame(width: 30 * model.textScale, height: 30 * model.textScale)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .help("設定")
        }
    }

    private var sunCard: some View {
        EventCard(title: "太陽", systemImage: "sun.max.fill", tint: .orange, textScale: model.textScale) {
            if let events = model.today?.sun {
                EventRow(label: "日の出", value: time(events.rise), textScale: model.textScale)
                EventRow(label: "南中", value: transit(events), textScale: model.textScale)
                EventRow(label: "日の入", value: time(events.set), textScale: model.textScale)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private var moonCard: some View {
        EventCard(title: "月", systemImage: "moon.stars.fill", tint: Color(red: 0.72, green: 0.78, blue: 1.0), textScale: model.textScale) {
            HStack(spacing: 10) {
                MoonPhaseView(phase: model.moonPhase.fraction)
                    .frame(width: 50 * model.textScale, height: 50 * model.textScale)
                VStack(alignment: .leading, spacing: 2) {
                    Text("月齢")
                        .font(widgetFont(11))
                        .foregroundStyle(.secondary)
                    Text(model.moonPhase.age, format: .number.precision(.fractionLength(1)))
                        .font(widgetFont(21, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let events = model.today?.moon {
                EventRow(label: "月の出", value: time(events.rise), textScale: model.textScale)
                EventRow(label: "南中", value: transit(events), textScale: model.textScale)
                EventRow(label: "月の入", value: time(events.set), textScale: model.textScale)
            }
        }
    }

    private var twilightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("天文薄明", systemImage: "sparkles")
                .font(widgetFont(14, weight: .semibold))
                .foregroundStyle(Color(red: 0.67, green: 0.72, blue: 1.0))
            TwilightRow(title: "今日", date: model.today?.date, events: model.today?.astronomicalTwilight, textScale: model.textScale, time: time)
            Divider().overlay(.white.opacity(0.10))
            TwilightRow(title: "明日", date: model.tomorrow?.date, events: model.tomorrow?.astronomicalTwilight, textScale: model.textScale, time: time)
        }
        .padding(14 * min(model.textScale, 1.15))
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let notice = model.locationNotice {
                Image(systemName: "location.slash")
                Text(notice)
            } else {
                Image(systemName: "arrow.clockwise")
                Text("毎分更新")
            }
            Spacer()
            Text("ドラッグして移動")
        }
        .font(widgetFont(10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private var coordinateText: String {
        String(format: "%.2f°, %.2f°", model.activeLocation.latitude, model.activeLocation.longitude)
    }

    private var widgetWidth: CGFloat {
        430 + (model.textScale - 1) * 140
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
        VStack(alignment: .leading, spacing: 10 * textScale) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15 * textScale, weight: .semibold))
                .foregroundStyle(tint)
            content
        }
        .padding(14 * min(textScale, 1.15))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EventRow: View {
    let label: String
    let value: String
    let textScale: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.system(size: 12 * textScale))
    }
}

private struct TwilightRow: View {
    let title: String
    let date: Date?
    let events: TwilightEvents?
    let textScale: CGFloat
    let time: (Date?) -> String

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold)
                if let date {
                    Text(date, format: .dateTime.month().day().weekday(.abbreviated))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11 * textScale))
            .frame(width: 72 * textScale, alignment: .leading)
            Label(time(events?.morning), systemImage: "sunrise.fill")
            Spacer(minLength: 4)
            Label(time(events?.evening), systemImage: "sunset.fill")
        }
        .font(.system(size: 12 * textScale, weight: .medium))
        .monospacedDigit()
    }
}
