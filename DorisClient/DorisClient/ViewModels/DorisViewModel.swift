import Foundation
import MapKit
import UIKit
import AVFoundation

/// Message model for conversation history
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date

    init(text: String, isUser: Bool, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }

    /// Init with explicit ID (used when loading from database)
    init(id: UUID, text: String, isUser: Bool, timestamp: Date) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

@MainActor
class DorisViewModel: ObservableObject {
    @Published var state: DorisState = .idle
    @Published var audioPower: Double = 0.0
    @Published var lastResponse: String = ""
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var isProcessingText: Bool = false

    private let api = DorisAPIService()
    private let recorder = AudioRecorderService()
    private let speech = SpeechService()
    private let directions = DirectionsService()
    private lazy var toolExecutor = ClientToolExecutor(directions: directions)

    private let minimumThinkingTime: UInt64 = 2_000_000_000

    init() {
        loadRecentMessages()
        // Request location permission on first launch
        directions.requestLocationPermission()
    }

    // MARK: - Database Persistence

    /// Load recent messages from database into conversationHistory
    private func loadRecentMessages() {
        do {
            let dbMessages = try DatabaseManager.shared.fetchRecentMessages(limit: 50, offset: 0)
            // Messages come back newest-first, reverse to get chronological order
            conversationHistory = dbMessages.reversed().map { $0.toConversationMessage() }
        } catch {
            print("DorisViewModel: Failed to load messages from database: \(error)")
            conversationHistory = []
        }
    }

    /// Load earlier messages for pagination (prepends to conversationHistory)
    /// - Parameter offset: Number of messages already loaded
    /// - Returns: Number of new messages loaded
    func loadEarlierMessages(offset: Int) -> Int {
        do {
            let dbMessages = try DatabaseManager.shared.fetchRecentMessages(limit: 50, offset: offset)
            guard !dbMessages.isEmpty else { return 0 }
            // Messages come back newest-first, reverse to get chronological order
            let earlierMessages = dbMessages.reversed().map { $0.toConversationMessage() }
            conversationHistory.insert(contentsOf: earlierMessages, at: 0)
            return dbMessages.count
        } catch {
            print("DorisViewModel: Failed to load earlier messages: \(error)")
            return 0
        }
    }

    /// Save a message to the database
    private func saveMessage(_ message: ConversationMessage) {
        do {
            let dbMessage = Message(from: message)
            try DatabaseManager.shared.insertMessage(dbMessage)
        } catch {
            print("DorisViewModel: Failed to save message to database: \(error)")
        }
    }

    /// Search messages using FTS5
    func searchMessages(query: String) -> [ConversationMessage] {
        do {
            let dbMessages = try DatabaseManager.shared.searchMessages(query: query)
            return dbMessages.map { $0.toConversationMessage() }
        } catch {
            print("DorisViewModel: Search failed: \(error)")
            return []
        }
    }

    /// Convert conversation history to API format (last N messages for context)
    private func getHistoryForAPI(limit: Int = 10) -> [DorisAPIService.ChatMessage] {
        // Get last N messages, excluding the current one being sent
        let recentHistory = conversationHistory.suffix(limit)
        return recentHistory.map { msg in
            DorisAPIService.ChatMessage(
                role: msg.isUser ? "user" : "assistant",
                content: msg.text
            )
        }
    }

    func handleTap() {
        switch state {
        case .idle:
            startListening()
        case .listening:
            stopListening()
        case .speaking:
            stopSpeaking()
        default:
            break
        }
    }

    func startListening() {
        // Haptic feedback to acknowledge tap
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Play brief acknowledgment sound
        AudioServicesPlaySystemSound(1113)  // Short "begin recording" tone

        state = .listening
        lastResponse = "" // Clear previous response when starting new interaction

        recorder.start { [weak self] power, transcription in
            self?.audioPower = power
        } onSilenceDetected: { [weak self] finalText in
            self?.sendMessage(finalText)
        }
    }

