import Foundation
import SwiftUI
import Combine

@MainActor
class DorisViewModel: ObservableObject {
    @Published var state: DorisState = .idle
    @Published var audioPower: Double = 0.0
    @Published var lastResponse: String = ""
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var wakeWordEnabled: Bool = false
    @Published var wakeWordActive: Bool = false
    @AppStorage("microphoneDisabled") var microphoneDisabled: Bool = false

    private let api = DorisAPIService()
    private let recorder = AudioRecorderService()
    private let player = AudioPlayerService()
    private let wakeWordService = WakeWordService()
    private let syncService = ConversationSyncService.shared

    private let minimumThinkingTime: UInt64 = 2_000_000_000
    private var syncObserver: NSObjectProtocol?

    init() {
        // Load history from iCloud
        conversationHistory = syncService.loadHistory()

        // Listen for external sync changes
        syncObserver = NotificationCenter.default.addObserver(
            forName: .conversationHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadHistoryFromCloud()
            }
        }

        // Request location permission on launch
        LocationService.shared.requestPermission()
    }

    deinit {
        if let observer = syncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Reload history when external change detected
    private func reloadHistoryFromCloud() {
        let cloudHistory = syncService.loadHistory()
        // Merge: keep newer messages
        if cloudHistory.count > conversationHistory.count {
            conversationHistory = cloudHistory
            print("DorisViewModel: Updated history from iCloud (\(cloudHistory.count) messages)")
        }
    }

    /// Save history to iCloud after changes
    private func saveHistoryToCloud() {
        syncService.saveHistory(conversationHistory)
    }

    // MARK: - Wake Word

    /// Enable "Hey Doris" wake word detection
    func enableWakeWord() {
        guard !wakeWordEnabled else { return }

        // Don't enable wake word if microphone is disabled
        guard !microphoneDisabled else {
            print("DorisViewModel: Cannot enable wake word - microphone disabled")
            return
        }

        wakeWordEnabled = true

        wakeWordService.start { [weak self] in
            print("DorisViewModel: Wake word detected!")
            self?.handleWakeWord()
        }

        print("DorisViewModel: Wake word detection enabled")
    }

    /// Disable wake word detection
    func disableWakeWord() {
        wakeWordEnabled = false
        wakeWordService.stop()
        print("DorisViewModel: Wake word detection disabled")
    }

    /// Called when wake word is detected
    private func handleWakeWord() {
        // Only respond if we're idle
        guard state == .idle else {
            print("DorisViewModel: Wake word ignored, not in idle state")
            return
        }

        wakeWordActive = true

        // Start listening for the actual command
        startListening()
    }

    /// Pause wake word while Doris is speaking (to avoid hearing herself)
    private func pauseWakeWord() {
        if wakeWordEnabled {
            wakeWordService.pause()
        }
    }

    /// Resume wake word after speaking
    private func resumeWakeWord() {
        if wakeWordEnabled {
            wakeWordService.resume()
        }
    }

    // MARK: - Interaction

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
        // Block listening if microphone is disabled
        guard !microphoneDisabled else {
            state = .error("Microphone disabled")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if case .error = self.state {
                    state = .idle
                }
            }
            return
        }

        state = .listening
        lastResponse = ""

        recorder.start { [weak self] power, transcription in
            self?.audioPower = power
        } onSilenceDetected: { [weak self] finalText in
            self?.sendVoiceMessage(finalText)
        }
    }

    func stopListening() {
        recorder.stop()
        state = .idle
    }

    // MARK: - Send Message (voice or text)

    /// Internal send with audio control
    private func sendMessage(_ text: String, withAudio: Bool) {
        guard !text.isEmpty else {
            print("DorisViewModel: sendMessage called with empty text, returning to idle")
            state = .idle
            return
        }

        print("DorisViewModel: Setting state to .thinking (withAudio: \(withAudio))")
        state = .thinking

        let userMessage = ConversationMessage(text: text, isUser: true, timestamp: Date())
        conversationHistory.append(userMessage)

        Task {
            let startTime = DispatchTime.now()
            print("DorisViewModel: Starting API call")

            do {
                let response = try await api.chat(message: text, includeAudio: withAudio)

                let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
                print("DorisViewModel: API returned after \(elapsed / 1_000_000)ms")

                if elapsed < minimumThinkingTime {
                    let sleepTime = minimumThinkingTime - elapsed
                    print("DorisViewModel: Sleeping for \(sleepTime / 1_000_000)ms")
                    try await Task.sleep(nanoseconds: sleepTime)
                }

                lastResponse = response.text
                let dorisMessage = ConversationMessage(text: response.text, isUser: false, timestamp: Date())
                conversationHistory.append(dorisMessage)

                // Sync to iCloud
                saveHistoryToCloud()

                if withAudio, let audioData = response.audioData, !audioData.isEmpty {
                    print("DorisViewModel: Playing audio, setting state to .speaking")
                    state = .speaking

                    // Pause wake word so Doris doesn't hear herself
                    pauseWakeWord()

                    player.play(audioData) { [weak self] power in
                        self?.audioPower = power
                    } onComplete: { [weak self] in
                        print("DorisViewModel: Audio complete")
                        self?.state = .idle
                        self?.wakeWordActive = false

                        // Resume wake word after speaking
                        self?.resumeWakeWord()
                    }
                } else {
                    print("DorisViewModel: Text-only response (no audio)")
                    state = .idle
                    wakeWordActive = false
                    resumeWakeWord()
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

    /// Send voice message (will speak response)
    func sendVoiceMessage(_ text: String) {
        sendMessage(text, withAudio: true)
    }

    /// Send text message (text-only response, no TTS)
    func sendTextMessage(_ text: String) {
        sendMessage(text, withAudio: false)
    }

    func stopSpeaking() {
        player.stop()
        state = .idle
    }

    func clearHistory() {
        conversationHistory = []
        lastResponse = ""
        syncService.clearHistory()
    }

    /// Search messages in conversation history (in-memory filter)
    func searchMessages(query: String) -> [ConversationMessage] {
        guard !query.isEmpty else { return [] }
        let lowercasedQuery = query.lowercased()
        return conversationHistory.filter { message in
            message.text.lowercased().contains(lowercasedQuery)
        }
    }

    // MARK: - Microphone Control

    /// Set microphone disabled state with side effects
    func setMicrophoneDisabled(_ disabled: Bool) {
        microphoneDisabled = disabled

        if disabled {
            // Stop any active listening
            if state == .listening {
                stopListening()
            }
            // Disable wake word when mic is disabled
            if wakeWordEnabled {
                disableWakeWord()
            }
            print("DorisViewModel: Microphone disabled")
        } else {
            print("DorisViewModel: Microphone enabled")
        }
    }
}
