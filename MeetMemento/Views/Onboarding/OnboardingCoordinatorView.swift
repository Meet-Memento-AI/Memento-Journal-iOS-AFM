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

    /// Stack of steps. Forward = append (out left / in from right); back = pop (reverse).
    @State private var routeStack: [OnboardingRoute] = [.yourName]
    /// `true` while animating a forward push; `false` for back.
    @State private var isNavigatingForward = true
    /// After the first forward slide, YourName should not re-run its Welcome dissolve.
    @State private var hasLeftFirstStep = false
    @State private var hasLoadedState = false
    @State private var hasMetMinimumLoadTime = false
    @State private var showSaveError = false
    @State private var saveErrorMessage: String?

    /// Fast page turn between onboarding steps.
    private static let stepTransition = Animation.easeInOut(duration: 0.28)

    init(lockScreenViewModel: LockScreenViewModel) {
        self.lockScreenViewModel = lockScreenViewModel
    }

    private var currentRoute: OnboardingRoute {
        routeStack.last ?? .yourName
    }

    public var body: some View {
        Group {
            if !hasLoadedState || onboardingViewModel.isLoadingState || !hasMetMinimumLoadTime {
                LoadingView()
            } else {
                stepHost
            }
        }
        .environmentObject(onboardingViewModel)
        .useTheme()
        .useTypography()
        .task {
            if !hasLoadedState {
                // Coming from Welcome's white dissolve: skip the artificial 500ms
                // LoadingView so YourName can fade in on the white bridge.
                let fromWelcome = appState.isEnteringOnboardingFromWelcome
                if fromWelcome {
                    appState.isEnteringOnboardingFromWelcome = false
                    hasMetMinimumLoadTime = true
                }

                let minimumLoadTask = Task {
                    guard !fromWelcome else { return }
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
            Text(saveErrorMessage ?? "Something went wrong saving that. Please try again.")
        }
    }

    // MARK: - Step Host

    private var stepHost: some View {
        ZStack {
            // Full-bleed fill behind sliding pages; page scaffolds own their chrome.
            theme.background.ignoresSafeArea()

            destinationView(for: currentRoute)
                .id(routeIdentity(for: currentRoute))
                .transition(stepTransition(forForward: isNavigatingForward))
        }
        // Clip horizontal slide overflow only — do not ignore the safe area here.
        .clipShape(Rectangle())
    }

    /// Forward: completed step exits left; next enters from the right.
    /// Back: reverse edges.
    private func stepTransition(forForward forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private func routeIdentity(for route: OnboardingRoute) -> String {
        switch route {
        case .yourName: return "yourName"
        case .learnAboutYourself: return "learnAboutYourself"
        case .themeConfirmation: return "themeConfirmation"
        case .faceID: return "faceID"
        case .setupPin(let isFaceIDBackup): return "setupPin-\(isFaceIDBackup)"
        case .confirmPin(let originalPin, let isFaceIDBackup):
            return "confirmPin-\(isFaceIDBackup)-\(originalPin)"
        case .loading: return "loading"
        }
    }

    private func pushRoute(_ route: OnboardingRoute) {
        isNavigatingForward = true
        hasLeftFirstStep = true
        withAnimation(Self.stepTransition) {
            routeStack.append(route)
        }
    }

    private func popRoute() {
        guard routeStack.count > 1 else { return }
        isNavigatingForward = false
        withAnimation(Self.stepTransition) {
            _ = routeStack.removeLast()
        }
    }

    // MARK: - Destination View Builder

    @ViewBuilder
    private func destinationView(for route: OnboardingRoute) -> some View {
        switch route {
        case .yourName:
            YourNameView(
                onComplete: { handleYourNameComplete() },
                isFirstStep: true,
                onBack: { handleBackToWelcome() },
                dissolvesInOnAppear: !hasLeftFirstStep
            )
            .environmentObject(appState)

        case .learnAboutYourself:
            LearnAboutYourselfView(
                onComplete: { userInput in handleLearnAboutYourselfComplete(userInput) },
                isFirstStep: false,
                onBack: { handleBack() }
            )

        case .themeConfirmation:
            ThemeConfirmationView(
                onComplete: { outcome in
                    handleThemeConfirmationComplete(outcome)
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

    // MARK: - Navigation Handlers

    private func handleYourNameComplete() {
        // Slide to the next step immediately; persist in the background.
        appState.setDisplayName(firstName: onboardingViewModel.firstName, lastName: onboardingViewModel.lastName)
        pushRoute(.learnAboutYourself)
        Task {
            do {
                try await onboardingViewModel.saveProfileData()
            } catch {
                AppLogger.log("⚠️ Failed to save profile: \(error)")
                saveErrorMessage = "Failed to save your profile. Please try again."
                showSaveError = true
            }
        }
    }

    private func handleLearnAboutYourselfComplete(_ userInput: String) {
        onboardingViewModel.personalizationText = userInput
        pushRoute(.themeConfirmation)
        Task {
            do {
                try await onboardingViewModel.savePersonalizationText()
            } catch {
                AppLogger.log("⚠️ Failed to save personalization: \(error)")
                saveErrorMessage = "Failed to save your preferences. Please try again."
                showSaveError = true
            }
        }
    }

    private func handleThemeConfirmationComplete(_ outcome: ThemeSelectionOutcome) {
        pushRoute(.faceID)
        Task {
            do {
                try await onboardingViewModel.saveExperienceProfile(
                    themeIds: outcome.themeIds,
                    promptLens: outcome.promptLens,
                    suggestedIds: outcome.suggestedIds,
                    modelIdentifier: outcome.modelIdentifier,
                    promptVersion: outcome.promptVersion
                )
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
        pushRoute(.setupPin(isFaceIDBackup: true))
    }

    private func handleCreatePIN() {
        onboardingViewModel.useFaceID = false
        pushRoute(.setupPin(isFaceIDBackup: false))
    }

    private func handleSetupPinComplete(_ pin: String, isFaceIDBackup: Bool) {
        pushRoute(.confirmPin(originalPin: pin, isFaceIDBackup: isFaceIDBackup))
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
        popRoute()
    }

    private func handleBackToWelcome() {
        // Signal to WelcomeView to skip intro animations
        appState.isReturningFromOnboarding = true
        appState.hasStartedOnboarding = false
    }

    private func finishSecuritySetup() {
        // Move to the loading / finish screen right away; journal seed can follow.
        pushRoute(.loading)
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
