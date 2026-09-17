//
//  VideoBackground.swift
//  MeetMemento
//
//  Full-bleed looping video, gapless via `AVPlayerLooper`.
//
//  Clips that need to ping-pong must ship the reverse leg baked into the
//  file (`welcome-bg.mp4` is forward 0…191 then reverse 190…1). Building
//  the reverse half at runtime out of per-frame composition segments is
//  what used to make the loop stutter: the source had a single I-frame, so
//  every reversed frame forced a decode from the top of the clip.
//

import SwiftUI
import UIKit
import AVKit

struct VideoBackground: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    @Binding var isVideoReady: Bool

    init(
        videoName: String,
        videoExtension: String = "mp4",
        isVideoReady: Binding<Bool> = .constant(true)
    ) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self._isVideoReady = isVideoReady
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(frame: .zero)
        view.videoName = videoName
        view.videoExtension = videoExtension
        view.isVideoReadyBinding = $isVideoReady
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

final class PlayerUIView: UIView {
    var videoName: String = ""
    var videoExtension: String = "mp4"
    var isVideoReadyBinding: Binding<Bool>?

    private var playerLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObserver: NSKeyValueObservation?
    private var didSetup = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resizing the layer mid-playback re-rasterizes every frame under it,
        // so keep the implicit animation off.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()

        guard !didSetup, bounds.width > 0, bounds.height > 0 else { return }
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

        let template = AVPlayerItem(asset: AVURLAsset(url: url))
        // A background loop must never rebuffer mid-frame; it is a small local
        // file, so hold enough of it to ride out a busy main thread.
        template.preferredForwardBufferDuration = 4

        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        // Local asset: starting immediately beats AVFoundation's stall heuristics,
        // which otherwise hesitate on the first loop.
        player.automaticallyWaitsToMinimizeStalling = false
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

    private func teardownPlayback() {
        readyObserver?.invalidate()
        readyObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
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
