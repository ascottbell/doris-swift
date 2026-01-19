import AVFoundation
import Foundation

@MainActor
class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var powerCallback: ((Double) -> Void)?
    private var completionCallback: (() -> Void)?

    func play(_ audioData: Data, onPowerUpdate: @escaping (Double) -> Void, onComplete: @escaping () -> Void) {
        self.powerCallback = onPowerUpdate
        self.completionCallback = onComplete

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.isMeteringEnabled = true
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            startPowerMonitoring()
        } catch {
            print("Error playing audio: \(error)")
            completionCallback?()
        }
    }

    func stop() {
        audioPlayer?.stop()
        stopPowerMonitoring()
        completionCallback?()
        cleanup()
    }

    private func startPowerMonitoring() {
        // Use CADisplayLink for smooth updates on main thread
        displayLink = CADisplayLink(target: self, selector: #selector(updatePower))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func updatePower() {
        guard let player = audioPlayer, player.isPlaying else { return }
        
        player.updateMeters()
        let averagePower = player.averagePower(forChannel: 0)
        
        // Convert decibels to 0.0-1.0 range
        let normalizedPower = max(0.0, min(1.0, Double((averagePower + 50) / 50)))
        powerCallback?(normalizedPower)
    }

    private func stopPowerMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func cleanup() {
        audioPlayer = nil
        powerCallback = nil
        completionCallback = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPowerMonitoring()
            self.completionCallback?()
            self.cleanup()
        }
    }
}
