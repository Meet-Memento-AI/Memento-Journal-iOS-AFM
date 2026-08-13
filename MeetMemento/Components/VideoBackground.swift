//
//  VideoBackground.swift
//  MeetMemento
//
//  Reusable video background: forward loop, or a smooth ping-pong loop
//  (full forward pass, then full reverse pass) built as one composition so
//  decode always runs forward — no AVPlayer rate = -1 (avoids H.264 hitch).
//

import SwiftUI
import UIKit
import AVKit

enum VideoPlaybackLoopMode {
    /// Forward-only seamless loop via AVPlayerLooper (default).
    case forwardLoop
    /// One composition = [full forward][full reverse], looped continuously.
    /// First forward half still drives blur progress; then blur locks.
    case boomerangAfterFirstPass
}

/// Shared welcome-video styling so Welcome and the onboarding completion
/// screen settle on the same look (same asset + settled layer blur).
enum WelcomeVideoBackgroundStyle {
    static let videoName = "welcome-bg"
    static let videoExtension = "mp4"
    /// Figma-equivalent layer blur once the intro ramp (or skip-intro) settles.
    static let settledBlurRadius: CGFloat = 50
}

struct VideoBackground: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    let loopMode: VideoPlaybackLoopMode
    @Binding var isVideoReady: Bool
    @Binding var playbackProgress: Double
    @Binding var hasCompletedFirstPass: Bool
    /// When true (skip-intro / UITest), lock blur immediately; ping-pong still plays.
    var startInBoomerang: Bool

    init(
        videoName: String,
        videoExtension: String = "mp4",
        loopMode: VideoPlaybackLoopMode = .forwardLoop,
        isVideoReady: Binding<Bool> = .constant(true),
        playbackProgress: Binding<Double> = .constant(0),
        hasCompletedFirstPass: Binding<Bool> = .constant(false),
        startInBoomerang: Bool = false
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.loopMode = loopMode
        self._isVideoReady = isVideoReady
        self._playbackProgress = playbackProgress
        self._hasCompletedFirstPass = hasCompletedFirstPass
        self.startInBoomerang = startInBoomerang
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(frame: .zero)
        view.videoName = videoName
        view.videoExtension = videoExtension
        view.loopMode = loopMode
        view.isVideoReadyBinding = $isVideoReady
        view.playbackProgressBinding = $playbackProgress
        view.hasCompletedFirstPassBinding = $hasCompletedFirstPass
        view.startInBoomerang = startInBoomerang
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if startInBoomerang || hasCompletedFirstPass {
            uiView.markFirstPassComplete()
        }
    }
}

class PlayerUIView: UIView {
    var videoName: String = ""
    var videoExtension: String = "mp4"
    var loopMode: VideoPlaybackLoopMode = .forwardLoop
    var startInBoomerang: Bool = false
    var isVideoReadyBinding: Binding<Bool>?
    var playbackProgressBinding: Binding<Double>?
    var hasCompletedFirstPassBinding: Binding<Bool>?

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
    /// Duration of one forward (or reverse) half in seconds.
    private var halfDuration: Double = 0
    private var didMarkFirstPass = false

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds

