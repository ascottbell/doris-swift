import Foundation
import CoreLocation

class DorisAPIService {
    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: "serverURL") ?? "http://100.125.207.74:8000"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "serverURL")
        }
    }

    // MARK: - Chat Types

    struct ChatRequest: Codable {
        let message: String?
        let history: [ChatMessage]?
        let client_context: ClientContext?

        init(message: String, history: [ChatMessage]? = nil, context: ClientContext? = nil) {
            self.message = message
            self.history = history
            self.client_context = context
        }
    }

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ClientLocation: Codable {
        let lat: Double
        let lon: Double
        let accuracy: Double?
    }

    struct ClientContext: Codable {
        let device: String?
        let timestamp: String?
        let location: ClientLocation?

        init(device: String? = nil, location: CLLocation? = nil) {
            #if os(iOS)
            self.device = device ?? "iOS"
            #else
            self.device = device ?? "macOS"
            #endif
            self.timestamp = ISO8601DateFormatter().string(from: Date())

            if let loc = location {
                self.location = ClientLocation(
                    lat: loc.coordinate.latitude,
                    lon: loc.coordinate.longitude,
                    accuracy: loc.horizontalAccuracy
                )
            } else {
                self.location = nil
            }
        }
    }

    struct ChatResponse: Codable {
        let response: String?
        let source: String?
        let latency_ms: Int?

        var text: String {
            response ?? ""
        }
    }

    // MARK: - TTS Types

    struct TTSRequest: Codable {
        let text: String
        let voice: String?

        init(text: String, voice: String? = nil) {
            self.text = text
            self.voice = voice
        }
    }

    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .invalidResponse: return "Invalid response from server"
            case .serverError(let msg): return msg
            }
        }
    }

    // MARK: - Chat

    func chat(message: String, includeAudio: Bool = true) async throws -> (text: String, audioData: Data?) {
        guard let url = URL(string: "\(baseURL)/chat/text") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = ChatRequest(message: message, context: ClientContext(location: nil))
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        let text = chatResponse.text

        // Get TTS audio if requested
        var audioData: Data? = nil
        if includeAudio && !text.isEmpty {
            audioData = try? await textToSpeech(text: text)
        }

        return (text: text, audioData: audioData)
    }

    // MARK: - Text to Speech

    func textToSpeech(text: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/tts") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let ttsRequest = TTSRequest(text: text)
        request.httpBody = try JSONEncoder().encode(ttsRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return data
    }

    func status() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            throw APIError.invalidURL
        }

        let (_, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }

        return true
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
}
