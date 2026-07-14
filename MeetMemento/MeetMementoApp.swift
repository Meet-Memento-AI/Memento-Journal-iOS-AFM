//
//  MeetMementoApp.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 9/30/25.
//

import SwiftUI
import UIKit

// MARK: - Root Background
/// A background view that matches the app's theme and extends to all screen edges
private struct RootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Use theme background colors from design tokens
        (colorScheme == .dark ? GrayScale.gray900 : BaseColors.white)
            .ignoresSafeArea()
    }
}

@main
struct MeetMementoApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var lockScreenViewModel = LockScreenViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Let RootBackground handle the theme-aware background color
        // Using clear allows SwiftUI to manage the background dynamically
        UIWindow.appearance().backgroundColor = .clear

                AppLogger.log("🔴 MeetMementoApp init() called")
    }

    var body: some Scene {
        let _ = { AppLogger.log("🔴 MeetMementoApp body evaluated") }()
        return WindowGroup {
            ZStack {
                // Full-screen background that extends under status bar/dynamic island
                RootBackground()

                Group {
                    if !authViewModel.hasCheckedAuth {
                        // Do not show Welcome/main until session + onboarding status are known (MEM-18).
                        LaunchLoadingView()
                            .useTheme()
                            .useTypography()
                            .environmentObject(authViewModel)
                    } else if authViewModel.isAuthenticated && authViewModel.hasCompletedOnboarding {
                        // LOGGED IN: Show lock screen for verification, then main app
                        if lockScreenViewModel.shouldShowLockScreen {
                            LockScreenView(viewModel: lockScreenViewModel)
                                .useTheme()
                                .useTypography()
                                .environmentObject(authViewModel)
                                .transition(.opacity)
                        } else {
                            ContentView()
                                .useTheme()
                                .useTypography()
                                .environmentObject(authViewModel)
                                .transition(.opacity)
                                .onAppear {
                                                                        AppLogger.log("🔴 ContentView appeared")
                                }
                        }
                    } else if authViewModel.isAuthenticated && !authViewModel.hasCompletedOnboarding {
                        // Authenticated but needs onboarding
                        OnboardingCoordinatorView(lockScreenViewModel: lockScreenViewModel)
                            .useTheme()
                            .useTypography()
                            .environmentObject(authViewModel)
                            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                    } else {
                        // LOGGED OUT: Show welcome/sign-in
                        WelcomeView()
                            .useTheme()
                            .useTypography()
                            .environmentObject(authViewModel)
                            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                            .onAppear {
                                                                AppLogger.log("🔴 WelcomeView appeared")
                                AppLogger.log("🔴 Auth state: isAuthenticated=\(authViewModel.isAuthenticated), hasCompletedOnboarding=\(authViewModel.hasCompletedOnboarding)")
                            }
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .task {
                                AppLogger.log("🔴 .task block started")

                // Watchdog: if initializeAuth() hangs for any reason, force the
                // app past the loading screen after a short timeout.
                let watchdog = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !authViewModel.hasCheckedAuth {
                        AppLogger.log("⚠️ [Watchdog] initializeAuth() timed out — forcing unauthenticated state")
                        authViewModel.isAuthenticated = false
                        authViewModel.hasCompletedOnboarding = false
                        authViewModel.authState = .unauthenticated
                        authViewModel.hasCheckedAuth = true
                        authViewModel.isInitializing = false
                    }
                }

                await authViewModel.initializeAuth()
                watchdog.cancel()

                lockScreenViewModel.consumeSkipNextLockScreen()
                                AppLogger.log("🔴 .task block completed")
            }
            .onChange(of: authViewModel.hasCompletedOnboarding) { _, completed in
                // Consume skip flag when transitioning from onboarding to main app
                if completed {
                    lockScreenViewModel.consumeSkipNextLockScreen()
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                                AppLogger.log("🔴 Scene phase changed: \(oldPhase) -> \(newPhase)")
                if newPhase == .background || newPhase == .inactive {
                    lockScreenViewModel.lock()
                }
                if newPhase == .active && authViewModel.isAuthenticated {
                    // Update activity timestamp when app becomes active
                    SecurityService.shared.updateActivityTimestamp()
                }
            }
            .onOpenURL { url in
                                AppLogger.log("🔴 Received deep link URL: \(url)")
                SupabaseService.shared.client.auth.handle(url)
            }
        }
    }
}