        if queuePlayer == nil {
            setupPlayer()
        }
    }

    // NOTE on console noise: the bundled background videos are deliberately
    // VIDEO-ONLY (no audio track — the player is muted anyway). At setup,
    // CoreMedia logs one benign probe line for the absent audio track.
    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            AppLogger.log("⚠️ VideoBackground: Could not find \(videoName).\(videoExtension) in bundle")
            return
        }

        switch loopMode {
        case .forwardLoop:
            setupForwardLoopPlayer(url: url)
        case .boomerangAfterFirstPass:
            setupPingPongPlayer(url: url)
        }
    }

    private func setupForwardLoopPlayer(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        self.queuePlayer = queuePlayer

        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        attachLayer(player: queuePlayer)

        queuePlayer.isMuted = true
        queuePlayer.play()

        Task { @MainActor in
            do {
                let duration = try await asset.load(.duration)
                self.halfDuration = CMTimeGetSeconds(duration)
                self.setupTimeObserver()
            } catch {
                AppLogger.log("⚠️ VideoBackground: Failed to load duration: \(error)")
            }
        }
    }

    /// Builds [forward][reverse] as one asset and loops it with AVPlayerLooper.
    /// Decode is always forward, so turnarounds stay smooth on H.264.
    private func setupPingPongPlayer(url: URL) {
        // Placeholder player so layoutSubviews doesn't re-enter setup while we compose.
        let placeholder = AVQueuePlayer()
        self.queuePlayer = placeholder
        attachLayer(player: placeholder)
        placeholder.isMuted = true

        Task {
            do {
                let source = AVURLAsset(url: url)
                let half = try await source.load(.duration)
                let composition = try await Self.makePingPongComposition(from: source)

                await MainActor.run {
                    self.halfDuration = CMTimeGetSeconds(half)

                    let item = AVPlayerItem(asset: composition)
                    let queuePlayer = AVQueuePlayer(playerItem: item)
                    self.queuePlayer = queuePlayer
                    self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

                    self.playerLayer?.player = queuePlayer
                    queuePlayer.isMuted = true

                    if self.startInBoomerang || self.hasCompletedFirstPassBinding?.wrappedValue == true {
                        self.markFirstPassComplete()
                    }

                    self.setupTimeObserver()
                    queuePlayer.play()
                }
            } catch {
                await MainActor.run {
                    AppLogger.log("⚠️ VideoBackground: Ping-pong composition failed (\(error)); falling back to forward loop")
                    self.queuePlayer = nil
                    self.playerLayer?.removeFromSuperlayer()
                    self.playerLayer = nil
                    self.setupForwardLoopPlayer(url: url)
                }
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

    private func setupTimeObserver() {
        guard let player = queuePlayer, halfDuration > 0 else { return }

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }

            let current = CMTimeGetSeconds(time)
            guard current.isFinite, self.halfDuration > 0 else { return }

            switch self.loopMode {
            case .forwardLoop:
                let progress = min(1.0, max(0.0, current / self.halfDuration))
                self.playbackProgressBinding?.wrappedValue = progress

            case .boomerangAfterFirstPass:
                // Composition timeline: [0, T) forward, [T, 2T) reverse.
                // Map into 0…1 over the active half for blur; lock after first forward.
                let t = current.truncatingRemainder(dividingBy: self.halfDuration * 2)
                if t < self.halfDuration {
                    self.playbackProgressBinding?.wrappedValue = min(1.0, max(0.0, t / self.halfDuration))
                    if t >= self.halfDuration - 0.05 {
                        self.markFirstPassComplete()
                    }
                } else {
                    // Reverse half: report 1→0 (full clip playing backward as forward decode).
                    let reverseT = t - self.halfDuration
                    self.playbackProgressBinding?.wrappedValue = min(1.0, max(0.0, 1.0 - reverseT / self.halfDuration))
                    self.markFirstPassComplete()
                }
            }

            if self.isVideoReadyBinding?.wrappedValue == false {
                self.isVideoReadyBinding?.wrappedValue = true
            }
        }
    }

    func markFirstPassComplete() {
        guard !didMarkFirstPass else {
            hasCompletedFirstPassBinding?.wrappedValue = true
            return
        }
        didMarkFirstPass = true
        hasCompletedFirstPassBinding?.wrappedValue = true
    }

    // MARK: - Ping-pong composition

    /// [0, T] = original forward; [T, 2T] = same frames in reverse order.
    private static func makePingPongComposition(from asset: AVAsset) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let sourceTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceTrack = sourceTracks.first else {
            throw PingPongError.noVideoTrack
        }
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PingPongError.couldNotCreateTrack
        }

        let duration = try await asset.load(.duration)
        let transform = try await sourceTrack.load(.preferredTransform)
        track.preferredTransform = transform

        // Full forward pass
        try track.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceTrack,
            at: .zero
        )

        // Full reverse pass — insert frame-sized slices from end → start so
        // playback of this half at rate +1 looks like a complete rewind.
        var frameDuration = try await sourceTrack.load(.minFrameDuration)
        if !frameDuration.isNumeric || frameDuration.seconds <= 0 || frameDuration.seconds > 0.2 {
            frameDuration = CMTime(value: 1, timescale: 24)
        }

        var insertAt = duration
        var sourceCursor = duration

        while CMTimeCompare(sourceCursor, .zero) > 0 {
            let chunk: CMTime
            if CMTimeCompare(sourceCursor, frameDuration) <= 0 {
                chunk = sourceCursor
            } else {
                chunk = frameDuration
            }
            sourceCursor = CMTimeSubtract(sourceCursor, chunk)
            try track.insertTimeRange(
                CMTimeRange(start: sourceCursor, duration: chunk),
                of: sourceTrack,
                at: insertAt
            )
            insertAt = CMTimeAdd(insertAt, chunk)
        }

        return composition
    }

    private enum PingPongError: Error {
        case noVideoTrack
        case couldNotCreateTrack
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
