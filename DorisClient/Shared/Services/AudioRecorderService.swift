import AVFoundation
import Speech
import Foundation
import Combine

#if os(macOS)
import AppKit
#endif

@MainActor
class AudioRecorderService: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private var noSpeechTimer: Timer?
    private var maxRecordingTimer: Timer?
    private var lastTranscriptionTime: Date?
    private var hasReceivedSpeech: Bool = false
    private var hasSentFinalResult: Bool = false
    private var hasDetectedAudioActivity: Bool = false

    private var powerCallback: ((Double, String?) -> Void)?
    private var silenceCallback: ((String) -> Void)?
    private var currentTranscription: String = ""

    private let silenceThreshold: TimeInterval = 2.5  // Wait longer for natural pauses
    private let noSpeechTimeout: TimeInterval = 5.0  // Give up if no transcription after audio activity
    private let maxRecordingDuration: TimeInterval = 30.0  // Maximum recording time
    private let audioActivityThreshold: Double = 0.15  // Power level to consider as audio activity

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start(onUpdate: @escaping (Double, String?) -> Void, onSilenceDetected: @escaping (String) -> Void) {
        self.powerCallback = onUpdate
        self.silenceCallback = onSilenceDetected
        self.currentTranscription = ""
        self.hasReceivedSpeech = false
        self.hasSentFinalResult = false
        self.hasDetectedAudioActivity = false

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

    // MARK: - Platform-specific permission handling

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else {
                    completion(false)
                    return
                }
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

    // MARK: - Recording

    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("AudioRecorderService: Speech recognizer not available")
            return
        }

        do {
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            #elseif os(macOS)
            // Check if there's actually an audio input device available
            guard AVCaptureDevice.default(for: .audio) != nil else {
                print("AudioRecorderService: No microphone available")
                silenceCallback?("")
                return
            }
            #endif

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

            // Start max recording timer as a failsafe
            startMaxRecordingTimer()

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcription = result.bestTranscription.formattedString
                    self.currentTranscription = transcription
                    self.lastTranscriptionTime = Date()

                    if !self.hasReceivedSpeech && !transcription.isEmpty {
                        self.hasReceivedSpeech = true
                        self.cancelNoSpeechTimer()  // Got speech, cancel the timeout
                        print("AudioRecorderService: First speech detected")
                    }

                    Task { @MainActor in
                        self.powerCallback?(0.0, transcription)
                    }

                    if self.hasReceivedSpeech {
                        self.resetSilenceTimer()
                    }

                    if result.isFinal {
                        print("AudioRecorderService: Got final result from recognizer")
                        Task { @MainActor in
                            self.stopRecording()
                            self.sendFinalTranscription()
                        }
                    }
                }

                if let error = error {
                    let nsError = error as NSError
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
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil

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
    }

    private func updateAudioPower(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)

        let normalizedPower = max(0.0, min(1.0, Double((avgPower + 50) / 50)))

        Task { @MainActor in
            self.powerCallback?(normalizedPower, nil)

            // Start no-speech timer only after we detect audio activity
            if !self.hasDetectedAudioActivity && normalizedPower > self.audioActivityThreshold {
                self.hasDetectedAudioActivity = true
                print("AudioRecorderService: Audio activity detected (power: \(normalizedPower))")
                self.startNoSpeechTimer()
            }
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

    private func startNoSpeechTimer() {
        noSpeechTimer?.invalidate()

        noSpeechTimer = Timer.scheduledTimer(withTimeInterval: noSpeechTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                if !self.hasReceivedSpeech {
                    print("AudioRecorderService: No speech timeout - giving up")
                    self.stopRecording()
                    // Don't send anything - just return to idle
                    self.silenceCallback?("")
                }
            }
        }
    }

    private func cancelNoSpeechTimer() {
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil
    }

    private func startMaxRecordingTimer() {
        maxRecordingTimer?.invalidate()

        maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                print("AudioRecorderService: Max recording duration reached")
                self.stopRecording()
                self.sendFinalTranscription()
            }
        }
    }
}
