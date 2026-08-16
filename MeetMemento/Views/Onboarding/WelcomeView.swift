//
//  WelcomeView.swift
//  MeetMemento
//
//  Welcome screen with video background. No account, no sign-in — a single
//  "Get Started" CTA moves straight into onboarding (spec 023 R2).
//

import SwiftUI

public struct WelcomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var appState: AppStateStore

    // Video loading and blur states
    @State private var isVideoReady = false
    @State private var playbackProgress: Double = 0
    @State private var hasCompletedFirstLoop = false

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

    /// Calculate blur amount based on video playback progress
    /// Delayed start with quadratic ease-in for a more delicate feel
    private var blurAmount: CGFloat {
        // No blur during exit (dissolving to white)
        if isExiting { return 0 }

        // Don't blur until content has loaded
        guard blurCanStart else { return 0 }

        if hasCompletedFirstLoop {
            return 40  // Stay at max blur after first loop
        }

        // Let video play clear for first 40%, then ease blur in
        let blurStartThreshold: Double = 0.4

        if playbackProgress < blurStartThreshold {
            return 0  // Crystal clear video
        }

        // Remap 0.4-1.0 → 0-1, then apply ease-in curve
        let normalizedProgress = (playbackProgress - blurStartThreshold) / (1.0 - blurStartThreshold)
        let easedProgress = normalizedProgress * normalizedProgress  // Quadratic ease-in

        return CGFloat(easedProgress) * 40
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Layer 1: White background (always present, visible during dissolve)
                Color.white
                    .ignoresSafeArea()

                // Layer 2: Video background (dissolves in/out)
                VideoBackground(
                    videoName: "welcome-bg",
                    videoExtension: "mp4",
                    isVideoReady: $isVideoReady,
                    playbackProgress: $playbackProgress
                )
                .opacity(videoOpacity)
                .blur(radius: blurAmount)
                .ignoresSafeArea()
                .onChange(of: playbackProgress) { oldValue, newValue in
                    // Detect loop completion (progress resets from ~1 to ~0)
                    if oldValue > 0.9 && newValue < 0.1 {
                        hasCompletedFirstLoop = true
                    }
                }

                // Layer 3: Gradient overlay (follows video opacity)
                LinearGradient(
                    colors: [Color.white.opacity(0.4), Color.white.opacity(0)],
                    startPoint: .top,
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
                    hasCompletedFirstLoop = true
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
                    hasCompletedFirstLoop = true
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

                    // Phase 3: After content loads, enable blur
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        blurCanStart = true
                    }
                }
            }
        }
        .useTypography()
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

    // MARK: - Content Overlay

    private var contentOverlay: some View {
        VStack(spacing: 0) {
            // Logo at center-top
            Image("Memento-Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .padding(.top, 32)
                .opacity(showLogo ? 1 : 0)

            Spacer()

            // Headline - centered
            Text("Journal with your voice, reflect privately on your device")
                .font(.custom("Lora-SemiBold", size: 32))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .accessibilityIdentifier("welcome.headline")
                .opacity(showHeadline ? 1 : 0)

            // Positioning line (REQ-POS-001) — the first UI expression of the
            // trust boundary. 1.x is on-device (Z0) only: no Private Cloud
            // Compute path has shipped, so the copy must not mention it.
            // Re-introduce the PCC clause only when Z1 routing actually lands.
            //
            // Restored 2026-08-16. `adbe7fa` ("boomerang the intro video")
            // deleted this Text and all nine of its modifiers as collateral —
            // its commit message never mentions the positioning line, and the
            // comment above was left stranded over a blank line. `b1bab65`
            // reverted that commit's video change but not this. The only thing
            // that noticed for five days was the smoke test asserting
            // `welcome.positioning`, which has been red ever since.
            Text("No account. No analytics. No third-party AI. Your words are processed on your iPhone with Apple's on-device models. Nothing else.")
                .font(type.body2)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .accessibilityIdentifier("welcome.positioning")
                .opacity(showHeadline ? 1 : 0)

            Spacer()

            // Get Started — no sign-in step; moves straight into onboarding.
            getStartedSection
                .padding(.horizontal, 24)
                .opacity(showButtons ? 1 : 0)
        }
    }

    // MARK: - Get Started

    @ViewBuilder
    private var getStartedSection: some View {
        Button(action: { getStarted() }) {
            Text("Get Started")
                .font(type.body1Bold)
                // AX5: minHeight lets the button grow instead of clipping/overlapping
                // the label text when it scales up at large Dynamic Type sizes.
                .frame(minHeight: 48)
                .frame(maxWidth: .infinity)
                .background(.black)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
        }
        .disabled(isExiting)
        .accessibilityIdentifier("welcome.getStarted")
    }

    // MARK: - Actions

    private static let exitDissolveDuration: TimeInterval = 0.5

    /// Phase 4: Exit animation — dissolve video and content to white.
    private func handleExit() {
        isExiting = true

        withAnimation(.easeInOut(duration: Self.exitDissolveDuration)) {
            videoOpacity = 0
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
