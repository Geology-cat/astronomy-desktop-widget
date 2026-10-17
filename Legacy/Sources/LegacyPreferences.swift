import AppKit
import Foundation

// macOS 10.12 版の設定です。macOS 13 版（Sources/AstronomyWidget/AppPreferences.swift）と同じキーを使います。

enum WidgetTextSize: String {
    case small
    case standard
    case large
    case extraLarge

    static let allCases: [WidgetTextSize] = [.small, .standard, .large, .extraLarge]

    var title: String {
        switch self {
        case .small: return "小"
        case .standard: return "標準"
        case .large: return "大"
        case .extraLarge: return "特大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.90
        case .standard: return 1.00
        case .large: return 1.15
        case .extraLarge: return 1.30
        }
    }
}

extension MoonDayMode {
    var title: String {
        switch self {
        case .risenThatDay: return "その日にのぼった月"
        case .withinDay: return "その日のうちの時刻"
        }
    }

    var explanation: String {
        switch self {
        case .risenThatDay:
            return "南中と月の入は、その日にのぼった月について表示します。翌日にまたぐ場合は「翌」を付けます。"
        case .withinDay:
            return "その日のうちに起きる南中と月の入を表示します。前日にのぼった月のものには「（前日）」を付けます。"
        }
    }
}

extension Notification.Name {
    static let astronomyPreferencesChanged = Notification.Name("astronomyPreferencesChanged")
    static let openAstronomySettings = Notification.Name("openAstronomySettings")
}

final class AppPreferences {
    static let shared = AppPreferences()

    private enum Key {
        static let useCurrentLocation = "useCurrentLocation"
        static let locationName = "locationName"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let widgetTextSize = "widgetTextSize"
        static let moonDayMode = "moonDayMode"
        /// 選択中の地点リストの識別子です。空文字は緯度経度の手入力を表します。
        static let locationPresetID = "locationPresetID"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.useCurrentLocation: true,
            Key.locationName: "東京",
            Key.latitude: 35.6812,
            Key.longitude: 139.7671,
            Key.widgetTextSize: WidgetTextSize.standard.rawValue,
            Key.moonDayMode: MoonDayMode.risenThatDay.rawValue
        ])
        if defaults.string(forKey: Key.locationPresetID) == nil, let tokyo = LocationPreset.preset(id: "tokyo") {
            // 初回起動時は東京都庁を選んだ状態にします。
            defaults.set(tokyo.id, forKey: Key.locationPresetID)
            defaults.set(tokyo.shortName, forKey: Key.locationName)
            defaults.set(tokyo.latitude, forKey: Key.latitude)
            defaults.set(tokyo.longitude, forKey: Key.longitude)
        }
    }

    var useCurrentLocation: Bool { defaults.bool(forKey: Key.useCurrentLocation) }
    var locationName: String { defaults.string(forKey: Key.locationName) ?? "東京" }
    var latitude: Double { defaults.double(forKey: Key.latitude) }
    var longitude: Double { defaults.double(forKey: Key.longitude) }
    var locationPreset: LocationPreset? {
        LocationPreset.preset(id: defaults.string(forKey: Key.locationPresetID) ?? "")
    }
    /// 現在地を使わない場合、または現在地を取得できない場合に使う地点です。
    var manualLocation: ObserverLocation {
        if let preset = locationPreset { return preset.location }
        return ObserverLocation(
            latitude: latitude,
            longitude: longitude,
            name: locationName.isEmpty ? "指定地点" : locationName
        )
    }
    var widgetTextSize: WidgetTextSize {
        WidgetTextSize(rawValue: defaults.string(forKey: Key.widgetTextSize) ?? "") ?? .standard
    }
    var moonDayMode: MoonDayMode {
        MoonDayMode(rawValue: defaults.string(forKey: Key.moonDayMode) ?? "") ?? .risenThatDay
    }

    func save(
        useCurrentLocation: Bool,
        locationPresetID: String?,
        locationName: String,
        latitude: Double,
        longitude: Double,
        widgetTextSize: WidgetTextSize,
        moonDayMode: MoonDayMode
    ) {
        defaults.set(useCurrentLocation, forKey: Key.useCurrentLocation)
        if let preset = locationPresetID.flatMap(LocationPreset.preset(id:)) {
            defaults.set(preset.id, forKey: Key.locationPresetID)
            defaults.set(preset.shortName, forKey: Key.locationName)
            defaults.set(preset.latitude, forKey: Key.latitude)
            defaults.set(preset.longitude, forKey: Key.longitude)
        } else {
            defaults.set("", forKey: Key.locationPresetID)
            defaults.set(locationName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.locationName)
            defaults.set(min(90, max(-90, latitude)), forKey: Key.latitude)
            defaults.set(min(180, max(-180, longitude)), forKey: Key.longitude)
        }
        defaults.set(widgetTextSize.rawValue, forKey: Key.widgetTextSize)
        defaults.set(moonDayMode.rawValue, forKey: Key.moonDayMode)
        NotificationCenter.default.post(name: .astronomyPreferencesChanged, object: nil)
    }
}

/// ログイン時の自動起動です。
/// macOS 13 版の SMAppService は使えないため、~/Library/LaunchAgents に起動用の plist を置きます。
enum LoginItem {
    private static var label: String {
        (Bundle.main.bundleIdentifier ?? "jp.yamashitaujou.AstronomyDesktopWidget.Legacy") + ".LoginItem"
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(label + ".plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fileManager = FileManager.default
        if enabled {
            try fileManager.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } else if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
    }
}
