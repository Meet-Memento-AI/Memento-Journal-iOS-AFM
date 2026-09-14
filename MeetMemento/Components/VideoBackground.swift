//
//  VideoBackground.swift
//  MeetMemento
//
//  Full-bleed looping video. Default is a gapless forward `AVPlayerLooper`.
//  Welcome opts into `.pingPong`: start→end, then end→start, forever.
//
//  `welcome-bg.mp4` is H.264 High with a single I-frame and a B-frame GOP.
//  `rate = -1` on that file is a slideshow. Ping-pong therefore plays two
//  *forward* items: the original clip, then a reversed composition of the
//  same frames. Both directions decode at rate 1.
//

import SwiftUI
import UIKit
import AVKit

enum VideoLoopMode {
    /// Gapless start→end→start via `AVPlayerLooper`.
    case forward
    /// Welcome: start→end, then end→start, forever.
    case pingPong
}

struct VideoBackground: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    var loopMode: VideoLoopMode = .forward
    @Binding var isVideoReady: Bool

    init(
        videoName: String,
        videoExtension: String = "mp4",
        loopMode: VideoLoopMode = .forward,
        isVideoReady: Binding<Bool> = .constant(true)
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.loopMode = loopMode
        self._isVideoReady = isVideoReady
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(frame: .zero)
        view.videoName = videoName
        view.videoExtension = videoExtension
        view.loopMode = loopMode
        view.isVideoReadyBinding = $isVideoReady
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    var videoName: String = ""
    var videoExtension: String = "mp4"
    var loopMode: VideoLoopMode = .forward
    var isVideoReadyBinding: Binding<Bool>?

    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var readyObserver: NSKeyValueObservation?
    private var didSetup = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
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
        if loopMode == .pingPong {
            setupPingPong(asset: asset)
        } else {
            startLooper(on: asset)
        }
    }

    private func setupPingPong(asset: AVURLAsset) {
        Task { [weak self] in
            do {
                let boomerang = try await Self.makeBoomerangComposition(from: asset)
                await MainActor.run {
                    self?.startLooper(on: boomerang)
                }
            } catch {
                AppLogger.log("⚠️ VideoBackground: boomerang composition failed — \(error)")
                await MainActor.run {
                    self?.startLooper(on: asset)
                }
            }
        }
    }

    private func startLooper(on asset: AVAsset) {
        let template = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        self.player = player
        looper = AVPlayerLooper(player: player, templateItem: template)
        attachLayer(player: player)
        observeReady(player)
        player.play()
    }

    private func attachLayer(player: AVPlayer) {
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer
    }

    private func observeReady(_ player: AVPlayer) {
        readyObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            let primed = player.currentItem?.status == .readyToPlay
            guard playing || primed else { return }
            DispatchQueue.main.async {
                guard self?.isVideoReadyBinding?.wrappedValue == false else { return }
                self?.isVideoReadyBinding?.wrappedValue = true
            }
        }
    }

    /// Original clip, then the same frames in reverse, as one asset. Playing
    /// this forward is start→end→start; `AVPlayerLooper` repeats it.
    ///
    /// Each reverse slice is a *forward* decode of one frame. That avoids
    /// `rate = -1` on a B-frame GOP, which is what looked like a slideshow.
    private static func makeBoomerangComposition(from asset: AVAsset) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first,
              let destTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              )
        else {
            throw BoomerangError.missingVideoTrack
        }

        let duration = try await asset.load(.duration)
        destTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)

        try destTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceTrack,
            at: .zero
        )

        var frameDuration = try await sourceTrack.load(.minFrameDuration)
        let floor = CMTime(value: 1, timescale: 24)
        if !frameDuration.isValid || frameDuration.seconds <= 0 || CMTimeCompare(frameDuration, floor) < 0 {
            frameDuration = floor
        }

        var cursor = duration
        var insertAt = duration
        var segments = 0
        let maxSegments = 240
        while cursor > .zero, segments < maxSegments {
            let start = CMTimeMaximum(.zero, CMTimeSubtract(cursor, frameDuration))
            let slice = CMTimeSubtract(cursor, start)
            guard CMTIME_IS_NUMERIC(slice), CMTimeGetSeconds(slice) > 0 else { break }
            try destTrack.insertTimeRange(
                CMTimeRange(start: start, duration: slice),
                of: sourceTrack,
                at: insertAt
            )
            insertAt = CMTimeAdd(insertAt, slice)
            cursor = start
            segments += 1
        }

        return composition
    }

    private func teardownPlayback() {
        readyObserver?.invalidate()
        readyObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
    }

    deinit {
        teardownPlayback()
    }

    private enum BoomerangError: Error {
        case missingVideoTrack
    }
}

// MARK: - Preview

#Preview {
    VideoBackground(videoName: "welcome-bg", videoExtension: "mp4", loopMode: .pingPong)
        .ignoresSafeArea()
}
