//
//  WelcomeView.swift
//  MeetMemento
//
//  Welcome screen with video background. No account, no sign-in — Get
//  Started reveals a privacy explainer (Figma 1009:9894), then "Open my
//  journal" hands off to onboarding (spec 023).
//

import SwiftUI

public struct WelcomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Intro wordmark → privacy explainer. Video and blur stay put.
    @State private var step: WelcomeStep = .intro
    /// How many privacy cards have faded in (0...3).
    @State private var visiblePrivacyCards = 0

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
                // Plate only while dissolving (intro in / Get Started out).
                // A standing plate flashes through when the player wraps.
                // Intro dissolves up from the white LaunchScreen, so that leg
                // stays white; the exit hands off to onboarding, which paints
                // `theme.background` — black in dark mode — so it must
                // dissolve to the same colour or the bridge flashes white.
                if isExiting || videoOpacity < 1 {
                    (isExiting ? theme.background : Color.white)
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
                        .opacity(isExiting ? 0 : 1)
                }

                // Layer 5: Launch screen replica while loading (skip when returning from onboarding)
                if !isVideoReady && !skipIntroAnimations {
                    launchLoadingView
                        .transition(.opacity.animation(.easeInOut(duration: 1.2)))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 1.0), value: isVideoReady)
            .animation(.easeInOut(duration: 0.45), value: step)
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
    /// Figma 1009:9894 — privacy explainer after Get Started.
    @ViewBuilder
    private var contentOverlay: some View {
        VStack(spacing: Spacing.xxl) {
            ZStack {
                switch step {
                case .intro:
                    introOverlay
                        .transition(.opacity)
                case .privacy:
                    privacyOverlay
                        .transition(.opacity)
                }
            }

            welcomeCTA(
                title: step == .intro ? "Get Started" : "Open my journal",
                identifier: step == .intro ? "welcome.getStarted" : "welcome.openJournal",
                hint: step == .intro
                    ? "Double-tap to learn how Memento stays private"
                    : "Double-tap to start setting up Memento",
                labelColor: step == .intro ? WarmNeutral.w600 : Color(hex: "#4F321D")
            ) {
                if step == .intro {
                    revealPrivacy()
                } else {
                    beginOnboarding()
                }
            }
            .opacity(step == .privacy || showButtons ? 1 : 0)
            .allowsHitTesting((step == .privacy || showButtons) && !isExiting)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.md)
        }
    }

    private var introOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

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
            .padding(.horizontal, Spacing.xl)
        }
    }

    /// Figma 1009:9894 — same loop and blur; intro copy is gone.
    private var privacyOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconButtonNav(
                icon: "chevron.left",
                foregroundColor: .white,
                enableHaptic: true,
                accessibilityLabel: "Back",
                onTap: returnToIntro
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxl)
            .disabled(isExiting)
            .accessibilityHint("Double-tap to return to the welcome screen")

            VStack(alignment: .leading, spacing: 0) {
                Text("Memento is a fully private app")
                    .font(type.h3)
                    .foregroundStyle(.white)
                    .lineSpacing(type.extraLineSpacing(for: Typography.baseSize2XL, lineHeight: 32))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("welcome.privacyTitle")

                Text("This means we cannot read your journal entries or your chats.")
                    .font(.custom("Figtree-SemiBold", size: 18, relativeTo: .title))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(type.extraLineSpacing(for: 18, lineHeight: 27))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
                    .accessibilityIdentifier("welcome.privacySubtitle")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)

            VStack(alignment: .leading, spacing: Spacing.xl) {
                privacyFeatureCard(
                    asset: "WelcomePrivacyAuth",
                    title: "No authentication required",
                    body: "Simply download the app to get started."
                )
                .opacity(visiblePrivacyCards >= 1 ? 1 : 0)
                .offset(y: visiblePrivacyCards >= 1 ? 0 : 16)

                privacyFeatureCard(
                    asset: "WelcomePrivacyData",
                    title: "None of your data is collected",
                    body: "All your information is stored directly on your device."
                )
                .opacity(visiblePrivacyCards >= 2 ? 1 : 0)
                .offset(y: visiblePrivacyCards >= 2 ? 0 : 16)

                privacyFeatureCard(
                    asset: "WelcomePrivacyDevice",
                    title: "AI runs on your own device",
                    body: "Chat, retrieval, and speech stay on device at all times.",
                    leafSize: CGSize(width: 18.67, height: 26.67)
                )
                .opacity(visiblePrivacyCards >= 3 ? 1 : 0)
                .offset(y: visiblePrivacyCards >= 3 ? 0 : 16)
            }
            .padding(.horizontal, Spacing.md)

            Spacer(minLength: 0)
        }
    }

    private func privacyFeatureCard(
        asset: String,
        title: String,
        body: String,
        leafSize: CGSize? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Group {
                if let leafSize {
                    Image(asset)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: leafSize.width, height: leafSize.height)
                } else {
                    Image(asset)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 32, height: 32)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.custom("Figtree-Bold", size: 18, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .lineSpacing(type.extraLineSpacing(for: 18, lineHeight: 24))
                Text(body)
                    .font(.custom("Figtree-Bold", size: 18, relativeTo: .headline))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(type.extraLineSpacing(for: 18, lineHeight: 24))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
                .fill(Color(red: 175 / 255, green: 175 / 255, blue: 175 / 255).opacity(0.24))
        )
        .accessibilityElement(children: .combine)
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

    // MARK: - Shared CTA

    /// White wash — 32% at the top, 48% at the bottom. Used by Get Started and
    /// Open my journal so the two steps share one chip.
    private static let ctaFillTopOpacity: Double = 0.32
    private static let ctaFillBottomOpacity: Double = 0.48

    private func welcomeCTA(
        title: String,
        identifier: String,
        hint: String,
        labelColor: Color = WarmNeutral.w600,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)

        return Button(action: action) {
            Text(title)
                .font(.custom("Figtree-Bold", size: 18, relativeTo: .body))
                .kerning(-0.28)
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.xl)
                .frame(minHeight: AppHeaderMetrics.minimumTapTarget)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(Self.ctaFillTopOpacity),
                            Color.white.opacity(Self.ctaFillBottomOpacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(PrimaryButtonPressStyle())
        .disabled(isExiting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(hint)
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Actions

    private static let exitDissolveDuration: TimeInterval = 0.5
    private static let stepCrossfadeDuration: TimeInterval = 0.45

    private func revealPrivacy() {
        guard !isExiting, step == .intro else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        visiblePrivacyCards = 0
        withAnimation(.easeInOut(duration: Self.stepCrossfadeDuration)) {
            step = .privacy
        }
        if reduceMotion {
            visiblePrivacyCards = 3
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            visiblePrivacyCards = 1
        }
        withAnimation(.easeInOut(duration: 0.5).delay(0.22)) {
            visiblePrivacyCards = 2
        }
        withAnimation(.easeInOut(duration: 0.5).delay(0.44)) {
            visiblePrivacyCards = 3
        }
    }

    private func returnToIntro() {
        guard !isExiting, step == .privacy else { return }
        withAnimation(.easeInOut(duration: Self.stepCrossfadeDuration)) {
            step = .intro
            showLogo = true
            showHeadline = true
            showButtons = true
            visiblePrivacyCards = 0
        }
    }

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
    private func beginOnboarding() {
        guard !isExiting else { return }
        handleExit()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.exitDissolveDuration * 1_000_000_000))
            appState.isEnteringOnboardingFromWelcome = true
            appState.hasStartedOnboarding = true
        }
    }
}

private enum WelcomeStep {
    case intro
    case privacy
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
