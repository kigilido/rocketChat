//
//  LocationService.swift
//  RocketChat
//

import Foundation
import CoreLocation

/// Wraps CoreLocation to provide one-shot location fixes used to geotag scans.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Request a single fresh fix (battery friendly).
    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// Reverse-geocode a coordinate into a short place name.
    func placeName(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        return placemark?.name ?? placemark?.locality
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: scans simply won't be geotagged until a fix arrives.
    }
}
