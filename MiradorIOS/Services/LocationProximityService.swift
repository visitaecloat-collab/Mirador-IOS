import Foundation
import CoreLocation

/// Equivalente de `LocationHelper.kt` + `Aviso_de_proximidad`:
/// - Solicita ubicación "solo mientras usas la app" (`requestWhenInUseAuthorization`)
/// - Calcula distancias en metros y minutos a pie
/// - Emite aviso de proximidad cuando el usuario se acerca a menos de 60 m de un monumento
@MainActor
final class LocationProximityService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var nearbyAlertSite: HeritageSite?

    private let manager = CLLocationManager()
    private var trackedSites: [HeritageSite] = []
    private var alertedSiteIds: Set<String> = []
    var alertsEnabled: Bool = true

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 15
        authorizationStatus = manager.authorizationStatus
    }

    func configureSites(_ sites: [HeritageSite]) {
        trackedSites = sites
    }

    func requestWhenInUsePermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func distanceMeters(to site: HeritageSite) -> Int {
        guard let loc = userLocation else { return 180 }
        let target = CLLocation(latitude: site.lat, longitude: site.lng)
        return Int(loc.distance(from: target).rounded())
    }

    func walkingMinutes(to site: HeritageSite) -> Int {
        let meters = distanceMeters(to: site)
        return max(1, Int((Double(meters) / 75.0).rounded()))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.userLocation = latest
            self.evaluateProximity(from: latest)
        }
    }

    private func evaluateProximity(from location: CLLocation) {
        guard alertsEnabled else { return }
        for site in trackedSites {
            let dist = location.distance(from: CLLocation(latitude: site.lat, longitude: site.lng))
            if dist <= 60.0 && !alertedSiteIds.contains(site.id) {
                alertedSiteIds.insert(site.id)
                nearbyAlertSite = site
                break
            }
        }
    }
}
