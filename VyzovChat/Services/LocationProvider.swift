import CoreLocation

/// Геометка телефона — юридическая метка на фото (как в вебе).
/// Если доступа нет или фикс не пришёл, отдаём nil: фото уйдёт без координат.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private let geocoder = CLGeocoder()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Текущие координаты. Не висит дольше 6 секунд.
    func current() async -> (lat: Double, lng: Double)? {
        guard isAuthorized else { return nil }

        // Свежий кэш системы — самый быстрый путь.
        if let last = manager.location, Date().timeIntervalSince(last.timestamp) < 300 {
            return (last.coordinate.latitude, last.coordinate.longitude)
        }

        // Страховка от зависания: если фикс не пришёл — будим ожидающих с nil.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.finish(nil)
        }

        let location: CLLocation? = await withCheckedContinuation { cont in
            waiters.append(cont)
            manager.requestLocation()
        }
        guard let location else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    /// Человекочитаемый адрес по координатам (обратное геокодирование).
    func address(lat: Double, lng: Double) async -> String? {
        let location = CLLocation(latitude: lat, longitude: lng)
        guard let mark = try? await geocoder.reverseGeocodeLocation(
            location, preferredLocale: Locale(identifier: "ru_RU")).first else { return nil }

        let parts = [
            mark.locality ?? mark.administrativeArea,   // город
            mark.thoroughfare,                          // улица
            mark.subThoroughfare                        // дом
        ].compactMap { $0 }

        if parts.isEmpty { return mark.name }
        return parts.joined(separator: ", ")
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}
