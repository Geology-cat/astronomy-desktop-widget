import AstronomyCore
import CoreLocation
import Foundation

/// 現在地の取得状況です。設定画面で緯度経度を示すのに使います。
enum CurrentLocationState: Equatable {
    case unknown
    case locating
    case located(latitude: Double, longitude: Double)
    case unavailable(String)
}

@MainActor
final class AstronomyViewModel: NSObject, ObservableObject {
    @Published private(set) var now = Date()
    /// 表示している日（0 時）です。
    @Published private(set) var selectedDay = Calendar.current.startOfDay(for: Date())
    @Published private(set) var today: DailyAstronomy?
    @Published private(set) var tomorrow: DailyAstronomy?
    /// 表示日の夕方から翌日の朝にかけての暗夜です。
    @Published private(set) var tonight: DarkNight?
    @Published private(set) var moonPhase = MoonPhase(fraction: 0, age: 0, illuminatedFraction: 0)
    @Published private(set) var activeLocation = ObserverLocation(latitude: 35.6812, longitude: 139.7671, name: "東京")
    @Published private(set) var locationNotice: String?
    @Published private(set) var currentLocationState = CurrentLocationState.unknown
    @Published private(set) var textScale: CGFloat = WidgetTextSize.standard.scale

    private let calculator = AstronomyCalculator()
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var lastCalculationKey: String?
    /// true の間は、日付が変わると表示日も今日へ進めます。
    private var followsToday = true

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

    var isShowingToday: Bool {
        Calendar.current.isDate(selectedDay, inSameDayAs: now)
    }

    /// 表示日の翌日（0 時）です。
    var nextDay: Date {
        ObservationDay.shifted(selectedDay, by: 1)
    }

    func refreshNow() {
        if AppPreferences.shared.useCurrentLocation {
            requestLocationIfPossible()
        }
        refresh(force: true)
    }

    /// 設定画面で現在地の緯度経度を示すため、設定を保存する前でも現在地を取得します。
    func refreshLocation() {
        if case .located = currentLocationState {} else {
            currentLocationState = .locating
        }
        requestLocationIfPossible()
    }

    // MARK: - 表示日の変更

    func shiftDay(by days: Int) {
        selectDay(ObservationDay.shifted(selectedDay, by: days))
    }

    func showToday() {
        selectDay(Date())
    }

    func selectDay(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        followsToday = Calendar.current.isDate(day, inSameDayAs: Date())
        selectedDay = day
        refresh(force: false)
    }

    // MARK: - 更新

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
            if case .located(let latitude, let longitude) = currentLocationState {
                // 取得済みの現在地をすぐに使い、裏で更新します。
                activeLocation = ObserverLocation(latitude: latitude, longitude: longitude, name: "現在地")
                locationNotice = nil
            } else {
                locationNotice = "位置情報を確認中…"
                currentLocationState = .locating
            }
            if requestLocation { requestLocationIfPossible() }
        } else {
            activeLocation = preferences.manualLocation
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
            currentLocationState = .unavailable("位置情報の利用が許可されていません")
            useManualFallback(notice: "位置情報を利用できないため指定地点を表示")
        @unknown default:
            currentLocationState = .unavailable("位置情報を利用できません")
            useManualFallback(notice: "指定地点を表示")
        }
    }

    private func useManualFallback(notice: String) {
        guard AppPreferences.shared.useCurrentLocation else { return }
        activeLocation = AppPreferences.shared.manualLocation
        locationNotice = notice
        refresh(force: true)
    }

    private func refresh(force: Bool) {
        now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        if followsToday, selectedDay != todayStart {
            selectedDay = todayStart
        }
        moonPhase = calculator.moonPhase(at: ObservationDay.moonPhaseMoment(for: selectedDay, now: now))

        // 表示日・地点・設定が変わったときだけ再計算します。
        let moonMode = AppPreferences.shared.moonDayMode
        let key = "\(selectedDay.timeIntervalSince1970)|\(activeLocation.latitude)|\(activeLocation.longitude)|\(moonMode.rawValue)"
        guard force || lastCalculationKey != key else { return }
        lastCalculationKey = key
        today = calculator.dailyAstronomy(for: selectedDay, location: activeLocation, moonMode: moonMode)
        tomorrow = calculator.dailyAstronomy(for: nextDay, location: activeLocation, moonMode: moonMode)
        tonight = calculator.darkNight(for: selectedDay, location: activeLocation)
        // 暗夜の区間数などで高さが変わるため、パネルの大きさを合わせ直してもらいます。
        NotificationCenter.default.post(name: .astronomyWidgetContentChanged, object: nil)
    }
}

extension AstronomyViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 設定画面で現在地を確認中の場合も、許可が出たら取得します。
            guard AppPreferences.shared.useCurrentLocation || self.currentLocationState == .locating else { return }
            self.requestLocationIfPossible()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            self.currentLocationState = .located(latitude: latitude, longitude: longitude)
            guard AppPreferences.shared.useCurrentLocation else { return }
            self.activeLocation = ObserverLocation(latitude: latitude, longitude: longitude, name: "現在地")
            self.locationNotice = nil
            self.refresh(force: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 以前に取得できていれば、その現在地を使い続けます。
            if case .located = self.currentLocationState { return }
            self.currentLocationState = .unavailable("現在地を取得できませんでした")
            self.useManualFallback(notice: "現在地を取得できないため指定地点を表示")
        }
    }
}
