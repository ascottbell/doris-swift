//
//  GoogleCalendarService.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation
import AppKit
import Security

class GoogleCalendarService {
    // OAuth Configuration
    private let clientID: String
    private let clientSecret: String
    private var redirectURI = "http://localhost:8080/callback"  // Will be updated based on available port
    private let scope = "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.compose https://www.googleapis.com/auth/gmail.send"
    
    // Calendar configuration
    private let calendarDisplayName = "Indestructible" // Your main calendar display name
    private var cachedCalendarID: String? // Will be populated on first use
    
    // Keychain configuration (shared with Gmail)
    private let keychainServiceName = "com.doris.google"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    private let tokenExpiryKey = "token_expiry"
    
    // OAuth server
    private var authServer: HTTPServer?
    private var authContinuation: CheckedContinuation<String, Error>?
    
    init() {
        // Read credentials from environment variables
        guard let clientID = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
              let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"],
              !clientID.isEmpty, !clientSecret.isEmpty else {
            print("⚠️ GoogleCalendar: GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET not set")
            self.clientID = ""
            self.clientSecret = ""
            return
        }
        
        self.clientID = clientID
        self.clientSecret = clientSecret
        print("🟢 GoogleCalendar: Initialized with credentials")
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws {
        guard !clientID.isEmpty else {
            throw CalendarError.missingCredentials
        }
        
        // Check if we already have valid tokens
        if getAccessToken() != nil, !isTokenExpired() {
            print("🟢 GoogleCalendar: Already authenticated")
            return
        }
        
        // Try to refresh token if we have one
        if let refreshToken = getRefreshToken() {
            do {
                try await refreshAccessToken(refreshToken: refreshToken)
                print("🟢 GoogleCalendar: Token refreshed")
                return
            } catch {
                print("⚠️ GoogleCalendar: Token refresh failed, starting new auth flow")
            }
        }
        
        // Start new OAuth flow
        try await performOAuthFlow()
    }
    
    private func performOAuthFlow() async throws {
        let state = UUID().uuidString
        
        // Build authorization URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            throw CalendarError.invalidURL
        }
        
        print("🔵 GoogleCalendar: Opening auth URL in browser...")
        
        // Open browser
        await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }
        
        // Start local server and wait for callback
        let authCode = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.authContinuation = continuation
            
            // Try ports 8080-8090
            var serverStarted = false
            for port in 8080...8090 {
                do {
                    self.authServer = try HTTPServer(port: UInt16(port)) { [weak self] request in
                        self?.handleOAuthCallback(request: request, expectedState: state)
                    }
                    try self.authServer!.start()
                    
                    // Update redirect URI to match the port we actually got
                    self.redirectURI = "http://localhost:\(port)/callback"
                    
                    print("🟢 GoogleCalendar: Local server started on port \(port)")
                    serverStarted = true
                    break
                } catch {
                    print("🟡 GoogleCalendar: Port \(port) unavailable, trying next...")
                    continue
                }
            }
            
