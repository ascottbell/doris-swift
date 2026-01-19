import Foundation
import AVFoundation

class SpeechService: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var speakingContinuation: CheckedContinuation<Void, Never>?
    private var powerCallback: ((Double) -> Void)?
    private let apiService = DorisAPIService()

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            print("SpeechService: Audio session configured for playback")
        } catch {
            print("SpeechService: Failed to configure audio session: \(error)")
        }
    }

    /// Find the best available voice (Zoe Premium preferred, Samantha fallback)
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        print("SpeechService: Looking for Zoe...")
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Try Zoe Premium by identifier
        if let zoe = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") {
            print("SpeechService: Using voice: \(zoe.name) (\(zoe.identifier))")
            return zoe
        }

        // Try finding Zoe by name (handles different quality levels)
        if let zoe = voices.first(where: { $0.name.contains("Zoe") && $0.language.starts(with: "en") }) {
            print("SpeechService: Using voice: \(zoe.name) (\(zoe.identifier))")
            return zoe
        }

        // Fallback to Samantha Premium
        if let samantha = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Samantha") {
            print("SpeechService: Using voice: \(samantha.name) (\(samantha.identifier))")
            return samantha
        }

        // Fallback to any Samantha
        if let samantha = voices.first(where: { $0.name.contains("Samantha") && $0.language.starts(with: "en") }) {
            print("SpeechService: Using voice: \(samantha.name) (\(samantha.identifier))")
            return samantha
        }

        // Final fallback to default English voice
        let fallback = AVSpeechSynthesisVoice(language: "en-US")
        print("SpeechService: Using fallback voice: \(fallback?.name ?? "nil") (\(fallback?.identifier ?? "nil"))")
        return fallback
    }

    /// Speak text asynchronously, returning when speech completes
    /// Uses server TTS (Supertonic) with fallback to local AVSpeechSynthesizer
    func speak(_ text: String, onPowerUpdate: ((Double) -> Void)? = nil) async {
        print("SpeechService: Speaking text: \(text.prefix(50))...")

        // Stop any current speech
        stop()

        // Reconfigure audio session for playback (recorder may have changed it)
        configureAudioSession()

        // Small delay to let audio system settle after switching from recording
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        powerCallback = onPowerUpdate

        // Try server TTS first (Mac Mini with Supertonic - best quality)
        do {
            print("SpeechService: Requesting server TTS...")
            let audioData = try await apiService.synthesizeSpeech(text: text)
            print("SpeechService: Got \(audioData.count) bytes from server")

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                speakingContinuation = continuation

                do {
                    audioPlayer = try AVAudioPlayer(data: audioData)
                    audioPlayer?.delegate = self
                    audioPlayer?.play()
                    print("SpeechService: Playing server TTS audio")
                } catch {
                    print("SpeechService: Failed to play audio: \(error)")
                    speakingContinuation = nil
                    continuation.resume()
                }
            }
        } catch {
            // Fallback to local AVSpeechSynthesizer
            print("SpeechService: Server TTS failed (\(error.localizedDescription)), using local voice")
            await speakWithLocalVoice(text)
        }

        powerCallback = nil
    }

    /// Fallback to local AVSpeechSynthesizer
    private func speakWithLocalVoice(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        print("SpeechService: Voice is \(utterance.voice?.name ?? "nil")")
        print("SpeechService: Starting local speech synthesis")

        await withCheckedContinuation { continuation in
            speakingContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    /// Stop speaking immediately
    func stop() {
        // Stop audio player if playing
        audioPlayer?.stop()
        audioPlayer = nil

        // Stop synthesizer if speaking
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Resume continuation if waiting
        if let continuation = speakingContinuation {
            speakingContinuation = nil
            continuation.resume()
        }
    }

    /// Check if currently speaking
    var isSpeaking: Bool {
        synthesizer.isSpeaking || (audioPlayer?.isPlaying ?? false)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("SpeechService: Speech started")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("SpeechService: Speech finished")
        if let continuation = speakingContinuation {
            speakingContinuation = nil
            continuation.resume()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("SpeechService: Speech cancelled")
        if let continuation = speakingContinuation {
            speakingContinuation = nil
            continuation.resume()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Simulate power levels based on speaking progress
        let progress = Double(characterRange.location) / Double(utterance.speechString.count)
        let simulatedPower = 0.5 + sin(progress * .pi * 4) * 0.3
        powerCallback?(simulatedPower)
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("SpeechService: Audio player finished (success: \(flag))")
        audioPlayer = nil
        if let continuation = speakingContinuation {
            speakingContinuation = nil
            continuation.resume()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("SpeechService: Audio decode error: \(error?.localizedDescription ?? "unknown")")
        audioPlayer = nil
        if let continuation = speakingContinuation {
            speakingContinuation = nil
            continuation.resume()
        }
    }
}
