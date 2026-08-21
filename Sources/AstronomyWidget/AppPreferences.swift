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

extension Notification.Name {
    static let astronomyPreferencesChanged = Notification.Name("astronomyPreferencesChanged")
    static let openAstronomySettings = Notification.Name("openAstronomySettings")
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
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.useCurrentLocation: true,
            Key.locationName: "東京",
            Key.latitude: 35.6812,
            Key.longitude: 139.7671,
            Key.widgetTextSize: WidgetTextSize.standard.rawValue
        ])
    }

    var useCurrentLocation: Bool { defaults.bool(forKey: Key.useCurrentLocation) }
    var locationName: String { defaults.string(forKey: Key.locationName) ?? "東京" }
    var latitude: Double { defaults.double(forKey: Key.latitude) }
    var longitude: Double { defaults.double(forKey: Key.longitude) }
    var widgetTextSize: WidgetTextSize {
        WidgetTextSize(rawValue: defaults.string(forKey: Key.widgetTextSize) ?? "") ?? .standard
    }

    func save(
        useCurrentLocation: Bool,
        locationName: String,
        latitude: Double,
        longitude: Double,
        widgetTextSize: WidgetTextSize
    ) {
        defaults.set(useCurrentLocation, forKey: Key.useCurrentLocation)
        defaults.set(locationName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.locationName)
        defaults.set(min(90, max(-90, latitude)), forKey: Key.latitude)
        defaults.set(min(180, max(-180, longitude)), forKey: Key.longitude)
        defaults.set(widgetTextSize.rawValue, forKey: Key.widgetTextSize)
        NotificationCenter.default.post(name: .astronomyPreferencesChanged, object: nil)
    }
}
