//
//  WelcomeView.swift
//  MeetMemento
//
//  Welcome screen with video background and unified auth buttons.
//

import SwiftUI

public struct WelcomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var isAppleLoading = false
    @State private var isGoogleLoading = false
    @State private var authError: String = ""

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
                if authViewModel.isReturningFromOnboarding {
                    skipIntroAnimations = true
                    authViewModel.isReturningFromOnboarding = false
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
            Text("Journal with your voice, reflect privately with AI")
                .font(.custom("Lora-SemiBold", size: 32))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .accessibilityIdentifier("welcome.headline")
                .opacity(showHeadline ? 1 : 0)

            Spacer()

            // Auth buttons at bottom
            authButtonsSection
                .padding(.horizontal, 24)
                .opacity(showButtons ? 1 : 0)
        }
        .accessibilityIdentifier("welcome.root")
    }

    // MARK: - Auth Buttons Section

    @ViewBuilder
    private var authButtonsSection: some View {
        VStack(spacing: 16) {
            Button(action: { signInWithApple() }) {
                HStack(spacing: 8) {
                    if isAppleLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .bold))
                    }
                    Text("Continue with Apple")
                        .font(type.body1Bold)
                }
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(.black)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            }
            .accessibilityIdentifier("welcome.continueApple")
            .disabled(isAppleLoading || isGoogleLoading)
            .opacity((isAppleLoading || isGoogleLoading) ? 0.7 : 1.0)

            GoogleSignInButton(
                title: isGoogleLoading ? "Signing in..." : "Continue with Google",
                scheme: .light
            ) {
                signInWithGoogle()
            }
            .disabled(isAppleLoading || isGoogleLoading)
            .opacity((isAppleLoading || isGoogleLoading) ? 0.7 : 1.0)

            if !authError.isEmpty {
                Text(authError)
                    .font(type.body2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Auth Actions

    /// Phase 4: Exit animation - dissolve video and content to white
    /// SwiftUI transition in MeetMementoApp handles the 0.5s fade-out
    private func handleAuthSuccess() {
        isExiting = true

        // Quick internal fade (0.5s) synced with SwiftUI transition
        withAnimation(.easeInOut(duration: 0.5)) {
            videoOpacity = 0
            showLogo = false
            showHeadline = false
            showButtons = false
        }
    }

    private func signInWithApple() {
        isAppleLoading = true
        authError = ""

        Task {
            do {
                try await authViewModel.signInWithApple()
                await MainActor.run {
                    isAppleLoading = false
                    handleAuthSuccess()
                }
            } catch let error as AppleSignInError {
                await MainActor.run {
                    isAppleLoading = false
                    if case .canceled = error {
                        authError = ""
                    } else {
                        authError = error.localizedDescription
                    }
                }
            } catch {
                                AppLogger.log("🔴 Apple Sign In error: \(error)")
                await MainActor.run {
                    isAppleLoading = false
                    authError = error.localizedDescription
                }
            }
        }
    }

    private func signInWithGoogle() {
        isGoogleLoading = true
        authError = ""

        Task {
            do {
                try await authViewModel.signInWithGoogle()
                await MainActor.run {
                    isGoogleLoading = false
                    handleAuthSuccess()
                }
            } catch {
                                AppLogger.log("🔴 Google Sign In error: \(error)")
                await MainActor.run {
                    isGoogleLoading = false
                    authError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Previews
#Preview("Welcome • Light") {
    WelcomeView()
        .useTheme()
        .useTypography()
        .environmentObject(AuthViewModel.previewAuthReadyForWelcome())
        .preferredColorScheme(.light)
}

#Preview("Welcome • Dark") {
    WelcomeView()
        .useTheme()
        .useTypography()
        .environmentObject(AuthViewModel.previewAuthReadyForWelcome())
        .preferredColorScheme(.dark)
}
