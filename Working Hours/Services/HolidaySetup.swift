import CoreLocation
import Foundation

/// Finds the holiday region from the current location. Only runs when the user asks for it,
/// so the permission prompt appears in context.
@MainActor
final class RegionDetector: NSObject, CLLocationManagerDelegate {
    enum Result: Equatable {
        case found(HolidayRegion)
        /// Location Services are turned off for the whole Mac.
        case servicesOff
        /// The user did not allow location access for this app.
        case denied
        /// The location is outside the countries with built-in holidays.
        case unsupportedCountry
        case failed
    }

    /// The page in System Settings where location access is turned on.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func detect() async -> Result {
        // Apple advises against asking this on the main thread.
        let servicesEnabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard servicesEnabled else { return .servicesOff }

        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
                // macOS ignores the request while the app is not in use; do not wait forever.
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.finishAuthorization() }
            }
        }
        switch manager.authorizationStatus {
        case .authorizedAlways: break
        case .denied, .restricted: return .denied
        default: return .failed
        }

        let location: CLLocation? = await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.finish(with: nil) }
        }
        guard let location,
              let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .app).first
        else { return .failed }
        guard let region = Self.region(countryCode: placemark.isoCountryCode, area: placemark.administrativeArea) else {
            return .unsupportedCountry
        }
        return .found(region)
    }

    static func region(countryCode: String?, area: String?) -> HolidayRegion? {
        guard let countryCode, let country = HolidayCountry(rawValue: countryCode.uppercased()) else { return nil }
        return HolidayRegion(country: country, state: area.flatMap(GermanState.init(name:)))
    }

    /// The country set in System Settings > General > Language & Region. Needs no permission.
    static func regionFromLocale(_ locale: Locale = .current) -> HolidayRegion? {
        guard let identifier = locale.region?.identifier, let country = HolidayCountry(rawValue: identifier) else { return nil }
        return HolidayRegion(country: country)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            finishAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { finish(with: locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { finish(with: nil) }
    }

    private func finishAuthorization() {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    private func finish(with location: CLLocation?) {
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
}

/// Sets the holiday region of jobs that have none yet.
@MainActor
enum HolidaySetup {
    /// Runs once on the first start: jobs without a region get the country from the system settings.
    /// The location is only used when the user asks for it in the holiday settings.
    static func runInitialDetection(settings: AppSettings, jobs: JobStore) {
        #if DEBUG
        // The demo shares the preferences with the real app and must not use up the first detection.
        if DemoData.isEnabled { return }
        #endif
        guard !settings.holidayDetectionDone else { return }
        settings.holidayDetectionDone = true
        guard let region = RegionDetector.regionFromLocale() else { return }
        for job in jobs.jobs where job.holidayRegionCode.isEmpty {
            job.holidayRegion = region
        }
        jobs.save()
    }
}
