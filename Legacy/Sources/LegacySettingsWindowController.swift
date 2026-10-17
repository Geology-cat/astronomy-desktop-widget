import AppKit

/// macOS 13 版の SettingsView を AppKit で再現した設定画面です。
final class LegacySettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AstronomyViewModel
    private let formatter = AstronomyTextFormatter()

    private let useCurrentLocationCheckbox = NSButton(checkboxWithTitle: "現在地を使用", target: nil, action: nil)
    private let currentLocationLabel = NSTextField(labelWithString: "")
    private let currentLocationRow = NSStackView()
    private let locationCaption = NSTextField(labelWithString: "")
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presetCoordinateLabel = NSTextField(labelWithString: "")
    private let presetSourceLabel = NSTextField(labelWithString: "")
    private let presetInfo = NSStackView()
    private let nameField = NSTextField(string: "")
    private let latitudeField = NSTextField(string: "")
    private let longitudeField = NSTextField(string: "")
    private let manualFields = NSStackView()
    private let textSizeControl = NSSegmentedControl(
        labels: WidgetTextSize.allCases.map { $0.title },
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let sampleLabel = NSTextField(labelWithString: "南中  12:34（45.6°）")
    private let moonModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let moonModeExplanation = NSTextField(wrappingLabelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "ログイン時に自動起動", target: nil, action: nil)
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    /// 地点リストのうち、緯度経度の手入力を表す項目の識別子です。
    private static let customTag = ""

    init(model: AstronomyViewModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "天文情報ウィジェット設定"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 保存済みの設定を読み込んでから表示します。
    func present() {
        load()
        model.onLocationStateChange = { [weak self] in self?.updateCurrentLocation() }
        if useCurrentLocationCheckbox.state == .on { model.refreshLocation() }
        fitWindow()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.onLocationStateChange = nil
    }

    // MARK: - 組み立て

    private func buildContent() {
        let title = NSTextField(labelWithString: "天文情報ウィジェット")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let subtitle = caption("観測地点と起動方法を設定します。\n時刻はMacの現在のタイムゾーンで表示されます。", size: 12)

        // 観測地点
        useCurrentLocationCheckbox.target = self
        useCurrentLocationCheckbox.action = #selector(useCurrentLocationChanged)
        currentLocationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        currentLocationLabel.isSelectable = true
        configureRow(currentLocationRow, label: "現在地", control: currentLocationLabel)

        locationCaption.font = NSFont.systemFont(ofSize: 11)
        locationCaption.textColor = .secondaryLabelColor

        buildPresetMenu()
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        presetPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let presetRow = NSStackView()
        configureRow(presetRow, label: "地点", control: presetPopup)

        presetCoordinateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        presetCoordinateLabel.textColor = .secondaryLabelColor
        let coordinateRow = NSStackView()
        configureRow(coordinateRow, label: "緯度・経度", control: presetCoordinateLabel)
        presetSourceLabel.font = NSFont.systemFont(ofSize: 10)
        presetSourceLabel.textColor = .tertiaryLabelColor
        presetInfo.orientation = .vertical
        presetInfo.alignment = .leading
        presetInfo.spacing = 6
        presetInfo.setViews([coordinateRow, presetSourceLabel], in: .top)

        nameField.placeholderString = "東京"
        nameField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        latitudeField.placeholderString = "35.6812"
        latitudeField.formatter = coordinateFormatter(minimum: -90, maximum: 90)
        latitudeField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        longitudeField.placeholderString = "139.7671"
        longitudeField.formatter = coordinateFormatter(minimum: -180, maximum: 180)
        longitudeField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let nameRow = NSStackView()
        configureRow(nameRow, label: "地点名", control: nameField)
        let latitudeRow = NSStackView()
        configureRow(latitudeRow, label: "緯度", control: latitudeField)
        let longitudeRow = NSStackView()
        configureRow(longitudeRow, label: "経度", control: longitudeField)
        let rangeNote = caption("緯度は −90〜90°、経度は −180〜180°（東経が正）", size: 10)
        rangeNote.textColor = .tertiaryLabelColor
        manualFields.orientation = .vertical
        manualFields.alignment = .leading
        manualFields.spacing = 8
        manualFields.setViews([nameRow, latitudeRow, longitudeRow, rangeNote], in: .top)

        let separator = NSBox()
        separator.boxType = .separator
        let locationBox = groupBox("観測地点", views: [
            useCurrentLocationCheckbox, currentLocationRow, separator, locationCaption, presetRow, presetInfo, manualFields
        ], fullWidth: [separator])

        // 表示
        textSizeControl.target = self
        textSizeControl.action = #selector(textSizeChanged)
        textSizeControl.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let textSizeRow = NSStackView()
        configureRow(textSizeRow, label: "文字サイズ", control: textSizeControl)
        let sampleCaption = caption("表示例", size: 11)
        let sampleRow = NSStackView(views: [sampleCaption, flexibleSpace(), sampleLabel])
        sampleRow.orientation = .horizontal
        sampleRow.alignment = .centerY

        MoonDayMode.allCases.forEach { moonModePopup.addItem(withTitle: $0.title) }
        moonModePopup.target = self
        moonModePopup.action = #selector(moonModeChanged)
        moonModePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let moonModeRow = NSStackView()
        configureRow(moonModeRow, label: "月の南中・月の入", control: moonModePopup)
        moonModeExplanation.font = NSFont.systemFont(ofSize: 11)
        moonModeExplanation.textColor = .secondaryLabelColor
        moonModeExplanation.preferredMaxLayoutWidth = 370

        let displaySeparator = NSBox()
        displaySeparator.boxType = .separator
        let displayBox = groupBox("表示", views: [
            textSizeRow, sampleRow, displaySeparator, moonModeRow, moonModeExplanation
        ], fullWidth: [sampleRow, displaySeparator])

        messageLabel.font = NSFont.systemFont(ofSize: 11)
        messageLabel.textColor = .systemOrange
        messageLabel.preferredMaxLayoutWidth = 400

        let cancelButton = NSButton(title: "キャンセル", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [flexibleSpace(), cancelButton, saveButton])
        buttonRow.orientation = .horizontal

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 5

        let root = NSStackView(views: [headerStack, locationBox, displayBox, launchAtLoginCheckbox, messageLabel, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: 450).isActive = true
        for view in [locationBox, displayBox, buttonRow] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        }

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window?.contentView = container
    }

    /// 地方ごとの見出しを付けた地点リストを作ります。
    private func buildPresetMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, group) in LocationPreset.groupedByRegion.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let header = NSMenuItem(title: group.region, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for preset in group.presets {
                let item = NSMenuItem(title: preset.title, action: nil, keyEquivalent: "")
                item.representedObject = preset.id
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let custom = NSMenuItem(title: "緯度・経度を入力…", action: nil, keyEquivalent: "")
        custom.representedObject = Self.customTag
        menu.addItem(custom)
        presetPopup.menu = menu
    }

    private func groupBox(_ title: String, views: [NSView], fullWidth: [NSView]) -> NSBox {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in fullWidth {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        }
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        box.contentView = content
        return box
    }

    /// 左に見出し、右に入力欄を置く 1 行です（SwiftUI の LabeledContent 相当）。
    private func configureRow(_ row: NSStackView, label: String, control: NSView) {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setViews([title, control], in: .leading)
    }

    private func caption(_ text: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: size)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return view
    }

    private func coordinateFormatter(minimum: Double, maximum: Double) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        return formatter
    }

    // MARK: - 状態

    private var selectedPresetID: String {
        presetPopup.selectedItem?.representedObject as? String ?? Self.customTag
    }

    private var selectedTextSize: WidgetTextSize {
        let index = max(0, textSizeControl.selectedSegment)
        return WidgetTextSize.allCases[min(index, WidgetTextSize.allCases.count - 1)]
    }

    private var selectedMoonMode: MoonDayMode {
        let index = max(0, moonModePopup.indexOfSelectedItem)
        return MoonDayMode.allCases[min(index, MoonDayMode.allCases.count - 1)]
    }

    private func load() {
        let preferences = AppPreferences.shared
        useCurrentLocationCheckbox.state = preferences.useCurrentLocation ? .on : .off
        let presetID = preferences.locationPreset?.id ?? Self.customTag
        if let item = presetPopup.itemArray.first(where: { ($0.representedObject as? String) == presetID }) {
            presetPopup.select(item)
        }
        nameField.stringValue = preferences.locationName
        latitudeField.objectValue = NSNumber(value: preferences.latitude)
        longitudeField.objectValue = NSNumber(value: preferences.longitude)
        textSizeControl.selectedSegment = WidgetTextSize.allCases.firstIndex(of: preferences.widgetTextSize) ?? 1
        moonModePopup.selectItem(at: MoonDayMode.allCases.firstIndex(of: preferences.moonDayMode) ?? 0)
        launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
        messageLabel.stringValue = ""
        messageLabel.isHidden = true
        updateLocationSection()
        updateCurrentLocation()
        textSizeChanged()
        moonModeChanged()
    }

    private func updateLocationSection() {
        let useCurrent = useCurrentLocationCheckbox.state == .on
        currentLocationRow.isHidden = !useCurrent
        locationCaption.stringValue = useCurrent
            ? "位置情報を利用できない場合は、以下の地点を使用します。"
            : "以下の地点の天文情報を表示します。"
        if let preset = LocationPreset.preset(id: selectedPresetID) {
            presetCoordinateLabel.stringValue = formatter.coordinate(
                latitude: preset.latitude,
                longitude: preset.longitude,
                fractionDigits: 4
            )
            presetSourceLabel.stringValue = preset.region == "北海道" && preset.city != "札幌"
                ? "市役所付近の位置です。"
                : "都道府県庁の位置です。"
            presetInfo.isHidden = false
            manualFields.isHidden = true
        } else {
            presetInfo.isHidden = true
            manualFields.isHidden = false
        }
        fitWindow()
    }

    private func updateCurrentLocation() {
        switch model.currentLocationState {
        case .located(let latitude, let longitude):
            currentLocationLabel.stringValue = formatter.coordinate(latitude: latitude, longitude: longitude, fractionDigits: 4)
            currentLocationLabel.textColor = .labelColor
        case .locating, .unknown:
            currentLocationLabel.stringValue = "取得中…"
            currentLocationLabel.textColor = .secondaryLabelColor
        case .unavailable(let reason):
            currentLocationLabel.stringValue = reason
            currentLocationLabel.textColor = .secondaryLabelColor
        }
    }

    private func fitWindow() {
        guard let window = window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        guard size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let top = window.frame.maxY
        frame.origin.x = window.frame.minX
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }

    // MARK: - 操作

    @objc private func useCurrentLocationChanged() {
        updateLocationSection()
        // 現在地へ切り替えたら、その場で緯度経度を確かめられるよう取得を始めます。
        if useCurrentLocationCheckbox.state == .on { model.refreshLocation() }
    }

    @objc private func presetChanged() {
        updateLocationSection()
    }

    @objc private func textSizeChanged() {
        sampleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12 * selectedTextSize.scale, weight: .medium)
    }

    @objc private func moonModeChanged() {
        moonModeExplanation.stringValue = selectedMoonMode.explanation
        fitWindow()
    }

    @objc private func cancel() {
        window?.close()
    }

    @objc private func save() {
        let presetID = selectedPresetID
        var latitude = AppPreferences.shared.latitude
        var longitude = AppPreferences.shared.longitude
        if presetID == Self.customTag {
            guard let lat = (latitudeField.objectValue as? NSNumber)?.doubleValue ?? Double(latitudeField.stringValue),
                  let lon = (longitudeField.objectValue as? NSNumber)?.doubleValue ?? Double(longitudeField.stringValue),
                  (-90...90).contains(lat), (-180...180).contains(lon) else {
                showMessage("緯度または経度が範囲外です。")
                return
            }
            latitude = lat
            longitude = lon
        }
        do {
            try LoginItem.setEnabled(launchAtLoginCheckbox.state == .on)
        } catch {
            showMessage("自動起動の設定を変更できませんでした：\(error.localizedDescription)")
            return
        }
        AppPreferences.shared.save(
            useCurrentLocation: useCurrentLocationCheckbox.state == .on,
            locationPresetID: presetID == Self.customTag ? nil : presetID,
            locationName: nameField.stringValue,
            latitude: latitude,
            longitude: longitude,
            widgetTextSize: selectedTextSize,
            moonDayMode: selectedMoonMode
        )
        window?.close()
    }

    private func showMessage(_ text: String) {
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        fitWindow()
    }
}
