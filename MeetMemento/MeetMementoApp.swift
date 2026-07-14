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

        #if DEBUG
        print("🔴 MeetMementoApp init() called")
        #endif
    }

    var body: some Scene {
        let _ = { print("🔴 MeetMementoApp body evaluated") }()
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
                                    #if DEBUG
                                    print("🔴 ContentView appeared")
                                    #endif
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
                                #if DEBUG
                                print("🔴 WelcomeView appeared")
                                print("🔴 Auth state: isAuthenticated=\(authViewModel.isAuthenticated), hasCompletedOnboarding=\(authViewModel.hasCompletedOnboarding)")
                                #endif
                            }
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .task {
                #if DEBUG
                print("🔴 .task block started")
                #endif

                // Watchdog: if initializeAuth() hangs for any reason, force the
                // app past the loading screen after a short timeout.
                let watchdog = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !authViewModel.hasCheckedAuth {
                        print("⚠️ [Watchdog] initializeAuth() timed out — forcing unauthenticated state")
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
                #if DEBUG
                print("🔴 .task block completed")
                #endif
            }
            .onChange(of: authViewModel.hasCompletedOnboarding) { _, completed in
                // Consume skip flag when transitioning from onboarding to main app
                if completed {
                    lockScreenViewModel.consumeSkipNextLockScreen()
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                #if DEBUG
                print("🔴 Scene phase changed: \(oldPhase) -> \(newPhase)")
                #endif
                if newPhase == .background || newPhase == .inactive {
                    lockScreenViewModel.lock()
                }
                if newPhase == .active && authViewModel.isAuthenticated {
                    // Update activity timestamp when app becomes active
                    SecurityService.shared.updateActivityTimestamp()
                }
            }
            .onOpenURL { url in
                #if DEBUG
                print("🔴 Received deep link URL: \(url)")
                #endif
                SupabaseService.shared.client.auth.handle(url)
            }
        }
    }
}
