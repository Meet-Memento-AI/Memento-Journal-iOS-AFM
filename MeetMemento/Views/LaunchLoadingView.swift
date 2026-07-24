//
//  LaunchLoadingView.swift
//  MeetMemento
//
//  Minimal loading view displayed while local app state loads.
//  Theme-aware background to avoid a light-to-dark flash after the OS launch screen.
//

import SwiftUI

struct LaunchLoadingView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var appState: AppStateStore
    @State private var isAnimating = false
    @State private var secondsVisible = 0

    var body: some View {
        ZStack {
            // Theme-aware background — the OS launch storyboard is always light
            // (a static asset that can't read colorScheme), but this first
            // SwiftUI-rendered frame should match dark mode immediately rather
            // than staying white until state resolves.
            theme.background.ignoresSafeArea()

            VStack(spacing: 24) {

                // Subtle loading indicator
                ProgressView()
                    .tint(theme.primary)
                    .scaleEffect(1.2)
                Text("Starting…")
                    .foregroundColor(theme.mutedForeground)
                    .font(.caption)
            }
        }
        .onAppear {
            isAnimating = true
        }
        .task {
            // No network call backs this anymore — state loads from UserDefaults
            // synchronously in appState.initializeAppState(). This failsafe exists
            // only in case that call is somehow delayed (e.g. a slow first launch).
            while !Task.isCancelled && !appState.hasCheckedAuth {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                secondsVisible += 1

                if secondsVisible >= 6 && !appState.hasCheckedAuth {
                    appState.resetToFreshInstall(reason: "LaunchLoadingView 6s failsafe fired after \(secondsVisible)s")
                    break
                }
            }
        }
#if DEBUG
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("startup diagnostics")
                    .font(.caption2.weight(.semibold))
                Text(verbatim: "secondsVisible=\(secondsVisible)")
                Text(verbatim: "hasCheckedAuth=\(appState.hasCheckedAuth)")
                Text(verbatim: "isInitializing=\(appState.isInitializing)")
                Text(verbatim: "hasCompletedOnboarding=\(appState.hasCompletedOnboarding)")
            }
            .font(.caption2.monospaced())
            .foregroundColor(theme.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.cardBackground.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
#endif
    }
}

#Preview("Light") {
    LaunchLoadingView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore.previewReadyForWelcome())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LaunchLoadingView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore.previewReadyForWelcome())
        .preferredColorScheme(.dark)
}
