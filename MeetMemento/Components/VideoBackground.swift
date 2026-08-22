//
//  VideoBackground.swift
//  MeetMemento
//
//  Reusable video background with an in-place ping-pong loop: play forward,
//  then reverse, forever. Direction flips by setting `AVPlayer.rate` to 1 or
//  -1 at the clip ends — no seek on a healthy flip.
//
//  Earlier attempts that were reverted:
//   1. Reverse `AVMutableComposition` frame-by-frame — too many segments,
//      jetsam (signal 9).
//   2. `rate = -1` plus zero-tolerance seeks on every flip — H.264 reverse
//      decode errors that stalled the player so Welcome looked stuck loading.
//
//  This pass never seeks with `.zero` tolerance. If reverse stalls (item
//  error, rate stuck at 0, or waiting-to-play too long after a flip), we
//  fall back to forward-only wrap so the launch overlay cannot hang.
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
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var durationSeconds: Double = 0
    private var didSetup = false
    private var lastPublishedProgress: Double = -1

    /// Flip before the last/first frame so we do not rely on play-to-end.
    private let edgeEpsilon: Double = 0.05
    /// Waiting-to-play / rate-0 longer than this after a flip → forward-only.
    private let stallTimeout: TimeInterval = 1.5

    private var isPingPongEnabled = true
    private var isReversing = false
    private var hasStartedPlaying = false
    private var isWrappingToStart = false
    private var stallStartedAt: Date?

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
        item.audioTimePitchAlgorithm = .spectral

        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.isMuted = true
        self.player = player

        attachLayer(player: player)
        observeItemEnd(item)
        observeItemFailure(item)
        player.play()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration)
                self.durationSeconds = CMTimeGetSeconds(duration)
                self.setupTimeObserver(on: player)
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

    private func observeItemEnd(_ item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlayedToEnd()
        }
    }

    private func observeItemFailure(_ item: AVPlayerItem) {
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.fallBackToForwardLoop()
        }
    }

    private func setupTimeObserver(on player: AVPlayer) {
        if let timeObserver {
            self.player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // 10 Hz is enough for blur ramp and edge flips; 30 Hz was thrashing
        // SwiftUI + blur.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }

            let current = CMTimeGetSeconds(time)
            guard current.isFinite, self.durationSeconds > 0 else { return }

            self.publishProgress(min(1.0, max(0.0, current / self.durationSeconds)))

            if self.isVideoReadyBinding?.wrappedValue == false {
                self.isVideoReadyBinding?.wrappedValue = true
            }

            self.flipIfNeeded(at: current)
            if abs(player.rate) > 0.01 {
                self.hasStartedPlaying = true
            }
            self.checkStall()
        }
    }

    private func flipIfNeeded(at current: Double) {
        guard let player else { return }

        if isPingPongEnabled {
            if !isReversing, current >= durationSeconds - edgeEpsilon {
                isReversing = true
                stallStartedAt = nil
                player.rate = -1
            } else if isReversing, current <= edgeEpsilon {
                isReversing = false
                stallStartedAt = nil
                player.rate = 1
            }
            return
        }

        if current >= durationSeconds - edgeEpsilon {
            wrapForwardToStart()
        }
    }

    private func handlePlayedToEnd() {
        guard let player else { return }

        if !isPingPongEnabled {
            wrapForwardToStart()
            return
        }

        isReversing = true
        stallStartedAt = nil
        player.rate = -1

        // Item is already at the last sample; rate -1 can no-op. Nudge off
        // the end with infinite tolerance — never `.zero`.
        if abs(player.rate) < 0.01 {
            let nudge = max(0, durationSeconds - edgeEpsilon)
            let time = CMTime(seconds: nudge, preferredTimescale: 600)
            player.seek(
                to: time,
                toleranceBefore: .positiveInfinity,
                toleranceAfter: .positiveInfinity
            ) { [weak self] finished in
                guard finished, let self, self.isPingPongEnabled else { return }
                self.player?.rate = -1
            }
        }
    }

    private func checkStall() {
        guard isPingPongEnabled, hasStartedPlaying, let player else { return }

        if player.currentItem?.status == .failed {
            fallBackToForwardLoop()
            return
        }

        // Rate can be 0 for a tick at a flip; only waiting-to-play is a stall.
        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            if stallStartedAt == nil {
                stallStartedAt = Date()
            } else if let started = stallStartedAt,
                      Date().timeIntervalSince(started) >= stallTimeout {
                fallBackToForwardLoop()
            }
        } else {
            stallStartedAt = nil
        }
    }

    private func fallBackToForwardLoop() {
        guard isPingPongEnabled else { return }
        isPingPongEnabled = false
        isReversing = false
        stallStartedAt = nil
        AppLogger.log("⚠️ VideoBackground: reverse stalled — falling back to forward loop")
        wrapForwardToStart()
    }

    private func wrapForwardToStart() {
        guard let player, !isWrappingToStart else { return }
        isWrappingToStart = true
        player.seek(
            to: .zero,
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .positiveInfinity
        ) { [weak self] finished in
            guard let self else { return }
            self.isWrappingToStart = false
            guard finished else { return }
            self.player?.rate = 1
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
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
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
