//
//  GmailService.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation
import AppKit

class GmailService {
    // OAuth Configuration (shared with Calendar)
    private let clientID: String
    private let clientSecret: String
    private let scope = "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/gmail.compose https://www.googleapis.com/auth/gmail.send"
    
    // Token storage configuration (shared with Calendar)
    private let tokenServiceName = "com.doris.google"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    private let tokenExpiryKey = "token_expiry"
    private let redirectURI = "http://127.0.0.1:8089/oauth/callback"
    
    private var authServer: OAuthCallbackServer?
    
    init() {
        // Read credentials from environment variables
        guard let clientID = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
              let clientSecret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"],
              !clientID.isEmpty, !clientSecret.isEmpty else {
            print("⚠️ Gmail: GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET not set")
            self.clientID = ""
            self.clientSecret = ""
            return
        }
        
        self.clientID = clientID
        self.clientSecret = clientSecret
        print("🟢 Gmail: Initialized with credentials")
    }
    
    // MARK: - Gmail API Methods
    
    func getUnreadCount() async throws -> Int {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "is:unread")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Gmail API Error: \(errorString)")
            }
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let messageList = try JSONDecoder().decode(MessageListResponse.self, from: data)
        return messageList.resultSizeEstimate ?? messageList.messages?.count ?? 0
    }
    
    func getRecentMessages(limit: Int = 10) async throws -> [GmailMessage] {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // First, get the list of message IDs
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "maxResults", value: String(limit))
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (listData, listResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = listResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let messageList = try JSONDecoder().decode(MessageListResponse.self, from: listData)
        
        guard let messageIds = messageList.messages else {
            return []
        }
        
        // Fetch details for each message
        var messages: [GmailMessage] = []
        for messageId in messageIds.prefix(limit) {
            if let message = try await fetchMessage(id: messageId.id, accessToken: accessToken) {
                messages.append(message)
            }
        }
        
        return messages
    }
    
    func getMessagesFromSender(sender: String) async throws -> [GmailMessage] {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // Search for messages from sender
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "from:\(sender)"),
            URLQueryItem(name: "maxResults", value: "10")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (listData, listResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = listResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let messageList = try JSONDecoder().decode(MessageListResponse.self, from: listData)
        
        guard let messageIds = messageList.messages else {
            return []
        }
        
        // Fetch details for each message
        var messages: [GmailMessage] = []
        for messageId in messageIds {
            if let message = try await fetchMessage(id: messageId.id, accessToken: accessToken) {
                messages.append(message)
            }
        }
        
        return messages
    }
    
    // MARK: - Search
    
    func searchMessages(query: String, limit: Int = 10) async throws -> [GmailMessage] {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(limit))
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (listData, listResponse) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = listResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let messageList = try JSONDecoder().decode(MessageListResponse.self, from: listData)
        
        guard let messageIds = messageList.messages else {
            return []
        }
        
        var messages: [GmailMessage] = []
        for messageId in messageIds.prefix(limit) {
            if let message = try await fetchMessage(id: messageId.id, accessToken: accessToken) {
                messages.append(message)
            }
        }
        
        return messages
    }
    
    // MARK: - Send & Reply
    
    func sendEmail(to: String, subject: String, body: String) async throws -> String {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // Build RFC 2822 message
        let message = """
            To: \(to)
            Subject: \(subject)
            Content-Type: text/plain; charset=utf-8
            
            \(body)
            """
        
        // Base64 URL encode
        let messageData = message.data(using: .utf8)!
        let base64Message = messageData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["raw": base64Message]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Gmail Send Error: \(errorString)")
            }
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(SendMessageResponse.self, from: data)
        print("🟢 Gmail: Message sent with ID: \(result.id)")
        return result.id
    }
    
    func replyToEmail(messageId: String, body: String) async throws -> String {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // First, fetch the original message to get headers
        guard let originalMessage = try await fetchMessageFull(id: messageId, accessToken: accessToken) else {
            throw GmailError.messageNotFound
        }
        
        // Build reply headers
        let replyTo = originalMessage.replyTo ?? originalMessage.sender
        let replySubject = originalMessage.subject.hasPrefix("Re: ") ? originalMessage.subject : "Re: \(originalMessage.subject)"
        
        // Build RFC 2822 message with threading headers
        let message = """
            To: \(replyTo)
            Subject: \(replySubject)
            Content-Type: text/plain; charset=utf-8
            In-Reply-To: \(originalMessage.messageIdHeader ?? "")
            References: \(originalMessage.messageIdHeader ?? "")
            
            \(body)
            """
        
        // Base64 URL encode
        let messageData = message.data(using: .utf8)!
        let base64Message = messageData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "raw": base64Message,
            "threadId": originalMessage.threadId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Gmail Reply Error: \(errorString)")
            }
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(SendMessageResponse.self, from: data)
        print("🟢 Gmail: Reply sent with ID: \(result.id)")
        return result.id
    }
    
    // MARK: - Labels & Organization
    
    func addLabel(messageId: String, labelName: String) async throws {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // First, get or create the label
        let labelId = try await getOrCreateLabel(name: labelName, accessToken: accessToken)
        
        // Add label to message
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["addLabelIds": [labelId]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Gmail Label Error: \(errorString)")
            }
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("🟢 Gmail: Label '\(labelName)' added to message")
    }
    
    func removeLabel(messageId: String, labelName: String) async throws {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        // Get label ID
        guard let labelId = try await getLabelId(name: labelName, accessToken: accessToken) else {
            throw GmailError.labelNotFound
        }
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["removeLabelIds": [labelId]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("🟢 Gmail: Label '\(labelName)' removed from message")
    }
    
    func archiveMessage(messageId: String) async throws {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Archive = remove INBOX label
        let payload = ["removeLabelIds": ["INBOX"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("🟢 Gmail: Message archived")
    }
    
    func markAsRead(messageId: String) async throws {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["removeLabelIds": ["UNREAD"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("🟢 Gmail: Message marked as read")
    }
    
    func markAsUnread(messageId: String) async throws {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["addLabelIds": ["UNREAD"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("🟢 Gmail: Message marked as unread")
    }
    
    func trashMessage(messageId: String) async throws {
        try await ensureAuthenticated()
        
        guard let accessToken = getAccessToken() else {
            throw GmailError.notAuthenticated
        }
        
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/trash")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        print("🟢 Gmail: Message moved to trash")
    }
    
    // MARK: - Helper Methods
    
    private func getOrCreateLabel(name: String, accessToken: String) async throws -> String {
        // First try to find existing label
        if let labelId = try await getLabelId(name: name, accessToken: accessToken) {
            return labelId
        }
        
        // Create new label
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "name": name,
            "labelListVisibility": "labelShow",
            "messageListVisibility": "show"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let label = try JSONDecoder().decode(GmailLabel.self, from: data)
        print("🟢 Gmail: Created label '\(name)'")
        return label.id
    }
    
    private func getLabelId(name: String, accessToken: String) async throws -> String? {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let labelList = try JSONDecoder().decode(LabelListResponse.self, from: data)
        return labelList.labels?.first(where: { $0.name == name })?.id
    }
    
    private func fetchMessageFull(id: String, accessToken: String) async throws -> GmailMessageFull? {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "To"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
            URLQueryItem(name: "metadataHeaders", value: "Message-ID"),
            URLQueryItem(name: "metadataHeaders", value: "Reply-To")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            return nil
        }
        
        let apiMessage = try JSONDecoder().decode(APIMessageFull.self, from: data)
        return GmailMessageFull(from: apiMessage)
    }
    
    private func fetchMessage(id: String, accessToken: String) async throws -> GmailMessage? {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            return nil
        }
        
        let apiMessage = try JSONDecoder().decode(APIMessage.self, from: data)
        return GmailMessage(from: apiMessage)
    }
    
    private func ensureAuthenticated() async throws {
        // Try to refresh if expired
        if isTokenExpired() {
            if let refreshToken = getRefreshToken() {
                do {
                    try await refreshAccessToken(refreshToken: refreshToken)
                    return
                } catch {
                    print("🔴 Gmail: Failed to refresh token: \(error)")
                }
            }
            throw GmailError.notAuthenticated
        }
        
        if getAccessToken() == nil {
            throw GmailError.notAuthenticated
        }
    }
    
    // MARK: - OAuth Authentication
    
    var isAuthenticated: Bool {
        return getAccessToken() != nil && !isTokenExpired()
    }
    
    func authenticate() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw GmailError.notAuthenticated
        }
        
        print("📧 Gmail: Starting OAuth flow...")
        
        // Start local server to receive callback
        let server = OAuthCallbackServer(port: 8089)
        self.authServer = server
        
        try await server.start()
        
        // Build authorization URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        // Open browser
        if let url = components.url {
            print("📧 Gmail: Opening browser for authentication...")
            NSWorkspace.shared.open(url)
        }
        
        // Wait for callback with authorization code
        let code = try await server.waitForCode(timeout: 120)
        
        print("📧 Gmail: Received authorization code, exchanging for tokens...")
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
        
        // Stop server
        await server.stop()
        self.authServer = nil
        
        print("🟢 Gmail: Authentication successful!")
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("🔴 Gmail Token Error: \(errorString)")
            }
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        saveTokens(tokenResponse)
    }
    
    private func refreshAccessToken(refreshToken: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw GmailError.apiError(statusCode: httpResponse.statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        saveTokens(tokenResponse, existingRefreshToken: refreshToken)
        print("🟢 Gmail: Token refreshed")
    }
    
    private func saveTokens(_ response: TokenResponse, existingRefreshToken: String? = nil) {
        UserDefaults.standard.set(response.access_token, forKey: "\(tokenServiceName).\(accessTokenKey)")
        
        // Refresh token is only returned on initial auth, not on refresh
        if let refreshToken = response.refresh_token ?? existingRefreshToken {
            UserDefaults.standard.set(refreshToken, forKey: "\(tokenServiceName).\(refreshTokenKey)")
        }
        
        let expiry = Date().addingTimeInterval(TimeInterval(response.expires_in))
        UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: "\(tokenServiceName).\(tokenExpiryKey)")
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: "\(tokenServiceName).\(accessTokenKey)")
        UserDefaults.standard.removeObject(forKey: "\(tokenServiceName).\(refreshTokenKey)")
        UserDefaults.standard.removeObject(forKey: "\(tokenServiceName).\(tokenExpiryKey)")
        print("📧 Gmail: Logged out")
    }
    
    // MARK: - Token Storage (shared with Calendar - UserDefaults)
    
    private func getAccessToken() -> String? {
        return UserDefaults.standard.string(forKey: "\(tokenServiceName).\(accessTokenKey)")
    }
    
    private func getRefreshToken() -> String? {
        return UserDefaults.standard.string(forKey: "\(tokenServiceName).\(refreshTokenKey)")
    }
    
    private func getTokenExpiry() -> Date? {
        let interval = UserDefaults.standard.double(forKey: "\(tokenServiceName).\(tokenExpiryKey)")
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
    
    private func isTokenExpired() -> Bool {
        guard let expiry = getTokenExpiry() else { return true }
        return Date() >= expiry.addingTimeInterval(-60)
    }
    
    // MARK: - Formatting
    
    static func formatMessages(_ messages: [GmailMessage]) -> String {
        guard !messages.isEmpty else {
            return "No messages found."
        }
        
        var result = ""
        for (index, message) in messages.enumerated() {
            if index > 0 { result += "\n" }
            
            result += "• \(message.subject)\n"
            result += "  From: \(message.sender) · \(formatRelativeTime(message.date))\n"
            
            if let snippet = message.snippet, !snippet.isEmpty {
                let trimmedSnippet = snippet.prefix(60)
                result += "  \(trimmedSnippet)\(snippet.count > 60 ? "..." : "")\n"
            }
        }
        
        return result
    }
    
    static func formatUnreadCount(_ count: Int) -> String {
        if count == 0 {
            return "No unread messages."
        } else if count == 1 {
            return "1 unread message."
        } else {
            return "\(count) unread messages."
        }
    }
    
    private static func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 172800 {
            return "yesterday"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Models

struct GmailMessage {
    let id: String
    let sender: String
    let subject: String
    let snippet: String?
    let date: Date
    
    init(from apiMessage: APIMessage) {
        self.id = apiMessage.id
        self.snippet = apiMessage.snippet
        
        // Parse headers
        var sender = "Unknown"
        var subject = "(No Subject)"
        var dateString: String?
        
        if let headers = apiMessage.payload?.headers {
            for header in headers {
                switch header.name.lowercased() {
                case "from":
                    sender = header.value
                case "subject":
                    subject = header.value
                case "date":
                    dateString = header.value
                default:
                    break
                }
            }
        }
        
        // Extract email from "Name <email@domain.com>" format
        if let emailMatch = sender.range(of: #"<([^>]+)>"#, options: .regularExpression) {
            let email = String(sender[emailMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            if let nameEnd = sender.firstIndex(of: "<") {
                let name = String(sender[..<nameEnd]).trimmingCharacters(in: .whitespaces)
                sender = name.isEmpty ? email : name
            }
        }
        
        self.sender = sender
        self.subject = subject
        
        // Parse date
        if let dateStr = dateString {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            self.date = formatter.date(from: dateStr) ?? Date()
        } else {
            self.date = Date()
        }
    }
}

struct APIMessage: Codable {
    let id: String
    let snippet: String?
    let payload: Payload?
    
    struct Payload: Codable {
        let headers: [Header]?
    }
    
    struct Header: Codable {
        let name: String
        let value: String
    }
}

struct MessageListResponse: Codable {
    let messages: [MessageId]?
    let resultSizeEstimate: Int?
    
    struct MessageId: Codable {
        let id: String
    }
}

// Full message with threading info for replies
struct GmailMessageFull {
    let id: String
    let threadId: String
    let sender: String
    let replyTo: String?
    let subject: String
    let messageIdHeader: String?
    
    init(from apiMessage: APIMessageFull) {
        self.id = apiMessage.id
        self.threadId = apiMessage.threadId
        
        var sender = "Unknown"
        var subject = "(No Subject)"
        var replyTo: String? = nil
        var messageIdHeader: String? = nil
        
        if let headers = apiMessage.payload?.headers {
            for header in headers {
                switch header.name.lowercased() {
                case "from":
                    sender = header.value
                case "subject":
                    subject = header.value
                case "reply-to":
                    replyTo = header.value
                case "message-id":
                    messageIdHeader = header.value
                default:
                    break
                }
            }
        }
        
        self.sender = sender
        self.subject = subject
        self.replyTo = replyTo
        self.messageIdHeader = messageIdHeader
    }
}

struct APIMessageFull: Codable {
    let id: String
    let threadId: String
    let payload: Payload?
    
    struct Payload: Codable {
        let headers: [Header]?
    }
    
    struct Header: Codable {
        let name: String
        let value: String
    }
}

struct SendMessageResponse: Codable {
    let id: String
    let threadId: String
}

struct GmailLabel: Codable {
    let id: String
    let name: String
}

struct LabelListResponse: Codable {
    let labels: [GmailLabel]?
}

enum GmailError: LocalizedError {
    case notAuthenticated
    case apiError(statusCode: Int)
    case messageNotFound
    case labelNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Gmail"
        case .apiError(let statusCode):
            return "Gmail API error (HTTP \(statusCode))"
        case .messageNotFound:
            return "Message not found"
        case .labelNotFound:
            return "Label not found"
        }
    }
}
