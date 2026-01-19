import Foundation
import Combine
import CoreLocation

/// Shared location service for iOS and macOS
@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        // Check current authorization
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Request location permission
    func requestPermission() {
        #if os(iOS)
        locationManager.requestWhenInUseAuthorization()
        #else
        // macOS - request authorization
        if CLLocationManager.locationServicesEnabled() {
            locationManager.requestWhenInUseAuthorization()
        }
        #endif
    }

    /// Get current location (one-shot)
    func getCurrentLocation() async -> CLLocation? {
        // Check if we have a recent location (within last 5 minutes)
        if let location = currentLocation,
           Date().timeIntervalSince(location.timestamp) < 300 {
            return location
        }

        // Request fresh location
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let cont = self.locationContinuation {
                    self.locationContinuation = nil
                    cont.resume(returning: self.currentLocation)
                }
            }
        }
    }

    /// Start continuous location updates
    func startUpdating() {
        #if os(iOS)
        locationManager.startUpdatingLocation()
        #else
        locationManager.startUpdatingLocation()
        #endif
    }

    /// Stop location updates
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location
            print("LocationService: Updated location - \(location.coordinate.latitude), \(location.coordinate.longitude)")

            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService: Error - \(error.localizedDescription)")

        Task { @MainActor in
            if let continuation = self.locationContinuation {
                self.locationContinuation = nil
                continuation.resume(returning: nil)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            print("LocationService: Authorization changed to \(self.authorizationStatus.rawValue)")
        }
    }
}