            if !serverStarted {
                continuation.resume(throwing: CalendarError.serverError(NSError(domain: "HTTPServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not bind to any port 8080-8090"])))
            }
        }
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: authCode)
        
        // Stop server
        authServer?.stop()
        authServer = nil
    }
    
    private func handleOAuthCallback(request: HTTPRequest, expectedState: String) {
        print("🔵 GoogleCalendar: Received callback")
        
        // Only handle /callback path, ignore other requests (like favicon)
        guard request.path.starts(with: "/callback") else {
            print("🟡 GoogleCalendar: Ignoring non-callback request: \(request.path)")
            return
        }
        
        // Make sure we haven't already resumed the continuation
        guard authContinuation != nil else {
            print("🟡 GoogleCalendar: Callback already handled, ignoring duplicate")
            return
        }
        
        guard let components = URLComponents(string: "http://localhost\(request.path)"),
              let queryItems = components.queryItems else {
            let continuation = authContinuation
            authContinuation = nil
            continuation?.resume(throwing: CalendarError.invalidCallback)
            return
        }
        
        let params = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        
        // Check state
        guard params["state"] == expectedState else {
            let continuation = authContinuation
            authContinuation = nil
            continuation?.resume(throwing: CalendarError.stateMismatch)
            return
        }
        
        // Get authorization code
        let continuation = authContinuation
        authContinuation = nil  // Clear it before resuming
        
        if let code = params["code"] {
            continuation?.resume(returning: code)
        } else if let error = params["error"] {
            continuation?.resume(throwing: CalendarError.authorizationDenied(error))
        } else {
            continuation?.resume(throwing: CalendarError.invalidCallback)
        }
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        print("🔵 GoogleCalendar: Exchanging code for tokens...")
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        // Store tokens in keychain
        saveAccessToken(response.access_token)
        if let refreshToken = response.refresh_token {
            saveRefreshToken(refreshToken)
        }
        
        // Calculate and store expiry time
        let expiryDate = Date().addingTimeInterval(TimeInterval(response.expires_in))
        saveTokenExpiry(expiryDate)
        
        print("🟢 GoogleCalendar: Tokens saved successfully")
    }
    
    private func refreshAccessToken(refreshToken: String) async throws {
        print("🔵 GoogleCalendar: Refreshing access token...")
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        saveAccessToken(response.access_token)
        let expiryDate = Date().addingTimeInterval(TimeInterval(response.expires_in))
        saveTokenExpiry(expiryDate)
        
        print("🟢 GoogleCalendar: Access token refreshed")
    }
    
    // MARK: - Calendar API Methods
    
    private func getCalendarID() async throws -> String {
        // Return cached ID if we have it
        if let cached = cachedCalendarID {
            return cached
        }
        
        // Otherwise, fetch the calendar list and find our calendar
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw CalendarError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 GoogleCalendar: Error fetching calendar list: \(errorString)")
            }
            throw CalendarError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let calendarList = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        
        // Find calendar by display name
        if let calendar = calendarList.items.first(where: { $0.summary == calendarDisplayName }) {
            cachedCalendarID = calendar.id
            print("🟢 GoogleCalendar: Found calendar '\(calendarDisplayName)' with ID: \(calendar.id)")
            return calendar.id
        }
        
        // If not found, list all calendars to help debug
        print("🔴 GoogleCalendar: Calendar '\(calendarDisplayName)' not found. Available calendars:")
        for calendar in calendarList.items {
            print("  - \(calendar.summary) (ID: \(calendar.id))")
        }
        
        throw CalendarError.calendarNotFound
    }
    
    func getTodaysEvents() async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return try await getEvents(from: startOfDay, to: endOfDay)
    }
    
    func getEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        let calendarID = try await getCalendarID()
        
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw CalendarError.notAuthenticated
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        let timeMin = dateFormatter.string(from: startDate)
        let timeMax = dateFormatter.string(from: endDate)
        
        // URL encode the calendar ID
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "100")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for API errors
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 GoogleCalendar API Error: \(errorString)")
            }
            throw CalendarError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let apiResponse = try JSONDecoder().decode(EventsResponse.self, from: data)
        
        return apiResponse.items.map { CalendarEvent(from: $0) }
    }
    
    func getNextUpcomingEvent() async throws -> CalendarEvent? {
        let calendarID = try await getCalendarID()
        
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw CalendarError.notAuthenticated
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        let timeMin = dateFormatter.string(from: Date())
        
        // URL encode the calendar ID
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for API errors
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 GoogleCalendar API Error: \(errorString)")
            }
            throw CalendarError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let apiResponse = try JSONDecoder().decode(EventsResponse.self, from: data)
        
        return apiResponse.items.first.map { CalendarEvent(from: $0) }
    }
    
    func createEvent(title: String, startTime: Date, endTime: Date, description: String? = nil, location: String? = nil) async throws -> CalendarEvent {
        let calendarID = try await getCalendarID()
        
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw CalendarError.notAuthenticated
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        var eventData: [String: Any] = [
            "summary": title,
            "start": ["dateTime": dateFormatter.string(from: startTime)],
            "end": ["dateTime": dateFormatter.string(from: endTime)]
        ]
        
        if let description = description {
            eventData["description"] = description
        }
        
        if let location = location {
            eventData["location"] = location
        }
        
        // URL encode the calendar ID
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let apiEvent = try JSONDecoder().decode(APIEvent.self, from: data)
        
        return CalendarEvent(from: apiEvent)
    }
    
    private func ensureAuthenticated() async throws {
        if getAccessToken() == nil || isTokenExpired() {
            try await authenticate()
        }
    }
    
    // MARK: - Token Storage (UserDefaults for now to avoid keychain prompts)
    
    private func saveAccessToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "\(keychainServiceName).\(accessTokenKey)")
    }
    
    private func getAccessToken() -> String? {
        return UserDefaults.standard.string(forKey: "\(keychainServiceName).\(accessTokenKey)")
    }
    
    private func saveRefreshToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "\(keychainServiceName).\(refreshTokenKey)")
    }
    
    private func getRefreshToken() -> String? {
        return UserDefaults.standard.string(forKey: "\(keychainServiceName).\(refreshTokenKey)")
    }
    
    private func saveTokenExpiry(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "\(keychainServiceName).\(tokenExpiryKey)")
    }
    
    private func getTokenExpiry() -> Date? {
        let interval = UserDefaults.standard.double(forKey: "\(keychainServiceName).\(tokenExpiryKey)")
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
    
    private func isTokenExpired() -> Bool {
        guard let expiry = getTokenExpiry() else { return true }
        return Date() >= expiry.addingTimeInterval(-60) // Refresh 1 minute early
    }
    
    // MARK: - Formatting
    
    static func formatEvents(_ events: [CalendarEvent]) -> String {
        guard !events.isEmpty else {
            return "No events found."
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        var result = ""
        for event in events {
            result += "• \(event.title)"
            
            if let start = event.startTime {
                result += " at \(formatter.string(from: start))"
            }
            
            if let location = event.location {
                result += " (\(location))"
            }
            
            result += "\n"
        }
        
        return result
    }
}

// MARK: - Models

struct CalendarEvent {
    let id: String
    let title: String
    let startTime: Date?
    let endTime: Date?
    let location: String?
    let description: String?
    var isAllDay: Bool = false
    
    init(from apiEvent: APIEvent) {
        self.id = apiEvent.id
        self.title = apiEvent.summary
        self.location = apiEvent.location
        self.description = apiEvent.description
        self.isAllDay = apiEvent.start.date != nil && apiEvent.start.dateTime == nil
        
        let formatter = ISO8601DateFormatter()
        
        if let dateTimeString = apiEvent.start.dateTime {
            self.startTime = formatter.date(from: dateTimeString)
        } else if let dateString = apiEvent.start.date {
            // All-day event
            self.startTime = ISO8601DateFormatter().date(from: dateString + "T00:00:00Z")
        } else {
            self.startTime = nil
        }
        
        if let dateTimeString = apiEvent.end.dateTime {
            self.endTime = formatter.date(from: dateTimeString)
        } else if let dateString = apiEvent.end.date {
            self.endTime = ISO8601DateFormatter().date(from: dateString + "T00:00:00Z")
        } else {
            self.endTime = nil
        }
    }
    
    // Init for Apple Calendar events
    init(id: String, title: String, startTime: Date?, endTime: Date?, location: String?, description: String?, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.description = description
        self.isAllDay = isAllDay
    }
}

struct APIEvent: Codable {
    let id: String
    let summary: String
    let start: EventTime
    let end: EventTime
    let location: String?
    let description: String?
}

struct EventTime: Codable {
    let dateTime: String?
    let date: String?
}

struct EventsResponse: Codable {
    let items: [APIEvent]
}

struct CalendarListResponse: Codable {
    let items: [CalendarListEntry]
}

struct CalendarListEntry: Codable {
    let id: String
    let summary: String
}

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}

