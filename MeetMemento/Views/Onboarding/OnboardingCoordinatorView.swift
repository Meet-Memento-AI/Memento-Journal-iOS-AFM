//
//  OnboardingCoordinatorView.swift
//  MeetMemento
//
//  Coordinates navigation flow for onboarding steps (UI boilerplate).
//

import SwiftUI

// MARK: - Onboarding Routes
// Flow order: YourName → LearnAboutYourself → ThemeConfirmation → FaceID →
// (Use Face ID → SetupPin(backup) → ConfirmPin → Loading) or
// (Create PIN → SetupPin → ConfirmPin → Loading) or
// (Skip → Loading, spec 023 R3 — app lock defaults on but is skippable).

enum OnboardingRoute: Hashable {
    case yourName
    case learnAboutYourself
    case themeConfirmation
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
    @EnvironmentObject var appState: AppStateStore
    @ObservedObject var lockScreenViewModel: LockScreenViewModel
    @StateObject private var onboardingViewModel = OnboardingViewModel()
    @StateObject private var entryViewModel = EntryViewModel()

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
                .environmentObject(appState)

        case .learnAboutYourself:
            LearnAboutYourselfView(onComplete: { userInput in handleLearnAboutYourselfComplete(userInput) }, isFirstStep: false, onBack: { handleBack() })
                .environmentObject(appState)

        case .themeConfirmation:
            ThemeConfirmationView(
                onComplete: { themeIds, lens, suggested in
                    handleThemeConfirmationComplete(themeIds: themeIds, promptLens: lens, suggestedIds: suggested)
                },
                onBack: { handleBack() }
            )
            .environmentObject(appState)

        case .faceID:
            FaceIDView(
                onUseFaceID: { handleUseFaceID() },
                onCreatePIN: { handleCreatePIN() },
                onSkip: { handleSkipSecuritySetup() },
                isFirstStep: false,
                onBack: { handleBack() }
            )
            .environmentObject(appState)

        case .setupPin(let isFaceIDBackup):
            SetupPinView(
                isFaceIDBackup: isFaceIDBackup,
                onComplete: { pin in handleSetupPinComplete(pin, isFaceIDBackup: isFaceIDBackup) },
                onCancel: { handleBack() }
            )
            .environmentObject(appState)

        case .confirmPin(let originalPin, let isFaceIDBackup):
            ConfirmPinView(
                originalPin: originalPin,
                isFaceIDBackup: isFaceIDBackup,
                onComplete: { handleConfirmPinComplete() },
                onCancel: { handleBack() }
            )
            .environmentObject(appState)

        case .loading:
            LoadingStateView {
                handleOnboardingComplete()
            }
            .environmentObject(appState)
        }
    }

    // MARK: - Initial View Logic

    @ViewBuilder
    private var initialView: some View {
        // Always start onboarding at YourNameView
        YourNameView(onComplete: { handleYourNameComplete() }, isFirstStep: true, onBack: { handleBackToWelcome() })
            .environmentObject(appState)
    }

    // MARK: - Navigation Handlers

    private func handleYourNameComplete() {
        Task {
            do {
                try await onboardingViewModel.saveProfileData()
                appState.setDisplayName(firstName: onboardingViewModel.firstName, lastName: onboardingViewModel.lastName)
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
                navigationPath.append(OnboardingRoute.themeConfirmation)
            } catch {
                AppLogger.log("⚠️ Failed to save personalization: \(error)")
                saveErrorMessage = "Failed to save your preferences. Please try again."
                showSaveError = true
            }
        }
    }

    private func handleThemeConfirmationComplete(themeIds: [String], promptLens: String?, suggestedIds: [String]) {
        Task {
            do {
                try await onboardingViewModel.saveExperienceProfile(
                    themeIds: themeIds,
                    promptLens: promptLens,
                    suggestedIds: suggestedIds
                )
                navigationPath.append(OnboardingRoute.faceID)
            } catch {
                AppLogger.log("⚠️ Failed to save experience profile: \(error)")
                saveErrorMessage = "Failed to save your themes. Please try again."
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
            entryViewModel.setSessionPIN(pin)
        }
        finishSecuritySetup()
    }

    /// Skip lock setup (spec 023 R3). No lock screen will ever show
    /// (`SecurityMode.none`), but entries must still be encrypted at rest —
    /// so a random PIN is generated and stored silently in the Keychain,
    /// used only as encryption key material, never as an unlock gate. See
    /// `ContentView`'s launch task for how this silent PIN reaches
    /// `EntryViewModel` on later app launches (there's no lock screen to
    /// post `.didUnlockWithPIN` for it).
    private func handleSkipSecuritySetup() {
        let silentPIN = UUID().uuidString
        let saved = SecurityService.shared.savePIN(silentPIN)
        if !saved {
            AppLogger.log("⚠️ Failed to save silent PIN to Keychain for skipped lock setup")
        }
        SecurityService.shared.setSecurityMode(.none)
        entryViewModel.setSessionPIN(silentPIN)
        finishSecuritySetup()
    }

    private func handleBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    private func handleBackToWelcome() {
        // Signal to WelcomeView to skip intro animations
        appState.isReturningFromOnboarding = true
        appState.hasStartedOnboarding = false
    }

    private func finishSecuritySetup() {
        Task {
            if !onboardingViewModel.personalizationText.isEmpty {
                do {
                    try await onboardingViewModel.createFirstJournalEntry(
                        text: onboardingViewModel.personalizationText,
                        using: entryViewModel
                    )
                } catch {
                    AppLogger.log("⚠️ Failed to create first journal entry: \(error)")
                }
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
            } catch {
                AppLogger.log("⚠️ Failed to mark onboarding complete: \(error)")
            }
            await MainActor.run {
                // Skip lock screen on first launch after onboarding
                // User just set up security, no need to immediately prompt again
                lockScreenViewModel.skipNextLockScreen = true
                appState.completeOnboarding()
            }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding Flow") {
    OnboardingCoordinatorView(lockScreenViewModel: LockScreenViewModel())
        .environmentObject(AppStateStore())
}
