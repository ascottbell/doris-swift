import Foundation
import CoreLocation
import MapKit

/// Service for getting directions and ETAs using MapKit
class DirectionsService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Location Authorization

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    var hasLocationPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - Get Current Location

    func getCurrentLocation() async throws -> CLLocation {
        guard hasLocationPermission else {
            throw DirectionsError.locationNotAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    // MARK: - Search for Destination

    /// Search for a place by name or address
    func searchDestination(_ query: String, near location: CLLocation? = nil) async throws -> MKMapItem {
        let results = try await searchDestinations(query, near: location, limit: 1)
        guard let first = results.first else {
            throw DirectionsError.destinationNotFound
        }
        return first
    }

    /// Search for multiple places by name or address, sorted by distance
    func searchDestinations(_ query: String, near location: CLLocation? = nil, limit: Int = 10) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        if let location = location {
            // Search near current location
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50000,  // 50km radius
                longitudinalMeters: 50000
            )
            request.region = region
        }

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        guard !response.mapItems.isEmpty else {
            throw DirectionsError.destinationNotFound
        }

        // Sort by distance from current location if available
        var items = response.mapItems
        if let location = location {
            items.sort { item1, item2 in
                let dist1 = item1.placemark.location?.distance(from: location) ?? .infinity
                let dist2 = item2.placemark.location?.distance(from: location) ?? .infinity
                return dist1 < dist2
            }
        }

        return Array(items.prefix(limit))
    }

    // MARK: - Get Directions & ETA

    struct DirectionsResult {
        let destination: MKMapItem
        let destinationName: String
        let travelTime: TimeInterval
        let distance: CLLocationDistance
        let transportType: MKDirectionsTransportType
        let mapsURL: URL

        var formattedTravelTime: String {
            let minutes = Int(travelTime / 60)
            if minutes < 60 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s")"
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                if remainingMinutes == 0 {
                    return "\(hours) hour\(hours == 1 ? "" : "s")"
                } else {
                    return "\(hours) hour\(hours == 1 ? "" : "s") and \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
                }
            }
        }

        var formattedDistance: String {
            let miles = distance / 1609.34
            if miles < 0.1 {
                let feet = Int(distance * 3.28084)
                return "\(feet) feet"
            } else if miles < 10 {
                return String(format: "%.1f miles", miles)
            } else {
                return String(format: "%.0f miles", miles)
            }
        }

        var transportModeDescription: String {
            switch transportType {
            case .walking: return "walk"
            case .transit: return "transit ride"
            case .automobile: return "drive"
            default: return "trip"
            }
        }
    }

    /// Get directions from current location to a destination
    func getDirections(
        to destination: String,
        transportType: MKDirectionsTransportType = .automobile
    ) async throws -> DirectionsResult {
        return try await getDirectionsAlternative(to: destination, resultIndex: 0, transportType: transportType)
    }

    /// Get directions to an alternative (nth closest) destination
    func getDirectionsAlternative(
        to destination: String,
        resultIndex: Int,
        transportType: MKDirectionsTransportType = .automobile
    ) async throws -> DirectionsResult {
        // Get current location
        let currentLocation = try await getCurrentLocation()

        // Search for multiple destinations
        let destinationItems = try await searchDestinations(destination, near: currentLocation, limit: 10)

        guard resultIndex < destinationItems.count else {
            throw DirectionsError.noRouteFound
        }

        let destinationItem = destinationItems[resultIndex]

        // Calculate route
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = destinationItem
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else {
            throw DirectionsError.noRouteFound
        }

        // Build Apple Maps URL
        let mapsURL = buildMapsURL(
            destination: destinationItem,
            transportType: transportType
        )

        let destinationName = destinationItem.name ?? destinationItem.placemark.title ?? destination

        return DirectionsResult(
            destination: destinationItem,
            destinationName: destinationName,
            travelTime: route.expectedTravelTime,
            distance: route.distance,
            transportType: transportType,
            mapsURL: mapsURL
        )
    }

    // MARK: - Build Maps URL

    private func buildMapsURL(destination: MKMapItem, transportType: MKDirectionsTransportType) -> URL {
        var components = URLComponents(string: "maps://")!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "saddr", value: "Current Location"),
        ]

        // Always use coordinates to ensure Maps routes to the exact location we calculated
        let coord = destination.placemark.coordinate
        queryItems.append(URLQueryItem(name: "daddr", value: "\(coord.latitude),\(coord.longitude)"))

        // Transport type flag
        let dirFlag: String
        switch transportType {
        case .walking: dirFlag = "w"
        case .transit: dirFlag = "r"
        case .automobile: dirFlag = "d"
        default: dirFlag = "d"
        }
        queryItems.append(URLQueryItem(name: "dirflg", value: dirFlag))

        components.queryItems = queryItems
        return components.url!
    }

    /// Open Apple Maps with directions
    func openMaps(url: URL) {
        UIApplication.shared.open(url)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(returning: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("DirectionsService: Location error: \(error.localizedDescription)")

        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: DirectionsError.locationError(error.localizedDescription))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        print("DirectionsService: Authorization status changed to \(authorizationStatus.rawValue)")
    }
}

enum DirectionsError: LocalizedError {
    case locationNotAuthorized
    case locationError(String)
    case destinationNotFound
    case noRouteFound

    var errorDescription: String? {
        switch self {
        case .locationNotAuthorized:
            return "Location access not authorized. Please enable location in Settings."
        case .locationError(let message):
            return "Could not get your location: \(message)"
        case .destinationNotFound:
            return "Couldn't find that destination."
        case .noRouteFound:
            return "Couldn't find a route to that destination."
        }
    }
}
