import AppKit

/// macOS 13 版の AstronomyWidgetView を AppKit で再現したウィジェット本体です。
/// 表示内容が変わるたびに中身を組み直します（1 分に 1 回程度なので負荷は問題になりません）。
final class LegacyWidgetView: NSView, NSPopoverDelegate {
    private let model: AstronomyViewModel
    private let formatter = AstronomyTextFormatter()
    private let effectView = NSVisualEffectView()
    private let borderView = BorderView()
    private var contentStack: NSStackView?
    private var widthConstraint: NSLayoutConstraint?
    private var dateButton: NSButton?
    private var datePopover: NSPopover?
    private var datePicker: NSDatePicker?

    /// 中身を組み直した後に呼ばれます。パネルの大きさを合わせるのに使います。
    var onLayoutChange: (() -> Void)?

    private var scale: CGFloat { model.textScale }
    /// カードなどの余白は、文字が大きくなっても広がりすぎないようにします。
    private var paddingScale: CGFloat { min(scale, 1.15) }
    private var widgetWidth: CGFloat { 420 + (scale - 1) * 180 }

    init(model: AstronomyViewModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 470))
        appearance = NSAppearance(named: .vibrantDark)

        effectView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
        } else {
            effectView.material = .dark
        }
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: 22)
        addSubview(effectView)

        // 明るい壁紙の上でも macOS 13 版と同じくらいの濃さになるよう、暗い色を重ねます。
        let tintView = CardView(cornerRadius: 22, color: NSColor(calibratedWhite: 0.10, alpha: 0.62))
        effectView.addSubview(tintView)
        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: effectView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        borderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(borderView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderView.topAnchor.constraint(equalTo: topAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let width = effectView.widthAnchor.constraint(equalToConstant: widgetWidth)
        width.isActive = true
        widthConstraint = width
        render()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { true }

    // MARK: - 組み立て

    func render() {
        contentStack?.removeFromSuperview()
        widthConstraint?.constant = widgetWidth

        var sections: [NSView] = [header, eventCards, twilightCard, darkNightCard]
        if let notice = model.locationNotice {
            sections.append(noticeRow(notice))
        }
        let stack = vstack(sections, spacing: 11 * scale)
        effectView.addSubview(stack)
        let padding = 14 * paddingScale
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -padding),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: padding),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -padding)
        ])
        sections.forEach { fillWidth($0, of: stack) }
        contentStack = stack
        onLayoutChange?()
    }

    // MARK: ヘッダー

    // 日付・地点・月齢バッジ・設定ボタンを 1 行にまとめたヘッダー
    private var header: NSView {
        let badge = moonBadge
        let settings = settingsButton
        // SwiftUI 版の minimumScaleFactor の代わりに、残りの幅へ収まるよう日付の文字を縮めます。
        let innerWidth = widgetWidth - 2 * 14 * paddingScale
        let reserved = badge.fittingSize.width + settings.fittingSize.width + 3 * 10 * scale + 4
        let navigator = dateNavigator(maxWidth: innerWidth - reserved)
        let locationRow = hstack([
            Icon.view(symbol: "location.fill", fallback: "➤", pointSize: 11 * scale, color: Palette.primary),
            label(model.activeLocation.name, size: 13),
            label(
                formatter.coordinate(latitude: model.activeLocation.latitude, longitude: model.activeLocation.longitude),
                size: 13,
                color: Palette.secondary
            )
        ], spacing: 4, alignment: .centerY)
        // 幅が足りないときは地点の行だけを省略表示にします。
        locationRow.setClippingResistancePriority(.defaultLow, for: .horizontal)
        let titleColumn = vstack([navigator, locationRow], spacing: 2)
        for view in [badge, settings, navigator] {
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        return hstack([titleColumn, spacer(), badge, settings], spacing: 10 * scale, alignment: .centerY)
    }

    /// 表示日の切り替え（前日・翌日・カレンダー・今日へ戻る）です。
    private func dateNavigator(maxWidth: CGFloat) -> NSStackView {
        var trailing: [NSView] = []
        if !model.isShowingToday {
            let today = textButton("今日", font: font(11, weight: .semibold), color: Palette.primary, action: #selector(showToday))
            today.toolTip = "今日の表示に戻る"
            trailing.append(pill(today))
        }
        let stepSize = 20 * scale
        let spacing = 4 * scale
        let fixedWidth = 2 * stepSize + trailing.reduce(0) { $0 + $1.fittingSize.width }
            + spacing * CGFloat(1 + trailing.count + 1)
        let title = formatter.fullDate(model.selectedDay)
        var dateFont = font(19, weight: .semibold, rounded: true)
        let naturalWidth = (title as NSString).size(withAttributes: [.font: dateFont]).width + 4
        let available = maxWidth - fixedWidth
        if naturalWidth > available, available > 0 {
            let factor = max(0.6, available / naturalWidth)
            dateFont = font(19 * factor, weight: .semibold, rounded: true)  // font() 内で文字サイズ倍率が掛かります
        }
        let dateButton = textButton(
            title,
            font: dateFont,
            color: model.isShowingToday ? Palette.primary : Palette.otherDay,
            action: #selector(toggleDatePicker)
        )
        dateButton.toolTip = "日付を選ぶ"
        dateButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.dateButton = dateButton
        let views: [NSView] = [
            circleButton(symbol: "chevron.left", fallback: "‹", size: stepSize, action: #selector(previousDay), help: "前の日"),
            dateButton,
            circleButton(symbol: "chevron.right", fallback: "›", size: stepSize, action: #selector(nextDay), help: "次の日")
        ] + trailing
        return hstack(views, spacing: spacing, alignment: .centerY)
    }

    // 月相の図と月齢はカードから外に出して、ヘッダーの一等地に置く
    private var moonBadge: NSView {
        let moonView = MoonPhaseNSView()
        moonView.phase = model.moonPhase.fraction
        moonView.translatesAutoresizingMaskIntoConstraints = false
        moonView.widthAnchor.constraint(equalToConstant: 36 * scale).isActive = true
        moonView.heightAnchor.constraint(equalToConstant: 36 * scale).isActive = true
        moonView.toolTip = "月の概形"
        let ageColumn = vstack([
            label("月齢", size: 11, color: Palette.secondary),
            label(String(format: "%.1f", model.moonPhase.age), size: 19, weight: .semibold, rounded: true, monospaced: true)
        ], spacing: 0)
        ageColumn.arrangedSubviews.forEach { $0.setContentCompressionResistancePriority(.required, for: .horizontal) }
        let content = hstack([moonView, ageColumn], spacing: 7 * scale, alignment: .centerY)
        return card(content, cornerRadius: 14, horizontalPadding: 9 * paddingScale, verticalPadding: 5 * paddingScale)
    }

    private var settingsButton: NSView {
        let button = circleButton(symbol: "gearshape.fill", fallback: "⚙︎", size: 32 * scale, action: #selector(openSettings), help: "設定")
        return button
    }

    // MARK: 太陽・月

    private var eventCards: NSView {
        let sun = eventCard(title: "太陽", symbol: "sun.max.fill", fallback: "☀︎", tint: Palette.sun, rows: sunRows)
        let moon = eventCard(title: "月", symbol: "moon.stars.fill", fallback: "☾", tint: Palette.moon, rows: moonRows)
        let row = hstack([sun, moon], spacing: 10 * scale, alignment: .top)
        row.distribution = .fillEqually
        // 2 枚のカードの高さをそろえます。
        sun.heightAnchor.constraint(equalTo: moon.heightAnchor).isActive = true
        return row
    }

    private var sunRows: [NSView] {
        guard let events = model.today?.sun else { return [placeholder] }
        return [
            eventRow(label: "日の出", value: formatter.time(events.rise)),
            eventRow(label: "南中", value: formatter.transit(events)),
            eventRow(label: "日の入", value: formatter.time(events.set))
        ]
    }

    private var moonRows: [NSView] {
        guard let events = model.today?.moon else { return [placeholder] }
        return [
            eventRow(label: "月の出", value: formatter.time(events.rise)),
            eventRow(label: "南中", value: formatter.transit(events), note: formatter.previousDayBadge(events.transitNote)),
            eventRow(label: "月の入", value: formatter.moonTime(events.set, events.setNote), note: formatter.previousDayBadge(events.setNote))
        ]
    }

    private func eventCard(title: String, symbol: String, fallback: String, tint: NSColor, rows: [NSView]) -> NSView {
        let titleRow = hstack([
            Icon.view(symbol: symbol, fallback: fallback, pointSize: 15 * scale, color: tint, weight: .semibold),
            label(title, size: 17, weight: .semibold, color: tint)
        ], spacing: 6, alignment: .centerY)
        let stack = vstack([titleRow] + rows, spacing: 8 * scale)
        rows.forEach { fillWidth($0, of: stack) }
        let padding = 12 * paddingScale
        return card(stack, cornerRadius: 16, horizontalPadding: padding, verticalPadding: padding, alignTop: true)
    }

    private func eventRow(label text: String, value: String, note: String? = nil) -> NSView {
        var views: [NSView] = [label(text, size: 15, color: Palette.secondary), spacer()]
        if let note = note {
            // 数字の列は右揃えのまま保ちたいので、注記は時刻の左へ小さく置きます。
            views.append(label(note, size: 11, color: Palette.secondary))
        }
        views.append(label(value, size: 15, weight: .medium, monospaced: true))
        return hstack(views, spacing: 5, alignment: .firstBaseline)
    }

    private var placeholder: NSView {
        label("—", size: 15, color: Palette.secondary)
    }

    // MARK: 天文薄明

    private var twilightCard: NSView {
        let title = hstack([
            Icon.view(symbol: "sparkles", fallback: "✦", pointSize: 13 * scale, color: Palette.twilight, weight: .semibold),
            label("天文薄明", size: 15, weight: .semibold, color: Palette.twilight)
        ], spacing: 6, alignment: .centerY)

        let separator = NSBox()
        separator.boxType = .separator
        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, label("朝の薄明開始", size: 11, color: Palette.secondary), label("夕の薄明終了", size: 11, color: Palette.secondary)],
            twilightRow(title: dayTitle(model.selectedDay, fallback: "当日"), day: model.today),
            [separator],
            twilightRow(title: dayTitle(model.nextDay, fallback: "翌日"), day: model.tomorrow)
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = 10 * scale
        grid.rowSpacing = 8 * scale
        grid.xPlacement = .leading
        grid.yPlacement = .center
        grid.row(at: 2).mergeCells(in: NSRange(location: 0, length: 3))
        // 先頭列（今日・明日）以外の 2 列は同じ幅にします。
        let cardPadding = 12 * paddingScale
        let innerWidth = widgetWidth - 2 * 14 * paddingScale - 2 * cardPadding
        let firstColumn = 82 * scale
        grid.column(at: 0).width = firstColumn
        let otherWidth = floor((innerWidth - firstColumn - 2 * grid.columnSpacing) / 2)
        grid.column(at: 1).width = otherWidth
        grid.column(at: 2).width = otherWidth

        let stack = vstack([title, grid], spacing: 9 * scale)
        return card(stack, cornerRadius: 16, horizontalPadding: cardPadding, verticalPadding: cardPadding)
    }

    private func twilightRow(title: String, day: DailyAstronomy?) -> [NSView] {
        var titleViews: [NSView] = [label(title, size: 13, weight: .semibold)]
        if let date = day?.date {
            titleViews.append(label(formatter.shortDate(date), size: 11, color: Palette.secondary))
        }
        return [
            vstack(titleViews, spacing: 0),
            twilightTime(symbol: "sunrise.fill", fallback: "↑", value: formatter.time(day?.astronomicalTwilight.morning)),
            twilightTime(symbol: "sunset.fill", fallback: "↓", value: formatter.time(day?.astronomicalTwilight.evening))
        ]
    }

    private func twilightTime(symbol: String, fallback: String, value: String) -> NSView {
        hstack([
            Icon.view(symbol: symbol, fallback: fallback, pointSize: 14 * scale, color: Palette.secondary),
            label(value, size: 16, weight: .medium, monospaced: true)
        ], spacing: 5, alignment: .centerY)
    }

    private func dayTitle(_ day: Date, fallback: String) -> String {
        ObservationDay.relativeTitle(for: day, now: model.now) ?? fallback
    }

    // MARK: 暗夜

    /// 表示日の夕方から翌日の朝にかけて、太陽も月も影響しない時間帯を示すカードです。
    private var darkNightCard: NSView {
        var headerViews: [NSView] = [
            Icon.view(symbol: "moon.zzz.fill", fallback: "☾", pointSize: 13 * scale, color: Palette.darkNight, weight: .semibold),
            label("暗夜", size: 15, weight: .semibold, color: Palette.darkNight)
        ]
        var rows: [NSView] = []
        var fullWidthRows: [NSView] = []
        if let night = model.tonight {
            headerViews.append(label(formatter.nightRangeTitle(night), size: 11, color: Palette.secondary))
            headerViews.append(spacer())
            if night.status == .dark {
                headerViews.append(label("計", size: 11, color: Palette.secondary))
                headerViews.append(label(formatter.durationText(night.totalDuration), size: 15, weight: .semibold, rounded: true, monospaced: true))
            }
            switch night.status {
            case .dark:
                for interval in night.darkIntervals {
                    let row = darkIntervalRow(interval, in: night)
                    rows.append(row)
                    fullWidthRows.append(row)
                }
                let timeline = darkNightTimeline(night)
                rows.append(timeline)
                fullWidthRows.append(timeline)
            case .moonlitAllNight:
                rows.append(darkNightMessage(symbol: "moon.fill", fallback: "●", text: "一晩中月が出ているため、暗夜はありません"))
                let timeline = darkNightTimeline(night)
                rows.append(timeline)
                fullWidthRows.append(timeline)
            case .noAstronomicalNight:
                rows.append(darkNightMessage(symbol: "sun.haze.fill", fallback: "☀︎", text: "天文薄明が終わらないため、暗夜はありません"))
            }
        } else {
            headerViews.append(spacer())
            rows.append(placeholder)
        }
        let header = hstack(headerViews, spacing: 6, alignment: .firstBaseline)
        let stack = vstack([header] + rows, spacing: 9 * scale)
        fillWidth(header, of: stack)
        fullWidthRows.forEach { fillWidth($0, of: stack) }
        let padding = 12 * paddingScale
        return card(stack, cornerRadius: 16, horizontalPadding: padding, verticalPadding: padding)
    }

    /// 暗夜 1 区間分の行です。開始・終了が薄明と月のどちらで決まったかを添えます。
    private func darkIntervalRow(_ interval: DateInterval, in night: DarkNight) -> NSView {
        var views: [NSView] = [
            darkBoundary(time: formatter.nightTime(interval.start, in: night), cause: formatter.startCause(interval, in: night)),
            label("→", size: 11, weight: .semibold, color: Palette.secondary),
            darkBoundary(time: formatter.nightTime(interval.end, in: night), cause: formatter.endCause(interval, in: night)),
            spacer()
        ]
        if night.darkIntervals.count > 1 {
            views.append(label(formatter.durationText(interval.duration), size: 12, color: Palette.secondary, monospaced: true))
        }
        return hstack(views, spacing: 8 * scale, alignment: .firstBaseline)
    }

    private func darkBoundary(time: String, cause: String?) -> NSView {
        var views: [NSView] = [label(time, size: 17, weight: .medium, monospaced: true)]
        if let cause = cause {
            views.append(label(cause, size: 11, color: Palette.secondary))
        }
        return hstack(views, spacing: 4, alignment: .firstBaseline)
    }

    private func darkNightMessage(symbol: String, fallback: String, text: String) -> NSView {
        hstack([
            Icon.view(symbol: symbol, fallback: fallback, pointSize: 12 * scale, color: Palette.secondary),
            label(text, size: 13)
        ], spacing: 6, alignment: .centerY)
    }

    /// 夜（夕の天文薄明終了〜朝の天文薄明開始）全体に対する、暗夜と月明かりの配置を示します。
    private func darkNightTimeline(_ night: DarkNight) -> NSView {
        guard let first = night.astronomicalNight.first, let last = night.astronomicalNight.last else {
            return NSView()
        }
        let span = DateInterval(start: first.start, end: last.end)
        let timeline = DarkNightTimelineView()
        timeline.span = span
        timeline.astronomicalNight = night.astronomicalNight
        timeline.darkIntervals = night.darkIntervals
        timeline.now = model.now
        timeline.translatesAutoresizingMaskIntoConstraints = false
        timeline.heightAnchor.constraint(equalToConstant: 9 * scale).isActive = true

        let leftSpacer = spacer()
        let rightSpacer = spacer()
        let legendRow = hstack([
            label(formatter.nightTime(span.start, in: night), size: 11, color: Palette.secondary, monospaced: true),
            leftSpacer,
            legend(color: Palette.darkNight, text: "暗夜"),
            legend(color: Palette.moonlit, text: "月明かり"),
            rightSpacer,
            label(formatter.nightTime(span.end, in: night), size: 11, color: Palette.secondary, monospaced: true)
        ], spacing: 8, alignment: .centerY)
        leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor).isActive = true

        let stack = vstack([timeline, legendRow], spacing: 4 * scale)
        fillWidth(timeline, of: stack)
        fillWidth(legendRow, of: stack)
        return stack
    }

    private func legend(color: NSColor, text: String) -> NSView {
        hstack([DotView(color: color, diameter: 6 * scale), label(text, size: 11, color: Palette.secondary)], spacing: 3, alignment: .centerY)
    }

    private func noticeRow(_ notice: String) -> NSView {
        let row = hstack([
            Icon.view(symbol: "location.slash", fallback: "⌀", pointSize: 11 * scale, color: Palette.secondary),
            label(notice, size: 12, color: Palette.secondary)
        ], spacing: 5, alignment: .centerY)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        return row
    }

    // MARK: - 操作

    @objc private func previousDay() { model.shiftDay(by: -1) }
    @objc private func nextDay() { model.shiftDay(by: 1) }

    @objc private func showToday() {
        model.showToday()
        datePopover?.close()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openAstronomySettings, object: nil)
    }

    @objc private func toggleDatePicker() {
        if let popover = datePopover, popover.isShown {
            popover.close()
            return
        }
        guard let dateButton = dateButton else { return }
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = model.selectedDay
        picker.target = self
        picker.action = #selector(datePicked(_:))
        picker.translatesAutoresizingMaskIntoConstraints = false
        datePicker = picker

        let todayButton = NSButton(title: "今日", target: self, action: #selector(showToday))
        todayButton.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(picker)
        container.addSubview(todayButton)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            picker.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            todayButton.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            todayButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            todayButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        let controller = NSViewController()
        controller.view = container

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        datePopover = popover
        // 日付を選ぶと中身を組み直すため、ボタンではなくウィジェット本体を基準に表示します。
        let rect = dateButton.convert(dateButton.bounds, to: self)
        // このビューは座標が反転していないため、.minY が下側（SwiftUI 版と同じ向き）です。
        popover.show(relativeTo: rect, of: self, preferredEdge: .minY)
    }

    @objc private func datePicked(_ sender: NSDatePicker) {
        model.selectDay(sender.dateValue)
    }

    func popoverDidClose(_ notification: Notification) {
        datePopover = nil
        datePicker = nil
    }

    // MARK: - 部品

    private func font(_ size: CGFloat, weight: NSFont.Weight = .regular, rounded: Bool = false, monospaced: Bool = false) -> NSFont {
        let pointSize = size * scale
        var font = monospaced
            ? NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: weight)
            : NSFont.systemFont(ofSize: pointSize, weight: weight)
        if rounded, #available(macOS 10.15, *),
           let descriptor = font.fontDescriptor.withDesign(.rounded),
           let roundedFont = NSFont(descriptor: descriptor, size: pointSize) {
            font = roundedFont
        }
        return font
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = Palette.primary,
        rounded: Bool = false,
        monospaced: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font(size, weight: weight, rounded: rounded, monospaced: monospaced)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return field
    }

    private func textButton(_ title: String, font: NSFont, color: NSColor, action: Selector) -> NSButton {
        let button = FirstClickButton(title: title, target: self, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func circleButton(symbol: String, fallback: String, size: CGFloat, action: Selector, help: String) -> NSButton {
        let button = FirstClickButton(title: "", target: self, action: action)
        button.isBordered = false
        button.toolTip = help
        let pointSize = size * 0.45
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
               .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)) {
            button.image = image
            button.imagePosition = .imageOnly
            button.contentTintColor = Palette.primary
        } else {
            button.attributedTitle = NSAttributedString(string: fallback, attributes: [
                .font: NSFont.systemFont(ofSize: size * 0.6, weight: .bold),
                .foregroundColor: Palette.primary
            ])
        }
        button.wantsLayer = true
        button.layer?.backgroundColor = Palette.cardBackground.cgColor
        button.layer?.cornerRadius = size / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        return button
    }

    private func pill(_ button: NSButton) -> NSView {
        let background = CardView(cornerRadius: 9 * scale, color: NSColor(white: 1, alpha: 0.16))
        background.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 7),
            button.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -7),
            button.topAnchor.constraint(equalTo: background.topAnchor, constant: 2),
            button.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -2)
        ])
        return background
    }

    private func card(
        _ content: NSView,
        cornerRadius: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        alignTop: Bool = false
    ) -> NSView {
        let card = CardView(cornerRadius: cornerRadius)
        card.addSubview(content)
        var constraints = [
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: horizontalPadding),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -horizontalPadding),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: verticalPadding)
        ]
        if alignTop {
            // 高さをそろえたカードでは、中身を上に寄せます。
            constraints.append(content.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -verticalPadding))
        } else {
            constraints.append(content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -verticalPadding))
        }
        NSLayoutConstraint.activate(constraints)
        return card
    }

    private func vstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultHigh, for: .vertical)
        return stack
    }

    private func hstack(_ views: [NSView], spacing: CGFloat, alignment: NSLayoutConstraint.Attribute) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = alignment
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// 横方向に伸びて、両側の要素を押し広げる空白です。
    private func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true
        return view
    }

    private func fillWidth(_ view: NSView, of stack: NSStackView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// デスクトップ上のパネルはキーウインドウにならないことが多いため、1 回目のクリックで反応するボタンです。
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// ウィジェットの縁取りです。クリックは下の要素へ通します。
private final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.22).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 21.5, yRadius: 21.5)
        path.lineWidth = 1
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
