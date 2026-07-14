//
//  VideoBackground.swift
//  MeetMemento
//
//  Reusable video background component with seamless looping.
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

class PlayerUIView: UIView {
    var videoName: String = ""
    var videoExtension: String = "mp4"
    var isVideoReadyBinding: Binding<Bool>?
    var playbackProgressBinding: Binding<Double>?

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

    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var timeObserver: Any?
    private var videoDuration: Double = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds

        if queuePlayer == nil {
            setupPlayer()
        }
    }

    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
                        AppLogger.log("⚠️ VideoBackground: Could not find \(videoName).\(videoExtension) in bundle")
            return
        }

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        self.queuePlayer = queuePlayer

        // Create looper for seamless loop
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        // Setup layer
        let playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer

        // Mute and play
        queuePlayer.isMuted = true
        queuePlayer.play()

        // Get video duration and setup progress tracking
        Task { @MainActor in
            do {
                let duration = try await asset.load(.duration)
                self.videoDuration = CMTimeGetSeconds(duration)
                self.setupTimeObserver()
            } catch {
                                AppLogger.log("⚠️ VideoBackground: Failed to load duration: \(error)")
            }
        }
    }

    private func setupTimeObserver() {
        guard let player = queuePlayer, videoDuration > 0 else { return }

        // Update progress ~8 times per second (sufficient for blur animation)
        let interval = CMTime(seconds: 1.0 / 8.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            let currentTime = CMTimeGetSeconds(time)
            let progress = min(1.0, max(0.0, currentTime / self.videoDuration))

            // Update progress binding
            self.playbackProgressBinding?.wrappedValue = progress

            // Mark video as ready on first progress update
            if self.isVideoReadyBinding?.wrappedValue == false {
                self.isVideoReadyBinding?.wrappedValue = true
            }
        }
    }

    deinit {
        if let observer = timeObserver {
            queuePlayer?.removeTimeObserver(observer)
        }
        queuePlayer?.pause()
        queuePlayer = nil
        playerLooper = nil
    }
}

// MARK: - Preview

#Preview {
    VideoBackground(videoName: "welcome-bg", videoExtension: "mp4")
        .ignoresSafeArea()
}
