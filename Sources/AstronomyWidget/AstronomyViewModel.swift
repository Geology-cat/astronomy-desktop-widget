import AstronomyCore
import CoreLocation
import Foundation

@MainActor
final class AstronomyViewModel: NSObject, ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var today: DailyAstronomy?
    @Published private(set) var tomorrow: DailyAstronomy?
    @Published private(set) var moonPhase = MoonPhase(fraction: 0, age: 0, illuminatedFraction: 0)
    @Published private(set) var activeLocation = ObserverLocation(latitude: 35.6812, longitude: 139.7671, name: "東京")
    @Published private(set) var locationNotice: String?
    @Published private(set) var textScale: CGFloat = WidgetTextSize.standard.scale

    private let calculator = AstronomyCalculator()
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var lastCalculatedDay: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .astronomyPreferencesChanged,
            object: nil
        )
        applyPreferences(requestLocation: true)
        refresh(force: true)
        timer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func refreshNow() {
        if AppPreferences.shared.useCurrentLocation {
            requestLocationIfPossible()
        }
        refresh(force: true)
    }

    @objc private func timerFired() {
        refresh(force: false)
    }

    @objc private func preferencesChanged() {
        applyPreferences(requestLocation: true)
        refresh(force: true)
    }

    private func applyPreferences(requestLocation: Bool) {
        let preferences = AppPreferences.shared
        textScale = preferences.widgetTextSize.scale
        if preferences.useCurrentLocation {
            locationNotice = "位置情報を確認中…"
            if requestLocation { requestLocationIfPossible() }
        } else {
            activeLocation = ObserverLocation(
                latitude: preferences.latitude,
                longitude: preferences.longitude,
                name: preferences.locationName.isEmpty ? "指定地点" : preferences.locationName
            )
            locationNotice = nil
        }
    }

    private func requestLocationIfPossible() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            useManualFallback(notice: "位置情報を利用できないため指定地点を表示")
        @unknown default:
            useManualFallback(notice: "指定地点を表示")
        }
    }

    private func useManualFallback(notice: String) {
        let preferences = AppPreferences.shared
        activeLocation = ObserverLocation(
            latitude: preferences.latitude,
            longitude: preferences.longitude,
            name: preferences.locationName.isEmpty ? "指定地点" : preferences.locationName
        )
        locationNotice = notice
    }

    private func refresh(force: Bool) {
        now = Date()
        moonPhase = calculator.moonPhase(at: now)
        let startOfDay = Calendar.current.startOfDay(for: now)
        guard force || lastCalculatedDay != startOfDay else { return }
        lastCalculatedDay = startOfDay
        today = calculator.dailyAstronomy(for: now, location: activeLocation)
        if let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: now) {
            tomorrow = calculator.dailyAstronomy(for: nextDate, location: activeLocation)
        }
    }
}

extension AstronomyViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard AppPreferences.shared.useCurrentLocation else { return }
            self?.requestLocationIfPossible()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard AppPreferences.shared.useCurrentLocation else { return }
            self.activeLocation = ObserverLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                name: "現在地"
            )
            self.locationNotice = nil
            self.refresh(force: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.useManualFallback(notice: "現在地を取得できないため指定地点を表示")
            self?.refresh(force: true)
        }
    }
}
