import Foundation
import UIKit

class DorisAPIService {
    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: "serverURL") ?? "http://100.125.207.74:8000"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "serverURL")
        }
    }

    // MARK: - Chat Models

    struct ChatMessage: Codable {
        let role: String  // "user" or "assistant"
        let content: String
    }

    struct ClientLocation: Codable {
        let lat: Double
        let lon: Double
        let accuracy: Double?
    }

    struct ClientContext: Codable {
        let location: ClientLocation?
        let timestamp: String
        let capabilities: [String]
        let device: String
    }

    struct ToolRequest: Codable {
        let tool_name: String
        let parameters: [String: AnyCodable]
        let tool_use_id: String
    }

    struct ToolResult: Codable {
        let tool_name: String
        let status: String
        let tool_use_id: String
        let parameters: [String: AnyCodable]
        let data: AnyCodable
    }

    struct ActionParameter: Codable {
        let lat: Double?
        let lon: Double?
        let label: String?

        init(lat: Double? = nil, lon: Double? = nil, label: String? = nil) {
            self.lat = lat
            self.lon = lon
            self.label = label
        }
    }

    struct ResponseAction: Codable {
        let type: String
        let parameters: ActionParameter?
    }

    struct ChatRequest: Codable {
        let message: String?
        let history: [ChatMessage]?
        let client_context: ClientContext?
        let tool_result: ToolResult?
    }

    struct ChatResponse: Codable {
        let response: String?
        let source: String?
        let latency_ms: Int?
        let tool_request: ToolRequest?
        let actions: [ResponseAction]?
    }

    enum APIError: Error {
        case invalidURL
        case invalidResponse
        case serverError(String)
    }

    // MARK: - Chat API

    func chat(request: ChatRequest) async throws -> ChatResponse {
        guard let url = URL(string: "\(baseURL)/chat/text") else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse
    }

    func status() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/status") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let statusResponse = try JSONDecoder().decode([String: String].self, from: data)
        return statusResponse["status"] == "ok"
    }

    func clearConversation() async throws {
        guard let url = URL(string: "\(baseURL)/clear") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Health Data Sync

    struct HealthSyncResponse: Codable {
        let status: String
        let date: String
        let message: String?
    }

    /// Sync health data to Doris server
    func syncHealth(_ summary: HealthSummary) async throws -> HealthSyncResponse {
        guard let url = URL(string: "\(baseURL)/health/sync") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(summary)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return try JSONDecoder().decode(HealthSyncResponse.self, from: data)
    }

    // MARK: - Device Registration (Push Notifications)

    struct DeviceRegistrationRequest: Codable {
        let device_token: String
        let device_name: String
        let app_version: String
    }

    struct DeviceRegistrationResponse: Codable {
        let status: String
        let device_id: String?
        let message: String?
    }

    /// Register device for push notifications
    func registerDevice(token: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/devices/register") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let deviceName = await MainActor.run { UIDevice.current.name }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let registrationRequest = DeviceRegistrationRequest(
            device_token: token,
            device_name: deviceName,
            app_version: appVersion
        )
        request.httpBody = try JSONEncoder().encode(registrationRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let registrationResponse = try JSONDecoder().decode(DeviceRegistrationResponse.self, from: data)
        return registrationResponse.status == "registered" || registrationResponse.status == "updated"
    }

    // MARK: - Text-to-Speech

    struct TTSRequest: Codable {
        let text: String
    }

    /// Synthesize text to speech using server TTS (Supertonic)
    /// Returns WAV audio data
    func synthesizeSpeech(text: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/tts") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let ttsRequest = TTSRequest(text: text)
        request.httpBody = try JSONEncoder().encode(ttsRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("TTS synthesis failed")
        }

        return data
    }
}

// MARK: - AnyCodable for dynamic JSON values

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }

    // Convenience accessors
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }
}
