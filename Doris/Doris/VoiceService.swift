//
//  VoiceService.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation
import Speech
import AVFoundation
import Combine

class VoiceService: NSObject, ObservableObject {
    // Speech Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    // Text-to-Speech
    private let speechSynthesizer = AVSpeechSynthesizer() // Fallback
    private var audioPlayer: AVAudioPlayer?
    
    // ElevenLabs config
    private let elevenLabsApiKey: String?
    private let elevenLabsVoiceId = "kdmDKE6EkgrWrrykO9Qt" // Alexandra - realistic, chatty
    private let elevenLabsEndpoint = "https://api.elevenlabs.io/v1/text-to-speech"
    
    // State
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var transcribedText = ""
    
    // Completion handler for async listening
    private var completionHandler: ((Result<String, Error>) -> Void)?
    private var silenceTimer: Timer?
    
    override init() {
        // Check for ElevenLabs API key
        self.elevenLabsApiKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
        
        super.init()
        speechSynthesizer.delegate = self
        
        if elevenLabsApiKey != nil {
            print("🔊 Voice: ElevenLabs configured")
        } else {
            print("🔊 Voice: Using fallback speech synthesizer (set ELEVENLABS_API_KEY for better voice)")
        }
    }
    
    // MARK: - Permission Handling
    
    func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        let micAuth = await AVAudioApplication.requestRecordPermission()
        
        let granted = speechAuth && micAuth
        print(granted ? "🟢 Voice: All permissions granted" : "🔴 Voice: Permissions denied")
        return granted
    }
    
    func checkPermissions() -> Bool {
        let speechAuth = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micAuth = AVAudioApplication.shared.recordPermission == .granted
        return speechAuth && micAuth
    }
    
    // MARK: - Speech Recognition
    
    func startListening() async throws -> String {
        guard checkPermissions() else {
            throw VoiceError.permissionDenied
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceError.recognitionFailed
        }
        
        // Stop any existing session
        stopListening()
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            // Create fresh audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                continuation.resume(throwing: VoiceError.audioEngineError)
                return
            }
            
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                continuation.resume(throwing: VoiceError.recognitionFailed)
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false
            
            // Update state
            DispatchQueue.main.async {
                self.isListening = true
                self.transcribedText = ""
            }
            
            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("🔴 Voice: Recognition error: \(error.localizedDescription)")
                    if !hasResumed {
                        hasResumed = true
                        self.stopListening()
                        if self.transcribedText.isEmpty {
                            continuation.resume(throwing: VoiceError.recognitionFailed)
                        } else {
                            continuation.resume(returning: self.transcribedText)
                        }
                    }
                    return
                }
                
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    print("🎤 Voice: Heard: \(text)")
                    
                    DispatchQueue.main.async {
                        self.transcribedText = text
                    }
                    
                    // Reset silence timer on each new result
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                        if !hasResumed && !text.isEmpty {
                            hasResumed = true
                            self.stopListening()
                            continuation.resume(returning: text)
                        }
                    }
                    
                    if result.isFinal {
                        self.silenceTimer?.invalidate()
                        if !hasResumed {
                            hasResumed = true
                            self.stopListening()
                            continuation.resume(returning: text)
                        }
                    }
                }
            }
            
            // Setup audio
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            print("🎤 Voice: Format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")
            
            // Check format is valid
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("🔴 Voice: Invalid audio format")
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: VoiceError.audioEngineError)
                }
                return
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            
            do {
                try audioEngine.start()
                print("🟢 Voice: Listening...")
            } catch {
                print("🔴 Voice: Engine start failed: \(error)")
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: VoiceError.audioEngineError)
                }
            }
        }
    }
    
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.isListening = false
        }
        
        print("🔴 Voice: Stopped")
    }
    
    // MARK: - Text-to-Speech
    
    func speak(_ text: String) {
        // Stop any current playback
        stopSpeaking()
        
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        
        // Try ElevenLabs first if configured
        if let apiKey = elevenLabsApiKey, !apiKey.isEmpty {
            Task {
                do {
                    try await speakWithElevenLabs(text, apiKey: apiKey)
                } catch {
                    print("🔴 Voice: ElevenLabs failed: \(error.localizedDescription), falling back to system voice")
                    await MainActor.run {
                        self.speakWithSystemVoice(text)
                    }
                }
            }
        } else {
            speakWithSystemVoice(text)
        }
    }
    
    private func speakWithElevenLabs(_ text: String, apiKey: String) async throws {
        let url = URL(string: "\(elevenLabsEndpoint)/\(elevenLabsVoiceId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.3,
                "similarity_boost": 0.7,
                "style": 0.5,
                "use_speaker_boost": true
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🔊 Voice: Requesting ElevenLabs TTS...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceError.ttsError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🔴 Voice: ElevenLabs error \(httpResponse.statusCode): \(errorText)")
            throw VoiceError.ttsError("API error: \(httpResponse.statusCode)")
        }
        
        print("🔊 Voice: Got audio data (\(data.count) bytes)")
        
        // Play the audio on main thread
        await MainActor.run {
            do {
                self.audioPlayer = try AVAudioPlayer(data: data)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.play()
                print("🔊 Voice: Playing ElevenLabs audio")
            } catch {
                print("🔴 Voice: Failed to play audio: \(error)")
                self.isSpeaking = false
            }
        }
    }
    
    private func speakWithSystemVoice(_ text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        
        speechSynthesizer.speak(utterance)
        print("🔊 Voice: Playing system voice")
    }
    
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    // MARK: - Audio Data Generation

    func synthesizeToData(_ text: String) async throws -> Data {
        guard let apiKey = elevenLabsApiKey, !apiKey.isEmpty else {
            throw VoiceError.ttsError("ElevenLabs API key not configured")
        }

        let url = URL(string: "\(elevenLabsEndpoint)/\(elevenLabsVoiceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.3,
                "similarity_boost": 0.7,
                "style": 0.5,
                "use_speaker_boost": true
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VoiceError.ttsError("ElevenLabs API error")
        }

        return data
    }
}

extension VoiceService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

extension VoiceService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
        print("🔊 Voice: Finished playing")
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("🔴 Voice: Audio decode error: \(error?.localizedDescription ?? "unknown")")
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

enum VoiceError: LocalizedError {
    case permissionDenied
    case recognitionFailed
    case audioEngineError
    case ttsError(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone permission denied"
        case .recognitionFailed: return "Speech recognition failed"
        case .audioEngineError: return "Audio engine error"
        case .ttsError(let message): return "Text-to-speech error: \(message)"
        }
    }
}
