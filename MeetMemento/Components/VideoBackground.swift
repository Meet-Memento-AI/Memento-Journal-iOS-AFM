//
//  VideoBackground.swift
//  MeetMemento
//
//  Reusable video background with a seamless forward-only loop.
//
//  History: this used to also offer a "boomerang" ping-pong mode (forward,
//  then reverse in place, forever). Two attempts at that were tried and both
//  had to be reverted:
//   1. Building a reverse AVMutableComposition frame-by-frame — allocated
//      hundreds of segments and could jetsam the process (signal 9).
//   2. Native `rate = -1` reverse playback — H.264 is decode-unfriendly in
//      reverse, and zero-tolerance seeks on every direction flip produced a
//      steady stream of CoreMedia/Fig decode-pipeline errors, severe enough
//      on-device to stall the player and make the app appear stuck loading.
//  Forward-only via AVPlayerLooper has no reverse decode and is the only
//  approach that's actually been reliable.
//

import SwiftUI
import UIKit
import AVKit

struct VideoBackground: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    @Binding var isVideoReady: Bool
    @Binding var playbackProgress: Double

    init(
        videoName: String,
        videoExtension: String = "mp4",
        isVideoReady: Binding<Bool> = .constant(true),
        playbackProgress: Binding<Double> = .constant(0)
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self._isVideoReady = isVideoReady
        self._playbackProgress = playbackProgress
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(frame: .zero)
        view.videoName = videoName
        view.videoExtension = videoExtension
        view.isVideoReadyBinding = $isVideoReady
        view.playbackProgressBinding = $playbackProgress
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    var videoName: String = ""
    var videoExtension: String = "mp4"
    var isVideoReadyBinding: Binding<Bool>?
    var playbackProgressBinding: Binding<Double>?

    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var timeObserver: Any?
    private var durationSeconds: Double = 0
    private var didSetup = false
    private var lastPublishedProgress: Double = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
        guard !didSetup else { return }
        didSetup = true
        setupPlayer()
    }

    // NOTE on console noise: the bundled background videos are deliberately
    // VIDEO-ONLY (no audio track — the player is muted anyway). At setup,
    // CoreMedia logs one benign probe line for the absent audio track.
    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            AppLogger.log("⚠️ VideoBackground: Could not find \(videoName).\(videoExtension) in bundle")
            return
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        self.queuePlayer = queuePlayer

        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        attachLayer(player: queuePlayer)

        queuePlayer.isMuted = true
        queuePlayer.play()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration)
                self.durationSeconds = CMTimeGetSeconds(duration)
                self.setupTimeObserver(on: queuePlayer)
            } catch {
                AppLogger.log("⚠️ VideoBackground: Failed to load duration: \(error)")
            }
        }
    }

    private func attachLayer(player: AVPlayer) {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
    }

    private func setupTimeObserver(on player: AVPlayer) {
        if let timeObserver {
            self.queuePlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // 10 Hz is enough for blur ramp; 30 Hz was thrashing SwiftUI + blur.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }

            let current = CMTimeGetSeconds(time)
            guard current.isFinite, self.durationSeconds > 0 else { return }

            self.publishProgress(min(1.0, max(0.0, current / self.durationSeconds)))

            if self.isVideoReadyBinding?.wrappedValue == false {
                self.isVideoReadyBinding?.wrappedValue = true
            }
        }
    }

    private func publishProgress(_ progress: Double) {
        // Skip no-op / tiny updates so blur doesn't re-render every tick.
        guard abs(progress - lastPublishedProgress) >= 0.01 else { return }
        lastPublishedProgress = progress
        playbackProgressBinding?.wrappedValue = progress
    }

    private func teardownPlayback() {
        if let observer = timeObserver {
            queuePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        queuePlayer?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        playerLooper = nil
        queuePlayer = nil
    }

    deinit {
        teardownPlayback()
    }
}

// MARK: - Preview

#Preview {
    VideoBackground(videoName: "welcome-bg", videoExtension: "mp4")
        .ignoresSafeArea()
}
