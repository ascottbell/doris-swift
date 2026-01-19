import AVFoundation
import Speech
import Foundation
import Combine

#if os(macOS)
import AppKit
#endif

/// Continuously listens for "Hey Doris" wake word
/// When detected, triggers a callback to activate the main listening mode
@MainActor
class WakeWordService: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var lastDetectedPhrase: String = ""

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var wakeWordCallback: (() -> Void)?
    private var restartTimer: Timer?

    // Wake word variations to detect
    private let wakeWords = [
        "hey doris",
        "hey dorius",
        "hey doors",
        "hey dorice",
        "a doris",
        "hey doris",
        "hi doris",
        "ok doris",
        "okay doris"
    ]

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Start listening for wake word
    func start(onWakeWord: @escaping () -> Void) {
        self.wakeWordCallback = onWakeWord

        requestPermissions { [weak self] granted in
            guard granted else {
                print("WakeWordService: Permissions not granted")
                return
            }

            Task { @MainActor in
                self?.startListening()
            }
        }
    }

    /// Stop listening for wake word
    func stop() {
        stopListening()
        restartTimer?.invalidate()
        restartTimer = nil
        wakeWordCallback = nil
    }

    /// Temporarily pause wake word detection (e.g., while Doris is speaking)
    func pause() {
        stopListening()
    }

    /// Resume wake word detection
    func resume() {
        if wakeWordCallback != nil {
            startListening()
        }
    }

    // MARK: - Permission Handling

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.requestMicrophonePermission(completion: completion)
                default:
                    completion(false)
                }
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
        #endif
    }

    // MARK: - Listening

    private func startListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("WakeWordService: Speech recognizer not available")
            scheduleRestart()
            return
        }

        guard !isListening else { return }

        do {
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }

            // Configure for continuous recognition
            recognitionRequest.shouldReportPartialResults = true

            // Use on-device recognition if available (lower latency, more privacy)
            if #available(macOS 13.0, iOS 16.0, *) {
                recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            print("WakeWordService: Started listening for wake word")

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcription = result.bestTranscription.formattedString.lowercased()
                    self.lastDetectedPhrase = transcription

                    // Check for wake word
                    for wakeWord in self.wakeWords {
                        if transcription.contains(wakeWord) {
                            print("WakeWordService: Wake word detected! '\(wakeWord)' in '\(transcription)'")

                            Task { @MainActor in
                                // Stop listening temporarily
                                self.stopListening()

                                // Trigger callback
                                self.wakeWordCallback?()

                                // Resume listening after a delay (let the main interaction finish)
                                self.scheduleRestart(delay: 10.0)
                            }
                            return
                        }
                    }
                }

                if let error = error {
                    let nsError = error as NSError

                    // Handle expected errors gracefully
                    let recoverableCodes = [203, 216, 301, 1110, 1700]

                    if recoverableCodes.contains(nsError.code) {
                        print("WakeWordService: Recognition ended (code \(nsError.code)), restarting...")
                    } else {
                        print("WakeWordService: Error (code \(nsError.code)): \(error.localizedDescription)")
                    }

                    Task { @MainActor in
                        self.stopListening()
                        self.scheduleRestart()
                    }
                }
            }

        } catch {
            print("WakeWordService: Error starting: \(error)")
            scheduleRestart()
        }
    }

    private func stopListening() {
        isListening = false

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        print("WakeWordService: Stopped listening")
    }

    private func scheduleRestart(delay: TimeInterval = 1.0) {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startListening()
            }
        }
    }
}
