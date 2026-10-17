import AstronomyCore
import Foundation

enum WidgetTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

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
    /// 表示内容が変わり、パネルの大きさを合わせ直す必要があるときに通知します。
    static let astronomyWidgetContentChanged = Notification.Name("astronomyWidgetContentChanged")
}

@MainActor
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
        migrateLocationPreset()
    }

    /// 地点リスト導入前の設定を引き継ぎます。
    /// 緯度経度を保存済みの利用者は手入力のまま、そうでなければ東京都庁を選んだ状態にします。
    private func migrateLocationPreset() {
        guard defaults.string(forKey: Key.locationPresetID) == nil else { return }
        let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        if domain[Key.latitude] != nil {
            defaults.set("", forKey: Key.locationPresetID)
        } else if let tokyo = LocationPreset.preset(id: "tokyo") {
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
    /// 地点リストから選んでいる場合はその地点、手入力の場合は nil です。
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
