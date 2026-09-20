//
//  LoadingView.swift
//  MeetMemento
//
//  Modern loading experience with fluid animations and mindful content
//

import SwiftUI

struct LoadingView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Animation states
    @State private var showIcon = false
    @State private var showAppName = false
    @State private var showProgress = false
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0
    @State private var breathingScale: CGFloat = 1.0

    // Progressive loading states
    @State private var loadingPhase: LoadingPhase = .initial
    @State private var currentTipIndex = 0
    @State private var showTip = false

    // Minimum display time enforcement
    @State private var hasMetMinimumDisplayTime = false

    // Memory management - timer and task tracking for cleanup
    @State private var tipTimer: Timer?
    @State private var animationTasks: [Task<Void, Never>] = []

    var body: some View {
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
            enforceMinimumDisplayTime()
        }
        .onDisappear {
            // CRITICAL: Clean up timer to prevent memory leak
            tipTimer?.invalidate()
            tipTimer = nil

            // Cancel all animation tasks to prevent orphaned async work
            animationTasks.forEach { $0.cancel() }
            animationTasks.removeAll()
        }
    }

    // MARK: - Loading Sequence

    private func startLoadingSequence() {
        if reduceMotion {
            // Show everything immediately for reduced motion
            showIcon = true
            showAppName = true
            showProgress = true
            iconScale = 1.0
            iconOpacity = 1.0

            startProgressiveLoading()
        } else {
            // Modern fluid entrance
            showIcon = true

            withAnimation(.easeOut(duration: 0.8)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }

            // Start breathing animation
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                breathingScale = 1.08
            }

            let task1 = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showAppName = true
                }
            }
            animationTasks.append(task1)

            let task2 = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.4)) {
                    showProgress = true
                }
                startProgressiveLoading()
            }
            animationTasks.append(task2)
        }

        // Show tips after 2.5 seconds
        let task3 = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showTip = true
            }
            startTipRotation()
        }
        animationTasks.append(task3)
    }

    private func startProgressiveLoading() {
        // Phase 1: Checking authentication (0-2s)
        loadingPhase = .authenticating

        // Phase 2: Loading data (2-5s)
        let task4 = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                loadingPhase = .loadingData
            }
        }
        animationTasks.append(task4)

        // Phase 3: Almost ready (5s+)
        let task5 = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                loadingPhase = .finalizing
            }
        }
        animationTasks.append(task5)
    }

    private func startTipRotation() {
        // Rotate tips every 6 seconds with smooth transition
        // Timer callback may fire on non-main thread, so dispatch to main queue
        // to safely update @State properties
        tipTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    currentTipIndex = (currentTipIndex + 1) % loadingTips.count
                }
            }
        }
    }

    private func enforceMinimumDisplayTime() {
        // Ensure loading view shows for at least 800ms to avoid jarring flashes
        let task6 = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            hasMetMinimumDisplayTime = true
        }
        animationTasks.append(task6)
    }
}

// Note: ModernProgressRing, TipCard, LoadingPhase, LoadingTip, and loadingTips
// are now shared components in Components/Loading/

// MARK: - Previews

#Preview("Light") {
    LoadingView()
        .useTheme()
        .useTypography()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LoadingView()
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

