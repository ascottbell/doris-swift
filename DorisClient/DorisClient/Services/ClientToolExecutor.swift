import Foundation
import CoreLocation
import MapKit

/// Executes client-side tools requested by the server and returns structured results
class ClientToolExecutor {
    private let directions: DirectionsService

    init(directions: DirectionsService) {
        self.directions = directions
    }

    // MARK: - Tool Execution

    /// Execute a tool request and return a tool result
    func execute(_ toolRequest: DorisAPIService.ToolRequest) async throws -> DorisAPIService.ToolResult {
        switch toolRequest.tool_name {
        case "search_local_places":
            return try await executeSearchLocalPlaces(toolRequest)
        case "get_directions":
            return try await executeGetDirections(toolRequest)
        default:
            return errorResult(
                toolRequest: toolRequest,
                error: "Unknown tool: \(toolRequest.tool_name)"
            )
        }
    }

    // MARK: - search_local_places

    private func executeSearchLocalPlaces(_ toolRequest: DorisAPIService.ToolRequest) async throws -> DorisAPIService.ToolResult {
        guard let query = toolRequest.parameters["query"]?.stringValue else {
            return errorResult(toolRequest: toolRequest, error: "Missing required parameter: query")
        }

        do {
            // Get current location for proximity search
            let currentLocation = try await directions.getCurrentLocation()

            // Search for places
            let mapItems = try await directions.searchDestinations(query, near: currentLocation, limit: 5)

            // Convert to result format
            let places = mapItems.map { item -> [String: Any] in
                var place: [String: Any] = [
                    "name": item.name ?? "Unknown",
                    "lat": item.placemark.coordinate.latitude,
                    "lon": item.placemark.coordinate.longitude
                ]

                // Add distance if we have location
                if let itemLocation = item.placemark.location {
                    place["distance_meters"] = Int(itemLocation.distance(from: currentLocation))
                }

                // Add address if available
                if let address = item.placemark.title {
                    place["address"] = address
                }

                return place
            }

            return DorisAPIService.ToolResult(
                tool_name: toolRequest.tool_name,
                status: "success",
                tool_use_id: toolRequest.tool_use_id,
                parameters: toolRequest.parameters,
                data: AnyCodable(places)
            )

        } catch {
            return errorResult(toolRequest: toolRequest, error: error.localizedDescription)
        }
    }

    // MARK: - get_directions

    private func executeGetDirections(_ toolRequest: DorisAPIService.ToolRequest) async throws -> DorisAPIService.ToolResult {
        // Parse parameters - can accept either coordinates or a place name
        let lat = toolRequest.parameters["lat"]?.doubleValue
        let lon = toolRequest.parameters["lon"]?.doubleValue
        let destination = toolRequest.parameters["destination"]?.stringValue
        let transportMode = toolRequest.parameters["transport_mode"]?.stringValue ?? "driving"

        let transportType: MKDirectionsTransportType
        switch transportMode {
        case "walking": transportType = .walking
        case "transit": transportType = .transit
        default: transportType = .automobile
        }

        do {
            let result: DirectionsService.DirectionsResult

            if let lat = lat, let lon = lon {
                // Direct coordinate-based directions
                result = try await getDirectionsToCoordinate(
                    lat: lat,
                    lon: lon,
                    transportType: transportType
                )
            } else if let destination = destination {
                // Place name search
                result = try await directions.getDirections(to: destination, transportType: transportType)
            } else {
                return errorResult(toolRequest: toolRequest, error: "Missing required parameter: either lat/lon or destination")
            }

            let routeData: [String: Any] = [
                "destination_name": result.destinationName,
                "destination_lat": result.destination.placemark.coordinate.latitude,
                "destination_lon": result.destination.placemark.coordinate.longitude,
                "travel_time_seconds": Int(result.travelTime),
                "travel_time_formatted": result.formattedTravelTime,
                "distance_meters": Int(result.distance),
                "distance_formatted": result.formattedDistance,
                "transport_mode": result.transportModeDescription
            ]

            return DorisAPIService.ToolResult(
                tool_name: toolRequest.tool_name,
                status: "success",
                tool_use_id: toolRequest.tool_use_id,
                parameters: toolRequest.parameters,
                data: AnyCodable(routeData)
            )

        } catch {
            return errorResult(toolRequest: toolRequest, error: error.localizedDescription)
        }
    }

    /// Get directions to a specific coordinate
    private func getDirectionsToCoordinate(
        lat: Double,
        lon: Double,
        transportType: MKDirectionsTransportType
    ) async throws -> DirectionsService.DirectionsResult {
        let currentLocation = try await directions.getCurrentLocation()

        let destinationCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let destinationPlacemark = MKPlacemark(coordinate: destinationCoord)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)

        // Calculate route
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = destinationItem
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        let directionsRequest = MKDirections(request: request)
        let response = try await directionsRequest.calculate()

        guard let route = response.routes.first else {
            throw DirectionsError.noRouteFound
        }

        // Build Apple Maps URL
        var components = URLComponents(string: "maps://")!
        components.queryItems = [
            URLQueryItem(name: "saddr", value: "Current Location"),
            URLQueryItem(name: "daddr", value: "\(lat),\(lon)"),
            URLQueryItem(name: "dirflg", value: transportType == .walking ? "w" : transportType == .transit ? "r" : "d")
        ]

        return DirectionsService.DirectionsResult(
            destination: destinationItem,
            destinationName: destinationItem.name ?? "Destination",
            travelTime: route.expectedTravelTime,
            distance: route.distance,
            transportType: transportType,
            mapsURL: components.url!
        )
    }

    // MARK: - Helpers

    private func errorResult(toolRequest: DorisAPIService.ToolRequest, error: String) -> DorisAPIService.ToolResult {
        return DorisAPIService.ToolResult(
            tool_name: toolRequest.tool_name,
            status: "error",
            tool_use_id: toolRequest.tool_use_id,
            parameters: toolRequest.parameters,
            data: AnyCodable(["error": error])
        )
    }
}
