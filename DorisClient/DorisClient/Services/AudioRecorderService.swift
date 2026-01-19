import AVFoundation
import Speech
import Foundation

@MainActor
class AudioRecorderService: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private var lastTranscriptionTime: Date?
    private var hasReceivedSpeech: Bool = false
    private var hasSentFinalResult: Bool = false  // Prevent double-send

    private var powerCallback: ((Double, String?) -> Void)?
    private var silenceCallback: ((String) -> Void)?
    private var currentTranscription: String = ""

    private let silenceThreshold: TimeInterval = 1.5

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start(onUpdate: @escaping (Double, String?) -> Void, onSilenceDetected: @escaping (String) -> Void) {
        self.powerCallback = onUpdate
        self.silenceCallback = onSilenceDetected
        self.currentTranscription = ""
        self.hasReceivedSpeech = false
        self.hasSentFinalResult = false  // Reset flag

        requestPermissions { [weak self] granted in
            guard granted else {
                print("AudioRecorderService: Permissions not granted")
                return
            }

            Task { @MainActor in
                self?.startRecording()
            }
        }
    }

    func stop() {
        stopRecording()
    }
    
    /// Send the final transcription exactly once
    private func sendFinalTranscription() {
        guard !hasSentFinalResult else {
            print("AudioRecorderService: Already sent final result, ignoring")
            return
        }
        
        let finalText = currentTranscription
        guard !finalText.isEmpty else {
            print("AudioRecorderService: Final text is empty, not sending")
            return
        }
        
        hasSentFinalResult = true
        print("AudioRecorderService: Sending final transcription: '\(finalText)'")
        silenceCallback?(finalText)
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        completion(granted)
                    }
                default:
                    completion(false)
                }
            }
        }
    }

    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("AudioRecorderService: Speech recognizer not available")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }

            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                self?.updateAudioPower(buffer: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            
            print("AudioRecorderService: Recording started")

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcription = result.bestTranscription.formattedString
                    self.currentTranscription = transcription
                    self.lastTranscriptionTime = Date()
                    
                    // First speech detected - start watching for silence
                    if !self.hasReceivedSpeech && !transcription.isEmpty {
                        self.hasReceivedSpeech = true
                        print("AudioRecorderService: First speech detected")
                    }

                    Task { @MainActor in
                        self.powerCallback?(0.0, transcription)
                    }

                    // Only start silence timer after we've received speech
                    if self.hasReceivedSpeech {
                        self.resetSilenceTimer()
                    }
                    
                    // If this is the final result from the recognizer, we're done
                    if result.isFinal {
                        print("AudioRecorderService: Got final result from recognizer")
                        Task { @MainActor in
                            self.stopRecording()
                            self.sendFinalTranscription()
                        }
                    }
                }

                // Handle errors - but ignore cancellation errors since we cause those
                if let error = error {
                    let nsError = error as NSError
                    // Ignore these expected errors:
                    // 203 = "No speech detected"
                    // 216 = "Request was canceled" (old code)
                    // 301 = "Recognition request was canceled" (current code)
                    // 1110 = "Session ended" (normal termination)
                    let ignoredCodes = [203, 216, 301, 1110]
                    
                    if !ignoredCodes.contains(nsError.code) {
                        print("AudioRecorderService: Recognition error (code \(nsError.code)): \(error)")
                        Task { @MainActor in
                            self.stopRecording()
                            self.sendFinalTranscription()
                        }
                    } else {
                        print("AudioRecorderService: Ignoring expected error code \(nsError.code)")
                    }
                }
            }

        } catch {
            print("AudioRecorderService: Error starting recording: \(error)")
        }
    }

    private func stopRecording() {
        print("AudioRecorderService: Stopping recording")

        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        // Release audio session so other services can use it
        releaseAudioSession()
    }

    /// Release the audio session so other services (like TTS) can use it
    func releaseAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            print("AudioRecorderService: Audio session released")
        } catch {
            print("AudioRecorderService: Failed to release audio session: \(error)")
        }
    }

    private func updateAudioPower(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)

        // Normalize to 0.0 - 1.0 range
        // -50 dB = silence, 0 dB = loud
        let normalizedPower = max(0.0, min(1.0, Double((avgPower + 50) / 50)))

        Task { @MainActor in
            self.powerCallback?(normalizedPower, nil)
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()

        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                print("AudioRecorderService: Silence detected")
                self.stopRecording()
                self.sendFinalTranscription()
            }
        }
    }
}
