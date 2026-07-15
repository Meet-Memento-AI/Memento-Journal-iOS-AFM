//
//  OnboardingCoordinatorView.swift
//  MeetMemento
//
//  Coordinates navigation flow for onboarding steps (UI boilerplate).
//

import SwiftUI

// MARK: - Onboarding Routes
// Create Account flow order: YourName → LearnAboutYourself → YourGoals → FaceID → (Use Face ID → Loading) or (SetupPin → ConfirmPin → Loading).

enum OnboardingRoute: Hashable {
    case yourName
    case learnAboutYourself
    case yourGoals
    case faceID
    case setupPin(isFaceIDBackup: Bool)
    case confirmPin(originalPin: String, isFaceIDBackup: Bool)
    case loading
}

// MARK: - Onboarding Coordinator View

@MainActor
public struct OnboardingCoordinatorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject var lockScreenViewModel: LockScreenViewModel
    @StateObject private var onboardingViewModel = OnboardingViewModel()

    @State private var navigationPath = NavigationPath()
    @State private var hasLoadedState = false
    @State private var hasMetMinimumLoadTime = false
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?

    init(lockScreenViewModel: LockScreenViewModel) {
        self.lockScreenViewModel = lockScreenViewModel
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !hasLoadedState || onboardingViewModel.isLoadingState || !hasMetMinimumLoadTime {
                    LoadingView()
                } else {
                    initialView
                }
            }
            .navigationDestination(for: OnboardingRoute.self) { route in
                destinationView(for: route)
            }
        }
        .environmentObject(onboardingViewModel)
        .useTheme()
        .useTypography()
        .task {
            if !hasLoadedState {
                let minimumLoadTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        hasMetMinimumLoadTime = true
                    }
                }

                await onboardingViewModel.loadCurrentState()
                hasLoadedState = true
                await minimumLoadTask.value
            }
        }
        .alert("Unable to Save", isPresented: $showSaveError) {
            Button("Try Again") {
                // User can retry by tapping continue again
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Please check your connection and try again.")
        }
    }

    // MARK: - Destination View Builder

    @ViewBuilder
    private func destinationView(for route: OnboardingRoute) -> some View {
        switch route {
        case .yourName:
            // When YourNameView is navigated to (not initial), back should go to WelcomeView
            YourNameView(onComplete: { handleYourNameComplete() }, isFirstStep: false, onBack: { handleBackToWelcome() })
                .environmentObject(authViewModel)

        case .learnAboutYourself:
            LearnAboutYourselfView(onComplete: { userInput in handleLearnAboutYourselfComplete(userInput) }, isFirstStep: false, onBack: { handleBack() })
                .environmentObject(authViewModel)

        case .yourGoals:
            YourGoalsView(onComplete: { handleYourGoalsComplete() }, isFirstStep: false, onBack: { handleBack() })
                .environmentObject(authViewModel)

        case .faceID:
            FaceIDView(
                onUseFaceID: { handleUseFaceID() },
                onCreatePIN: { handleCreatePIN() },
                isFirstStep: false,
                onBack: { handleBack() }
            )
            .environmentObject(authViewModel)

        case .setupPin(let isFaceIDBackup):
            SetupPinView(
                isFaceIDBackup: isFaceIDBackup,
                onComplete: { pin in handleSetupPinComplete(pin, isFaceIDBackup: isFaceIDBackup) },
                onCancel: { handleBack() }
            )
            .environmentObject(authViewModel)

        case .confirmPin(let originalPin, let isFaceIDBackup):
            ConfirmPinView(
                originalPin: originalPin,
                isFaceIDBackup: isFaceIDBackup,
                onComplete: { handleConfirmPinComplete() },
                onCancel: { handleBack() }
            )
            .environmentObject(authViewModel)

        case .loading:
            LoadingStateView {
                handleOnboardingComplete()
            }
            .environmentObject(authViewModel)
        }
    }

    // MARK: - Initial View Logic

    @ViewBuilder
    private var initialView: some View {
        // Always start onboarding at YourNameView
        // Pre-filled data from OAuth will show, user can confirm/edit
        // This ensures proper forward navigation and natural back animations
        YourNameView(onComplete: { handleYourNameComplete() }, isFirstStep: true, onBack: { handleBackToWelcome() })
            .environmentObject(authViewModel)
    }

    // MARK: - Navigation Handlers

    private func handleYourNameComplete() {
        Task {
            do {
                try await onboardingViewModel.saveProfileData()
                UserDefaults.standard.set(onboardingViewModel.firstName, forKey: "memento_first_name")
                UserDefaults.standard.set(onboardingViewModel.lastName, forKey: "memento_last_name")
                authViewModel.firstName = onboardingViewModel.firstName
                navigationPath.append(OnboardingRoute.learnAboutYourself)
            } catch {
                AppLogger.log("⚠️ Failed to save profile: \(error)")
                saveErrorMessage = "Failed to save your profile. Please try again."
                showSaveError = true
            }
        }
    }

    private func handleLearnAboutYourselfComplete(_ userInput: String) {
        onboardingViewModel.personalizationText = userInput
        Task {
            do {
                try await onboardingViewModel.savePersonalizationText()
                navigationPath.append(OnboardingRoute.yourGoals)
            } catch {
                AppLogger.log("⚠️ Failed to save personalization: \(error)")
                saveErrorMessage = "Failed to save your preferences. Please try again."
                showSaveError = true
            }
        }
    }

    private func handleYourGoalsComplete() {
        Task {
            do {
                try await onboardingViewModel.saveGoals()
                navigationPath.append(OnboardingRoute.faceID)
            } catch {
                AppLogger.log("⚠️ Failed to save goals: \(error)")
                saveErrorMessage = "Failed to save your goals. Please try again."
                showSaveError = true
            }
        }
    }

    private func handleUseFaceID() {
        // FaceID was already verified in FaceIDView
        // Now navigate to PIN setup (required for all users as backup + encryption)
        onboardingViewModel.useFaceID = true
        SecurityService.shared.setSecurityMode(.faceID)
        navigationPath.append(OnboardingRoute.setupPin(isFaceIDBackup: true))
    }

    private func handleCreatePIN() {
        onboardingViewModel.useFaceID = false
        navigationPath.append(OnboardingRoute.setupPin(isFaceIDBackup: false))
    }

    private func handleSetupPinComplete(_ pin: String, isFaceIDBackup: Bool) {
        navigationPath.append(OnboardingRoute.confirmPin(originalPin: pin, isFaceIDBackup: isFaceIDBackup))
    }

    private func handleConfirmPinComplete() {
        // Store confirmed PIN in Keychain
        let pin = onboardingViewModel.confirmedPin
        if !pin.isEmpty {
            let saved = SecurityService.shared.savePIN(pin)
            if !saved {
                // Log error but continue - security mode will still be set
                // User can reset PIN later if needed
                AppLogger.log("⚠️ Failed to save PIN to Keychain")
            }
            // Only set to PIN mode if user chose PIN-only (not FaceID backup)
            // FaceID users already have their mode set in handleUseFaceID()
            if !onboardingViewModel.useFaceID {
                SecurityService.shared.setSecurityMode(.pin)
            }
        }
        finishSecuritySetup()
    }

    private func handleBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    private func handleBackToWelcome() {
        // Signal to WelcomeView to skip intro animations
        authViewModel.isReturningFromOnboarding = true
        Task {
            await authViewModel.signOut()
        }
    }

    private func finishSecuritySetup() {
        Task {
            do {
                if !onboardingViewModel.personalizationText.isEmpty {
                    try await onboardingViewModel.createFirstJournalEntry(
                        text: onboardingViewModel.personalizationText
                    )
                }
            } catch {
                AppLogger.log("⚠️ Failed to create first journal entry: \(error)")
            }
            await MainActor.run {
                navigationPath.append(OnboardingRoute.loading)
            }
        }
    }

    private func handleOnboardingComplete() {
        Task {
            do {
                try await onboardingViewModel.completeOnboarding()
                await MainActor.run {
                    // Skip lock screen on first launch after onboarding
                    // User just set up security, no need to immediately prompt again
                    lockScreenViewModel.skipNextLockScreen = true
                    authViewModel.hasCompletedOnboarding = true
                    authViewModel.clearPendingProfile()
                }
            } catch {
                AppLogger.log("⚠️ Failed to mark onboarding complete: \(error)")
                await MainActor.run {
                    lockScreenViewModel.skipNextLockScreen = true
                    authViewModel.hasCompletedOnboarding = true
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding Flow") {
    OnboardingCoordinatorView(lockScreenViewModel: LockScreenViewModel())
        .environmentObject(AuthViewModel())
}
