import CoreLocation
import Foundation

/// 現在地の取得状況です。設定画面で緯度経度を示すのに使います。
enum CurrentLocationState: Equatable {
    case unknown
    case locating
    case located(latitude: Double, longitude: Double)
    case unavailable(String)
}

/// macOS 13 版の AstronomyViewModel と同じ計算を行います。
/// macOS 10.12 では Combine や Swift Concurrency を使えないため、変更はクロージャで通知します。
final class AstronomyViewModel: NSObject {
    private(set) var now = Date()
    /// 表示している日（0 時）です。
    private(set) var selectedDay = Calendar.current.startOfDay(for: Date())
    private(set) var today: DailyAstronomy?
    private(set) var tomorrow: DailyAstronomy?
    /// 表示日の夕方から翌日の朝にかけての暗夜です。
    private(set) var tonight: DarkNight?
    private(set) var moonPhase = MoonPhase(fraction: 0, age: 0, illuminatedFraction: 0)
    private(set) var activeLocation = ObserverLocation(latitude: 35.6812, longitude: 139.7671, name: "東京")
    private(set) var locationNotice: String?
    private(set) var currentLocationState = CurrentLocationState.unknown
    private(set) var textScale: CGFloat = WidgetTextSize.standard.scale

    /// ウィジェットの表示を更新すべきときに呼ばれます。
    var onChange: (() -> Void)?
    /// 現在地の取得状況が変わったときに呼ばれます（設定画面用）。
    var onLocationStateChange: (() -> Void)?

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
            setLocationState(.locating)
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

    private func setLocationState(_ state: CurrentLocationState) {
        currentLocationState = state
        onLocationStateChange?()
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
                setLocationState(.locating)
            }
            if requestLocation { requestLocationIfPossible() }
        } else {
            activeLocation = preferences.manualLocation
            locationNotice = nil
        }
    }

    private func requestLocationIfPossible() {
        guard CLLocationManager.locationServicesEnabled() else {
            setLocationState(.unavailable("位置情報サービスがオフです"))
            useManualFallback(notice: "位置情報を利用できないため指定地点を表示")
            return
        }
        let status = CLLocationManager.authorizationStatus()
        if status == .denied || status == .restricted {
            setLocationState(.unavailable("位置情報の利用が許可されていません"))
            useManualFallback(notice: "位置情報を利用できないため指定地点を表示")
            return
        }
        // macOS 10.12 には requestLocation() がないため、取得できたら止めます。
        // 未許可（notDetermined）の場合は、ここで許可ダイアログが表示されます。
        locationManager.startUpdatingLocation()
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
        if force || lastCalculationKey != key {
            lastCalculationKey = key
            today = calculator.dailyAstronomy(for: selectedDay, location: activeLocation, moonMode: moonMode)
            tomorrow = calculator.dailyAstronomy(for: nextDay, location: activeLocation, moonMode: moonMode)
            tonight = calculator.darkNight(for: selectedDay, location: activeLocation)
        }
        onChange?()
    }
}

extension AstronomyViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard AppPreferences.shared.useCurrentLocation || self.currentLocationState == .locating else { return }
            if status == .notDetermined { return }
            self.requestLocationIfPossible()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            self.setLocationState(.located(latitude: latitude, longitude: longitude))
            guard AppPreferences.shared.useCurrentLocation else { return }
            self.activeLocation = ObserverLocation(latitude: latitude, longitude: longitude, name: "現在地")
            self.locationNotice = nil
            self.refresh(force: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown は一時的なものなので、取得を続けます。
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        manager.stopUpdatingLocation()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 以前に取得できていれば、その現在地を使い続けます。
            if case .located = self.currentLocationState { return }
            self.setLocationState(.unavailable("現在地を取得できませんでした"))
            self.useManualFallback(notice: "現在地を取得できないため指定地点を表示")
        }
    }
}
