import Foundation
import AVFoundation
import Observation

/// Plays back recorded audio with scrubbing (PRD §4.3.2 "可回放、拖动进度").
@MainActor
@Observable
final class AudioPlayerService: NSObject {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var loadedPath: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let mediaStore: MediaStore

    init(mediaStore: MediaStore = .shared) {
        self.mediaStore = mediaStore
        super.init()
    }

    func toggle(relativePath: String) {
        if loadedPath == relativePath, isPlaying {
            pause()
        } else {
            play(relativePath: relativePath)
        }
    }

    func play(relativePath: String) {
        if loadedPath != relativePath {
            load(relativePath: relativePath)
        }
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        timer?.invalidate()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }

    private func load(relativePath: String) {
        stop()
        let url = mediaStore.absoluteURL(for: relativePath)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.prepareToPlay()
        player = p
        loadedPath = relativePath
        duration = p.duration
        currentTime = 0
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
        }
    }
}
