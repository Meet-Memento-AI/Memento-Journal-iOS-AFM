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
    @StateObject private var appState = AppStateStore()
    @StateObject private var lockScreenViewModel = LockScreenViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Let RootBackground handle the theme-aware background color
        // Using clear allows SwiftUI to manage the background dynamically
        UIWindow.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Full-screen background that extends under status bar/dynamic island
                RootBackground()

                Group {
                    if !appState.hasCheckedAuth {
                        // Do not show Welcome/main until local state is loaded (MEM-18).
                        // No network involved — this resolves near-instantly.
                        LaunchLoadingView()
                            .useTheme()
                            .useTypography()
                            .environmentObject(appState)
                    } else if appState.hasCompletedOnboarding {
                        // Onboarded: show lock screen for verification, then main app
                        if lockScreenViewModel.shouldShowLockScreen {
                            LockScreenView(viewModel: lockScreenViewModel)
                                .useTheme()
                                .useTypography()
                                .environmentObject(appState)
                                .transition(.opacity)
                        } else {
                            ContentView()
                                .useTheme()
                                .useTypography()
                                .environmentObject(appState)
                                .transition(.opacity)
                        }
                    } else if appState.hasStartedOnboarding {
                        // Mid-onboarding
                        OnboardingCoordinatorView(lockScreenViewModel: lockScreenViewModel)
                            .useTheme()
                            .useTypography()
                            .environmentObject(appState)
                            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                    } else {
                        // First run (or killed mid-onboarding): show Welcome
                        WelcomeView()
                            .useTheme()
                            .useTypography()
                            .environmentObject(appState)
                            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: appState.hasCompletedOnboarding)
                .animation(.easeInOut(duration: 0.4), value: appState.hasStartedOnboarding)
                // Root pages ignore the system safe area and pad by window
                // insets. Only RootBackground is full-bleed at this layer.
            }
            .task {
                appState.initializeAppState()
                lockScreenViewModel.consumeSkipNextLockScreen()
            }
            .onChange(of: appState.hasCompletedOnboarding) { _, completed in
                // Consume skip flag when transitioning from onboarding to main app
                if completed {
                    lockScreenViewModel.consumeSkipNextLockScreen()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    lockScreenViewModel.lock()
                }
                if newPhase == .background {
                    // Drain the chat store's write-behind queue so a suspension
                    // can't strand a persisted turn in memory (spec 029 R3).
                    LocalChatStore.shared.flush()
                }
                if newPhase == .active && appState.hasCompletedOnboarding {
                    // Update activity timestamp when app becomes active
                    SecurityService.shared.updateActivityTimestamp()
                }
            }
        }
    }
}
