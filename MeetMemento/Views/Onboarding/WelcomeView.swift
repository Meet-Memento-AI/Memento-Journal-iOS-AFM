//
//  WelcomeView.swift
//  MeetMemento
//
//  Welcome screen with video background. No account, no sign-in — a single
//  "Get Started" CTA moves straight into onboarding (spec 023
//

import SwiftUI

public struct WelcomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject var appState: AppStateStore

    // Video loading and blur states
    @State private var isVideoReady = false
    /// Applied as a one-shot animation, not per-tick from the playhead.
    /// Driving SwiftUI `.blur` from a 10 Hz progress binding re-rasterized
    /// the player every frame and made Welcome look like a slideshow.
    @State private var appliedBlur: CGFloat = 0

    // Animation sequence states
    @State private var videoOpacity: Double = 0        // For video dissolve
    @State private var contentCanAppear = false        // Gate for content
    @State private var blurCanStart = false            // Gate for blur
    @State private var isExiting = false               // Triggers exit dissolve

    // Staggered animation states
    @State private var showLogo = false
    @State private var showHeadline = false
    @State private var showButtons = false

    // Track if we should skip intro animations (when returning from onboarding)
    @State private var skipIntroAnimations = false

    /// UI tests must not depend on video-decode timing, which behaves
    /// differently (and was observed to sometimes never fire `isVideoReady`)
    /// under XCUITest's launch semantics versus a normal launch. Content
    /// renders immediately in this mode instead of waiting on the video.
    private var isUITestLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.environment["MEETMEMENTO_UI_TEST"] == "1"
    }

    public init() {}

    /// Extra layout around the player so a 100pt kernel samples video, not
    /// empty pixels. Fixed at the ceiling so the AVPlayer layer never resizes
    /// while the blur eases in.
    private var videoBlurOverflow: CGFloat { JournalBackdropShader.blurStrength }

    private var targetBlur: CGFloat {
        if isExiting || reduceTransparency { return 0 }
        return blurCanStart ? JournalBackdropShader.blurStrength : 0
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // White only while dissolving (intro in / Get Started out).
                // A standing plate flashes through when the player wraps.
                if isExiting || videoOpacity < 1 {
                    Color.white
                        .ignoresSafeArea()
                }

                welcomeVideo

                // Figma 905:2047 — light bottom scrim for the wordmark, not a
                // top-white wash that reads as the video being cut off.
                LinearGradient(
                    colors: [
                        Color.clear,
                        JournalBackdropShader.scrimColor.opacity(0.15)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .opacity(videoOpacity)
                .ignoresSafeArea()

                // Layer 4: Content (appears after video dissolve)
                if contentCanAppear {
                    contentOverlay
                }

                // Layer 5: Launch screen replica while loading (skip when returning from onboarding)
                if !isVideoReady && !skipIntroAnimations {
                    launchLoadingView
                        .transition(.opacity.animation(.easeInOut(duration: 1.2)))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 1.0), value: isVideoReady)
            .onAppear {
                // Check if returning from onboarding - skip intro animations
                if appState.isReturningFromOnboarding {
                    skipIntroAnimations = true
                    appState.isReturningFromOnboarding = false
                }

                if isUITestLaunch {
                    // Also suppresses the launchLoadingView overlay (layer 5,
                    // gated on `!isVideoReady && !skipIntroAnimations`), which
                    // would otherwise visually cover the content set below.
                    skipIntroAnimations = true
                    videoOpacity = 1.0
                    contentCanAppear = true
                    showLogo = true
                    showHeadline = true
                    showButtons = true
                    blurCanStart = true
                    appliedBlur = targetBlur
                }
            }
            .onChange(of: isVideoReady) { _, ready in
                guard ready else { return }

                // If returning from onboarding, show everything immediately
                if skipIntroAnimations {
                    videoOpacity = 1.0
                    contentCanAppear = true
                    showLogo = true
                    showHeadline = true
                    showButtons = true
                    blurCanStart = true
                    appliedBlur = targetBlur
                    return
                }

                // Phase 1: Dissolve video in
                withAnimation(.easeInOut(duration: 1.2)) {
                    videoOpacity = 1.0
                }

                // After video dissolve, start content sequence
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    contentCanAppear = true

                    // Phase 2: Staggered content reveal
                    withAnimation(.easeInOut(duration: 0.8)) { showLogo = true }
                    withAnimation(.easeInOut(duration: 0.8).delay(0.3)) { showHeadline = true }
                    withAnimation(.easeInOut(duration: 0.8).delay(0.6)) { showButtons = true }

                    // Phase 3: Video stays readable while the CTA lands, then
                    // the wash eases across most of the first forward pass so
                    // it is fully live around the first reverse.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        blurCanStart = true
                        withAnimation(.easeInOut(duration: 6.0)) {
                            appliedBlur = targetBlur
                        }
                    }
                }
            }
        }
        .useTheme()
        .useTypography()
    }

    // MARK: - Video

    /// Full-bleed player. Blur runs on a downscaled copy so a 100pt wash
    /// does not re-rasterize 720p H.264 at full resolution every frame.
    private var welcomeVideo: some View {
        GeometryReader { geo in
            let overflow = videoBlurOverflow
            let downscale: CGFloat = 0.4
            VideoBackground(
                videoName: "welcome-bg",
                videoExtension: "mp4",
                loopMode: .pingPong,
                isVideoReady: $isVideoReady
            )
            .transaction { $0.animation = nil }
            .frame(
                width: geo.size.width + overflow * 2,
                height: geo.size.height + overflow * 2
            )
            .scaleEffect(downscale)
            .blur(radius: appliedBlur * downscale)
            .scaleEffect(1 / downscale)
            .opacity(videoOpacity)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Launch Loading View

    /// Matches the launch screen appearance for seamless transition
    private var launchLoadingView: some View {
        ZStack {
            // White background matching LaunchScreen.storyboard
            Color.white
                .ignoresSafeArea()

            // Memento-Logo centered, matching storyboard dimensions
            Image("Memento-Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 128)
        }
    }

    // MARK: - Welcome Mark

    /// Figma 905:2057 — 56pt AppIcon. Same hexagon + sparkle paths as
    /// `AppIcon-Transparent` (`WelcomeMarkShape`). White opacity ramps
    /// 32% → 64% across the mark only; the wordmark stays solid.
    private let welcomeMarkSize: CGFloat = 56

    private var welcomeMarkFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.32),
                Color.white.opacity(0.64)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var welcomeMark: some View {
        welcomeMarkFill
            .frame(width: welcomeMarkSize, height: welcomeMarkSize)
            .mask {
                ZStack {
                    WelcomeMarkBodyShape()
                    WelcomeMarkSparkleShape()
                }
            }
            .accessibilityHidden(true)
    }

    // MARK: - Content Overlay

    /// Figma 905:2054 — bottom stack, 24pt sides, 32pt between copy and CTA.
    private var contentOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    wordmarkRow
                        .opacity(showLogo ? 1 : 0)

                    Text("Journal with your voice, reflect privately on your device.")
                        .font(.custom("Figtree-SemiBold", size: Typography.baseSize2XL, relativeTo: .title))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(type.extraLineSpacing(for: Typography.baseSize2XL, lineHeight: 32))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("welcome.positioning")
                        .opacity(showHeadline ? 1 : 0)
                }

                getStartedSection
                    .opacity(showButtons ? 1 : 0)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.md)
        }
    }

    /// Figma 905:2056 — 56pt mark, 8pt gap, Lora Bold 40 "Memento".
    private var wordmarkRow: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            welcomeMark
            Text("Memento")
                .font(type.h1)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("welcome.headline")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memento")
    }

    // MARK: - Get Started

    /// Figma 905:2060 — white 64% frost, 16pt corners, warm-neutral/600 label.
    private static let getStartedGlassTintOpacity: Double = 0.64

    @ViewBuilder
    private var getStartedSection: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)

        Button(action: { getStarted() }) {
            Text("Get Started")
                .font(.custom("Figtree-Bold", size: 18, relativeTo: .body))
                .kerning(-0.28)
                .foregroundStyle(WarmNeutral.w600)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: AppHeaderMetrics.minimumTapTarget)
                .glassEffect(
                    .regular.tint(Color.white.opacity(Self.getStartedGlassTintOpacity)),
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(PrimaryButtonPressStyle())
        .disabled(isExiting)
        .allowsHitTesting(showButtons && !isExiting)
        // Promote the Button itself so XCTest/`VoiceOver` see one control
        // named Get Started, not the inner `Text` after glass wrapping.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Get Started")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to start setting up Memento")
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("welcome.getStarted")
    }

    // MARK: - Actions

    private static let exitDissolveDuration: TimeInterval = 0.5

    /// Phase 4: Exit animation — dissolve video and content to white.
    private func handleExit() {
        isExiting = true

        withAnimation(.easeInOut(duration: Self.exitDissolveDuration)) {
            videoOpacity = 0
            appliedBlur = 0
            showLogo = false
            showHeadline = false
            showButtons = false
        }
    }

    /// Dissolve Welcome to white, then hand off to onboarding so YourName can
    /// fade in on the white bridge (no mid-fade root swap / LoadingView flash).
    private func getStarted() {
        guard !isExiting else { return }
        handleExit()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.exitDissolveDuration * 1_000_000_000))
            appState.isEnteringOnboardingFromWelcome = true
            appState.hasStartedOnboarding = true
        }
    }
}

// MARK: - Previews
#Preview("Welcome • Light") {
    WelcomeView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore.previewReadyForWelcome())
        .preferredColorScheme(.light)
}

#Preview("Welcome • Dark") {
    WelcomeView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore.previewReadyForWelcome())
        .preferredColorScheme(.dark)
}
