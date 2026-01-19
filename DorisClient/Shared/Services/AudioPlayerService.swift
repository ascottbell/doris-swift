import AVFoundation
import Foundation
import Combine

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var powerCallback: ((Double) -> Void)?
    private var completionCallback: (() -> Void)?

    #if os(iOS)
    private var displayLink: CADisplayLink?
    #elseif os(macOS)
    private var displayTimer: Timer?
    #endif

    func play(_ audioData: Data, onPowerUpdate: @escaping (Double) -> Void, onComplete: @escaping () -> Void) {
        self.powerCallback = onPowerUpdate
        self.completionCallback = onComplete

        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif

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

    // MARK: - Power Monitoring (Platform-specific)

    private func startPowerMonitoring() {
        #if os(iOS)
        displayLink = CADisplayLink(target: self, selector: #selector(updatePower))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        displayLink?.add(to: .main, forMode: .common)
        #elseif os(macOS)
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePower()
            }
        }
        #endif
    }

    @objc private func updatePower() {
        guard let player = audioPlayer, player.isPlaying else { return }

        player.updateMeters()
        let averagePower = player.averagePower(forChannel: 0)

        let normalizedPower = max(0.0, min(1.0, Double((averagePower + 50) / 50)))
        powerCallback?(normalizedPower)
    }

    private func stopPowerMonitoring() {
        #if os(iOS)
        displayLink?.invalidate()
        displayLink = nil
        #elseif os(macOS)
        displayTimer?.invalidate()
        displayTimer = nil
        #endif
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
