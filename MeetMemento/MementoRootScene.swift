//
//  MementoRootScene.swift
//  MeetMemento
//
//  App scene, extracted from `@main` so a future journal-only flavor can wrap
//  the same tree. Reserved: MEMENTO_AI currently always on for MeetMemento.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Root Background
/// A background view that matches the app's theme and extends to all screen edges
private struct RootBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Use theme background colors from design tokens
        (colorScheme == .dark ? BaseColors.black : BaseColors.white)
            .ignoresSafeArea()
    }
}

struct MementoRootScene: Scene {
    @StateObject private var appState = AppStateStore()
    @StateObject private var lockScreenViewModel = LockScreenViewModel()
    @StateObject private var navigationState = AppNavigationState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Opaque canvas so iOS 26 Liquid Glass cannot sample the wallpaper
        // through a clear window and tint Journal/Chat off-white.
        UIWindow.appearance().backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
                : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
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
                                .environmentObject(navigationState)
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
                #if MEMENTO_AI
                FeedbackSyncService.shared.resumePendingWork()
                #endif
            }
            .onChange(of: appState.hasCompletedOnboarding) { _, completed in
                // Consume skip flag when transitioning from onboarding to main app
                if completed {
                    lockScreenViewModel.consumeSkipNextLockScreen()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Lock only when the scene actually leaves the foreground.
                // `.inactive` also fires for every system sheet the app itself
                // raises — permission prompts, Face ID, the photo picker,
                // Control Center — and locking on it tears ContentView (and any
                // pushed editor) out from under that sheet.
                if newPhase == .background {
                    lockScreenViewModel.lock()
                    // Drain the chat store's write-behind queue so a suspension
                    // can't strand a persisted turn in memory (spec 029 R3).
                    #if MEMENTO_AI
                    LocalChatStore.shared.flush()
                    FeedbackSyncService.shared.resumePendingWork()
                    #endif
                }
                if newPhase == .active && appState.hasCompletedOnboarding {
                    // Update activity timestamp when app becomes active
                    SecurityService.shared.updateActivityTimestamp()
                    #if MEMENTO_AI
                    FeedbackSyncService.shared.resumePendingWork()
                    #endif
                }
            }
        }
        .modelContainer(JournalContainer.make())
    }
}
