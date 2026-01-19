//
//  LocationService.swift
//  Doris
//
//  Created by Adam Bell on 12/31/24.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Known Places

struct KnownPlace {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    
    // Radius in meters to consider "arrived" at this place
    let arrivalRadius: CLLocationDistance
    
    init(name: String, latitude: Double, longitude: Double, address: String, arrivalRadius: CLLocationDistance = 100) {
        self.name = name
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.address = address
        self.arrivalRadius = arrivalRadius
    }
}

// MARK: - Location Service

class LocationService: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var currentLocation: CLLocation?
    @Published var currentPlacemark: CLPlacemark?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isMonitoringSignificantChanges = false
    
    // Continuation for async/await pattern
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    
    // Known places - Adam's locations
    static let knownPlaces: [String: KnownPlace] = [
        "home": KnownPlace(
            name: "Home",
            latitude: 40.7870,  // Approximate for 310 W End Ave
            longitude: -73.9897,
            address: "310 W End Ave, New York, NY 10023"
        ),
        "house": KnownPlace(
            name: "Hudson Valley House",
            latitude: 41.7212,  // Approximate for Highland, NY
            longitude: -73.9654,
            address: "37 Thorns Ln, Highland, NY 12528"
        )
    ]
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Permissions
    
    func requestPermission() {
        print("📍 LocationService: Requesting location permission")
        locationManager.requestWhenInUseAuthorization()
    }
    
    func checkPermission() -> Bool {
        let status = locationManager.authorizationStatus
        return status == .authorized || status == .authorizedAlways
    }
    
    // MARK: - Get Current Location (async)
    
    func getCurrentLocation() async throws -> CLLocation {
        print("📍 LocationService: Getting current location...")
        
        guard checkPermission() else {
            print("📍 LocationService: No permission")
            throw LocationError.permissionDenied
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
    
    // MARK: - Reverse Geocode
    
    func reverseGeocode(location: CLLocation) async throws -> CLPlacemark {
        print("📍 LocationService: Reverse geocoding...")
        
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        
        guard let placemark = placemarks.first else {
            throw LocationError.geocodingFailed
        }
        
        await MainActor.run {
            self.currentPlacemark = placemark
        }
        
        return placemark
    }
    
    // MARK: - Get Human-Readable Location
    
    func getCurrentLocationDescription() async throws -> String {
        let location = try await getCurrentLocation()
        let placemark = try await reverseGeocode(location: location)
        
        var parts: [String] = []
        
        if let neighborhood = placemark.subLocality {
            parts.append(neighborhood)
        }
        if let city = placemark.locality {
            parts.append(city)
        }
        if let state = placemark.administrativeArea {
            parts.append(state)
        }
        
        let description = parts.isEmpty ? "Unknown location" : parts.joined(separator: ", ")
        print("📍 LocationService: Current location: \(description)")
        return description
    }
    
    // MARK: - Distance to Known Place
    
    func distanceTo(placeName: String) async throws -> (meters: Double, description: String) {
        let placeKey = placeName.lowercased()
        
        guard let place = LocationService.knownPlaces[placeKey] else {
            throw LocationError.unknownPlace(placeName)
        }
        
        let currentLocation = try await getCurrentLocation()
        let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        
        let distanceMeters = currentLocation.distance(from: placeLocation)
        let distanceMiles = distanceMeters / 1609.34
        
        let description: String
        if distanceMiles < 0.1 {
            description = "You're basically there"
        } else if distanceMiles < 1 {
            description = String(format: "About %.1f miles away", distanceMiles)
        } else {
            description = String(format: "About %.0f miles away", distanceMiles)
        }
        
        print("📍 LocationService: Distance to \(place.name): \(description)")
        return (distanceMeters, description)
    }
    
    // MARK: - Check if at Known Place
    
    func currentKnownPlace() async throws -> KnownPlace? {
        let currentLocation = try await getCurrentLocation()
        
        for (_, place) in LocationService.knownPlaces {
            let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            
            if distance <= place.arrivalRadius {
                print("📍 LocationService: Currently at \(place.name)")
                return place
            }
        }
        
        print("📍 LocationService: Not at any known place")
        return nil
    }
    
    // MARK: - Significant Location Monitoring (for background updates)
    
    func startMonitoringSignificantLocationChanges() {
        guard checkPermission() else {
            print("📍 LocationService: Can't monitor - no permission")
            return
        }
        
        print("📍 LocationService: Starting significant location monitoring")
        locationManager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = true
    }
    
    func stopMonitoringSignificantLocationChanges() {
        print("📍 LocationService: Stopping significant location monitoring")
        locationManager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = false
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        print("📍 LocationService: Got location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        // Resume any waiting continuation
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(returning: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 LocationService: Error: \(error.localizedDescription)")
        
        // Resume continuation with error
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: LocationError.locationUnavailable(error.localizedDescription))
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("📍 LocationService: Authorization changed to: \(status.rawValue)")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }
}

// MARK: - Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable(String)
    case geocodingFailed
    case unknownPlace(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied. Enable it in System Settings."
        case .locationUnavailable(let reason):
            return "Couldn't get location: \(reason)"
        case .geocodingFailed:
            return "Couldn't determine address from coordinates"
        case .unknownPlace(let name):
            return "I don't know where '\(name)' is. I know: home, house"
        }
    }
}