enum CalendarError: LocalizedError {
    case missingCredentials
    case invalidURL
    case serverError(Error)
    case invalidCallback
    case stateMismatch
    case authorizationDenied(String)
    case notAuthenticated
    case apiError(statusCode: Int)
    case calendarNotFound
    
    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Google Calendar credentials not configured"
        case .invalidURL:
            return "Invalid URL"
        case .serverError(let error):
            return "Server error: \(error.localizedDescription)"
        case .invalidCallback:
            return "Invalid OAuth callback"
        case .stateMismatch:
            return "OAuth state mismatch"
        case .authorizationDenied(let error):
            return "Authorization denied: \(error)"
        case .notAuthenticated:
            return "Not authenticated with Google Calendar"
        case .apiError(let statusCode):
            return "Calendar API error (HTTP \(statusCode))"
        case .calendarNotFound:
            return "Calendar not found - check console for available calendars"
        }
    }
}

// MARK: - Simple HTTP Server for OAuth Callback

class HTTPServer {
    private let port: UInt16
    private let handler: (HTTPRequest) -> Void
    private var serverSocket: Int32 = -1
    private var isRunning = false
    
    init(port: UInt16, handler: @escaping (HTTPRequest) -> Void) {
        self.port = port
        self.handler = handler
    }
    
    func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: "HTTPServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else {
            throw NSError(domain: "HTTPServer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"])
        }
        
        listen(serverSocket, 5)
        isRunning = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptConnections()
        }
    }
    
    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
    
    private func acceptConnections() {
        while isRunning {
            let clientSocket = accept(serverSocket, nil, nil)
            guard clientSocket >= 0 else { continue }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(socket: clientSocket)
            }
        }
    }
    
    private func handleClient(socket: Int32) {
        defer { close(socket) }
        
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(socket, &buffer, buffer.count)
        
        guard bytesRead > 0,
              let requestString = String(bytes: buffer[..<bytesRead], encoding: .utf8) else {
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let request = HTTPRequest(method: components[0], path: components[1])
        handler(request)
        
        // Send response
        let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html\r
            Connection: close\r
            \r
            <html><body><h1>Authentication successful!</h1><p>You can close this window.</p></body></html>
            """
        
        response.data(using: .utf8)?.withUnsafeBytes { bytes in
            _ = write(socket, bytes.baseAddress, bytes.count)
        }
    }
}

struct HTTPRequest {
    let method: String
    let path: String
}
