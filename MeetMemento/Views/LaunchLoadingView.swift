//
//  LaunchLoadingView.swift
//  MeetMemento
//
//  Minimal loading view displayed during auth initialization.
//  Matches the app's launch screen (white + centered logo) for a seamless transition.
//

import SwiftUI

struct LaunchLoadingView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var isAnimating = false
    @State private var secondsVisible = 0

    private var authStateLabel: String {
        switch authViewModel.authState {
        case .unauthenticated:
            return "unauthenticated"
        case .authenticated(needsOnboarding: let needsOnboarding):
            return needsOnboarding ? "authenticated(needsOnboarding)" : "authenticated"
        }
    }

    var body: some View {
        ZStack {
            // White background matching launch screen
            Color.white.ignoresSafeArea()

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
            while !Task.isCancelled && !authViewModel.hasCheckedAuth {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                secondsVisible += 1

                // Secondary failsafe in case root-level startup task gets interrupted.
                if secondsVisible >= 6 && !authViewModel.hasCheckedAuth {
                    AppLogger.log("⚠️ [LaunchLoadingView] Failsafe fired after \(secondsVisible)s")
                    authViewModel.isAuthenticated = false
                    authViewModel.hasCompletedOnboarding = false
                    authViewModel.authState = .unauthenticated
                    authViewModel.hasCheckedAuth = true
                    authViewModel.isInitializing = false
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
                Text(verbatim: "hasCheckedAuth=\(authViewModel.hasCheckedAuth)")
                Text(verbatim: "isInitializing=\(authViewModel.isInitializing)")
                Text(verbatim: "isAuthenticated=\(authViewModel.isAuthenticated)")
                Text(verbatim: "hasCompletedOnboarding=\(authViewModel.hasCompletedOnboarding)")
                Text(verbatim: "authState=\(authStateLabel)")
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
        .environmentObject(AuthViewModel.previewAuthReadyForWelcome())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LaunchLoadingView()
        .useTheme()
        .useTypography()
        .environmentObject(AuthViewModel.previewAuthReadyForWelcome())
        .preferredColorScheme(.dark)
}