    func stopListening() {
        recorder.stop()
        state = .idle
    }

    func sendMessage(_ text: String) {
        guard !text.isEmpty else {
            print("DorisViewModel: sendMessage called with empty text, returning to idle")
            state = .idle
            return
        }

        print("DorisViewModel: Setting state to .thinking")
        state = .thinking

        // Add user message to history and persist
        let userMessage = ConversationMessage(text: text, isUser: true, timestamp: Date())
        conversationHistory.append(userMessage)
        saveMessage(userMessage)

        Task {
            let startTime = DispatchTime.now()
            print("DorisViewModel: Starting API call")

            do {
                // Build client context with location
                let context = await buildClientContext()
                let history = getHistoryForAPI()

                // Initial request
                var request = DorisAPIService.ChatRequest(
                    message: text,
                    history: history.isEmpty ? nil : history,
                    client_context: context,
                    tool_result: nil
                )

                // Tool execution loop
                while true {
                    let response = try await api.chat(request: request)

                    // Check if server is requesting a tool execution
                    if let toolRequest = response.tool_request {
                        print("DorisViewModel: Server requested tool: \(toolRequest.tool_name)")

                        // Execute the tool locally
                        let toolResult = try await toolExecutor.execute(toolRequest)
                        print("DorisViewModel: Tool result status: \(toolResult.status)")

                        // Send tool result back to server (no message, just the result)
                        request = DorisAPIService.ChatRequest(
                            message: nil,
                            history: history.isEmpty ? nil : history,
                            client_context: context,
                            tool_result: toolResult
                        )
                        continue
                    }

                    // Final response - no more tool requests
                    let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
                    let serverLatency = response.latency_ms ?? Int(elapsed / 1_000_000)
                    print("DorisViewModel: API returned after \(serverLatency)ms (source: \(response.source ?? "unknown"))")

                    if elapsed < minimumThinkingTime {
                        let sleepTime = minimumThinkingTime - elapsed
                        print("DorisViewModel: Sleeping for \(sleepTime / 1_000_000)ms")
                        try await Task.sleep(nanoseconds: sleepTime)
                    }

                    // Store response and add to history
                    let responseText = response.response ?? ""
                    lastResponse = responseText

                    if !responseText.isEmpty {
                        let dorisMessage = ConversationMessage(text: responseText, isUser: false, timestamp: Date())
                        conversationHistory.append(dorisMessage)
                        saveMessage(dorisMessage)
                    }

                    // Release recorder's audio session before speaking
                    recorder.releaseAudioSession()

                    // Speak the response using local TTS
                    if !responseText.isEmpty {
                        print("DorisViewModel: Speaking response, setting state to .speaking")
                        state = .speaking

                        await speech.speak(responseText) { [weak self] power in
                            Task { @MainActor in
                                self?.audioPower = power
                            }
                        }
                    }

                    // Execute any actions from the response
                    if let actions = response.actions {
                        for action in actions {
                            await executeAction(action)
                        }
                    }

                    print("DorisViewModel: Response complete")
                    state = .idle
                    break
                }

            } catch {
                print("DorisViewModel: Error - \(error.localizedDescription)")
                state = .error(error.localizedDescription)

                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if case .error = self.state {
                        state = .idle
                    }
                }
            }
        }
    }

    // MARK: - Client Context & Actions

    /// Build client context with current location and capabilities
    private func buildClientContext() async -> DorisAPIService.ClientContext {
        var location: DorisAPIService.ClientLocation? = nil

        // Try to get current location
        if directions.hasLocationPermission {
            if let currentLocation = try? await directions.getCurrentLocation() {
                location = DorisAPIService.ClientLocation(
                    lat: currentLocation.coordinate.latitude,
                    lon: currentLocation.coordinate.longitude,
                    accuracy: currentLocation.horizontalAccuracy
                )
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return DorisAPIService.ClientContext(
            location: location,
            timestamp: formatter.string(from: Date()),
            capabilities: ["mapkit", "tts"],
            device: "iPhone"
        )
    }

    /// Execute an action returned by the server
    private func executeAction(_ action: DorisAPIService.ResponseAction) async {
        print("DorisViewModel: Executing action: \(action.type)")

        switch action.type {
        case "open_maps":
            if let params = action.parameters,
               let lat = params.lat,
               let lon = params.lon {
                // Build Apple Maps URL
                var components = URLComponents(string: "maps://")!
                var queryItems: [URLQueryItem] = [
                    URLQueryItem(name: "saddr", value: "Current Location"),
                    URLQueryItem(name: "daddr", value: "\(lat),\(lon)"),
                    URLQueryItem(name: "dirflg", value: "d")  // driving
                ]
                if let label = params.label {
                    // Add label as part of destination
                    queryItems[1] = URLQueryItem(name: "daddr", value: "\(lat),\(lon)")
                }
                components.queryItems = queryItems

                if let url = components.url {
                    print("DorisViewModel: Opening Maps URL: \(url)")
                    await UIApplication.shared.open(url)
                }
            }
        default:
            print("DorisViewModel: Unknown action type: \(action.type)")
        }
    }

    private func respondWithError(_ message: String) {
        Task {
            lastResponse = message
            let dorisMessage = ConversationMessage(text: message, isUser: false, timestamp: Date())
            conversationHistory.append(dorisMessage)
            saveMessage(dorisMessage)

            recorder.releaseAudioSession()
            state = .speaking

            await speech.speak(message) { [weak self] power in
                Task { @MainActor in
                    self?.audioPower = power
                }
            }

            state = .idle
        }
    }

    func stopSpeaking() {
        speech.stop()
        state = .idle
    }

    /// Send a text message without voice - response is text only (no TTS)
    func sendTextMessage(_ text: String) {
        guard !text.isEmpty else { return }
        guard !isProcessingText else { return }

        isProcessingText = true

        // Add user message to history immediately and persist
        let userMessage = ConversationMessage(text: text, isUser: true, timestamp: Date())
        conversationHistory.append(userMessage)
        saveMessage(userMessage)

        Task {
            do {
                // Build client context with location
                let context = await buildClientContext()
                let history = getHistoryForAPI()

                // Initial request
                var request = DorisAPIService.ChatRequest(
                    message: text,
                    history: history.isEmpty ? nil : history,
                    client_context: context,
                    tool_result: nil
                )

                // Tool execution loop (same as voice, but no TTS)
                while true {
                    let response = try await api.chat(request: request)

                    // Check if server is requesting a tool execution
                    if let toolRequest = response.tool_request {
                        print("DorisViewModel: Server requested tool: \(toolRequest.tool_name)")
                        let toolResult = try await toolExecutor.execute(toolRequest)
                        print("DorisViewModel: Tool result status: \(toolResult.status)")

                        request = DorisAPIService.ChatRequest(
                            message: nil,
                            history: history.isEmpty ? nil : history,
                            client_context: context,
                            tool_result: toolResult
                        )
                        continue
                    }

                    // Final response
                    let responseText = response.response ?? ""
                    lastResponse = responseText

                    if !responseText.isEmpty {
                        let dorisMessage = ConversationMessage(text: responseText, isUser: false, timestamp: Date())
                        conversationHistory.append(dorisMessage)
                        saveMessage(dorisMessage)
                    }

                    // Execute any actions from the response
                    if let actions = response.actions {
                        for action in actions {
                            await executeAction(action)
                        }
                    }

                    isProcessingText = false
                    break
                }

            } catch {
                print("DorisViewModel: Text message error - \(error.localizedDescription)")
                // Add error message to history and persist
                let errorMessage = ConversationMessage(text: "Sorry, I couldn't process that request.", isUser: false, timestamp: Date())
                conversationHistory.append(errorMessage)
                saveMessage(errorMessage)
                isProcessingText = false
            }
        }
    }

    func clearHistory() {
        conversationHistory = []
        lastResponse = ""
    }
}
