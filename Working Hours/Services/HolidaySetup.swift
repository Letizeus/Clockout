import CoreLocation
import Foundation

/// Finds the holiday region from the current location. Without permission or outside the
/// supported countries it falls back to the region set in the system settings.
@MainActor
final class RegionDetector: NSObject, CLLocationManagerDelegate {
    struct Result {
        let region: HolidayRegion?
        /// True when the region comes from the location, false when from the system settings.
        let fromLocation: Bool
    }

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func detect() async -> Result {
        if let location = await currentLocation(),
           let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .app).first,
           let region = Self.region(countryCode: placemark.isoCountryCode, area: placemark.administrativeArea) {
            return Result(region: region, fromLocation: true)
        }
        return Result(region: Self.regionFromLocale(), fromLocation: false)
    }

    static func region(countryCode: String?, area: String?) -> HolidayRegion? {
        guard let countryCode, let country = HolidayCountry(rawValue: countryCode.uppercased()) else { return nil }
        return HolidayRegion(country: country, state: area.flatMap(GermanState.init(name:)))
    }

    static func regionFromLocale(_ locale: Locale = .current) -> HolidayRegion? {
        guard let identifier = locale.region?.identifier, let country = HolidayCountry(rawValue: identifier) else { return nil }
        return HolidayRegion(country: country)
    }

    private func currentLocation() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized else { return nil }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { finish(with: locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { finish(with: nil) }
    }

    private func finish(with location: CLLocation?) {
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
}

/// Sets the holiday region of jobs that have none yet.
@MainActor
enum HolidaySetup {
    /// Runs once on the first start: jobs without a region get the detected one.
    static func runInitialDetection(settings: AppSettings, jobs: JobStore) async {
        #if DEBUG
        // The demo shares the preferences with the real app and must not use up the first detection.
        if DemoData.isEnabled { return }
        #endif
        guard !settings.holidayDetectionDone else { return }
        let result = await RegionDetector().detect()
        settings.holidayDetectionDone = true
        guard let region = result.region else { return }
        for job in jobs.jobs where job.holidayRegionCode.isEmpty {
            job.holidayRegion = region
        }
        jobs.save()
    }
}
