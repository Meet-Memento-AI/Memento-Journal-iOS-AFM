//
//  LoadingStateView.swift
//  MeetMemento
//
//  Onboarding completion loading screen with animation
//

import SwiftUI

public struct LoadingStateView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Animation states
    @State private var showProgress = false
    @State private var loadingPhase: LoadingPhase = .initial
    @State private var currentTipIndex = 0
    @State private var showTip = false

    // Resource tracking for cleanup
    @State private var tipRotationTimer: Timer?
    @State private var loadingTasks: [Task<Void, Never>] = []

    public var onComplete: (() -> Void)?

    public init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Modern gradient background
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Modern loading indicator
                if showProgress {
                    VStack(spacing: 24) {
                        // Animated progress ring
                        ModernProgressRing()
                            .frame(width: 48, height: 48)
                            .padding(.top, 40)

                        // Status message with modern styling
                        Text(loadingPhase.message)
                            .font(type.body1)
                            .foregroundStyle(theme.foreground)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .id(loadingPhase)
                    }
                    .transition(.opacity)
                }

                Spacer()
                Spacer()

                // Modern tip card
                if showTip {
                    TipCard(
                        icon: loadingTips[currentTipIndex].icon,
                        title: loadingTips[currentTipIndex].title,
                        message: loadingTips[currentTipIndex].message
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(currentTipIndex)
                }
            }
        }
        .accessibilityLabel("Loading MeetMemento. \(loadingPhase.message)")
        .onAppear {
            startLoadingSequence()
        }
        .onDisappear {
            // Clean up timer to prevent retain cycle
            tipRotationTimer?.invalidate()
            tipRotationTimer = nil

            // Cancel all tracked tasks
            loadingTasks.forEach { $0.cancel() }
            loadingTasks.removeAll()
        }
    }

    // MARK: - Loading Sequence

    private func startLoadingSequence() {
        if reduceMotion {
            // Show everything immediately for reduced motion
            showProgress = true
            startProgressiveLoading()
        } else {
            // Modern fluid entrance
            let entranceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.4)) {
                    showProgress = true
                }
                startProgressiveLoading()
            }
            loadingTasks.append(entranceTask)
        }

        // Show tips after 1.5 seconds
        let tipsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showTip = true
            }
            startTipRotation()
        }
        loadingTasks.append(tipsTask)

        // Complete after content loads (simulated with 5 second delay)
        let completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            onComplete?()
        }
        loadingTasks.append(completionTask)
    }

    private func startProgressiveLoading() {
        // Phase 1: Preparing space (0-2s)
        loadingPhase = .authenticating

        // Phase 2: Loading data (2-4s)
        let phase2Task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                loadingPhase = .loadingData
            }
        }
        loadingTasks.append(phase2Task)

        // Phase 3: Almost ready (4s+)
        let phase3Task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                loadingPhase = .finalizing
            }
        }
        loadingTasks.append(phase3Task)
    }

    private func startTipRotation() {
        // Rotate tips every 6 seconds with smooth transition
        // Timer callback may fire on non-main thread, so dispatch to main queue
        // to safely update @State properties
        tipRotationTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    currentTipIndex = (currentTipIndex + 1) % loadingTips.count
                }
            }
        }
    }
}

// Note: ModernProgressRing, TipCard, LoadingPhase, LoadingTip, and loadingTips
// are now shared components in Components/Loading/

// MARK: - Previews

#Preview("Light") {
    LoadingStateView {
        AppLogger.log("Onboarding complete!")
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    LoadingStateView {
        AppLogger.log("Onboarding complete!")
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
