//
//  AppStateStore.swift
//  MeetMemento
//
//  Local, account-free app state. Replaces the old auth view model (spec 023 R1).
//  No network calls, no auth, no accounts. Onboarding-complete is a local
//  UserDefaults flag; identity is a locally stored display name.
//

import Foundation
import SwiftUI

@MainActor
class AppStateStore: ObservableObject {
    private static let onboardingCompleteKey = "memento_onboarding_completed"
    private static let firstNameKey = "memento_first_name"
    private static let lastNameKey = "memento_last_name"
    private static let localUserIDKey = "memento_local_user_id"
    /// Set on first post-update launch when a prior account session was found and
    /// migrated (spec 023 R5). Informational only; nothing currently reads it besides
    /// the migration path itself, kept for support/debugging visibility.
    private static let migratedFromAccountKey = "memento_migrated_from_account"

    @Published var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AppStateStore.onboardingCompleteKey)

    /// True once local state has been loaded. Root UI waits on this the same way it
    /// used to wait on session restore — except this resolves near-instantly since
    /// it's just a UserDefaults read, not a network round trip.
    @Published var hasCheckedAuth = false

    @Published var isInitializing = true

    /// True once the user has tapped "Get Started" on Welcome, moving the root
    /// view into the onboarding flow. Not persisted: if the app is killed
    /// mid-onboarding, the next launch shows Welcome again, and onboarding
    /// resumes from whatever was already saved locally.
    @Published var hasStartedOnboarding = false

    /// Set to true when the user navigates back from onboarding to Welcome.
    /// WelcomeView uses this to skip intro animations and show content immediately.
    @Published var isReturningFromOnboarding = false

    /// One-shot: Welcome set this after dissolving to white, just before flipping
    /// `hasStartedOnboarding`. OnboardingCoordinator consumes it to skip the
    /// LoadingView minimum delay so YourName can dissolve in on the white bridge.
    /// Not persisted.
    @Published var isEnteringOnboardingFromWelcome = false

    /// Locally stored display name (set during onboarding / profile edits).
    @Published var firstName: String? = UserDefaults.standard.string(forKey: AppStateStore.firstNameKey)

    private var isRunningAnyTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// A stable, anonymous, device-local identifier. Not an account id — nothing
    /// authenticates it, nothing verifies it, it exists only so entry/profile
    /// records have a UUID to key off of until spec 015's SwiftData layer removes
    /// the need entirely. Generated once and persisted.
    static var localUserID: UUID {
        if let existing = UserDefaults.standard.string(forKey: localUserIDKey),
           let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let generated = UUID()
        UserDefaults.standard.set(generated.uuidString, forKey: localUserIDKey)
        return generated
    }

    /// Loads local state on launch. No network calls, ever.
    func initializeAppState() {
        defer {
            self.isInitializing = false
            self.hasCheckedAuth = true
        }

        // UI tests want a deterministic "always start from Welcome" state,
        // driven by an explicit opt-in launch argument — unlike the old
        // auth view model, this isn't about skipping a network bootstrap
        // (there is none), just about UI test determinism.
        let isUiTestRun =
            ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.environment["MEETMEMENTO_UI_TEST"] == "1"

        // R5 upgrade-fixture exit criteria: verified through a real app
        // launch (not just a direct method call in a unit test), a second
        // opt-in flag lets a UI test seed pre-023 local evidence (cached
        // name + configured PIN lock) before this method's normal local-load
        // + migration path runs, then assert the launch lands directly on
        // Journal. Double-gated on -UITesting so it can never fire outside
        // an explicit UI test launch.
        let shouldSeedUpgradeFixture = isUiTestRun
            && ProcessInfo.processInfo.arguments.contains("-SeedUpgradeFixture")
        if shouldSeedUpgradeFixture {
            seedUpgradeFixture()
        }

        if isUiTestRun && !shouldSeedUpgradeFixture {
            self.hasCompletedOnboarding = false
            return
        }

        // Unit tests: skip device-touching side effects (Keychain-backed
        // inactivity check) but still read real persisted state — there's no
        // network call left to protect against, and tests that verify
        // persistence (e.g. completeOnboarding) depend on this reading
        // truthfully.
        if !isRunningAnyTest {
            // 14-day inactivity auto-lock still applies (device-local, unrelated to accounts).
            if SecurityService.shared.shouldAutoLogout() {
                AppLogger.log("[AppState] Auto-lock triggered: 14+ days of inactivity")
                SecurityService.shared.clearActivityTimestamp()
                // Inactivity no longer signs anyone out (there's no account); it
                // simply re-locks the app. The lock screen (if configured) handles the rest.
            }
            SecurityService.shared.updateActivityTimestamp()
        }

        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingCompleteKey)
        self.firstName = UserDefaults.standard.string(forKey: Self.firstNameKey)

        migrateFromPriorAccountIfNeeded()

        AppLogger.log("[AppState] Local state loaded, onboarded: \(hasCompletedOnboarding)")
    }

    /// Writes pre-023 local evidence (cached name + configured PIN lock, no
    /// onboarding-complete flag) so the very next line of `initializeAppState()`
    /// exercises `migrateFromPriorAccountIfNeeded()` against realistic upgrade
    /// state instead of a fresh install. See `shouldSeedUpgradeFixture` above.
    private func seedUpgradeFixture() {
        UserDefaults.standard.set("Ada", forKey: Self.firstNameKey)
        UserDefaults.standard.set("Lovelace", forKey: Self.lastNameKey)
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey)
        UserDefaults.standard.removeObject(forKey: Self.migratedFromAccountKey)
        _ = SecurityService.shared.savePIN("4829")
        SecurityService.shared.setSecurityMode(.pin)
    }

    /// Marks onboarding complete locally.
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        hasCompletedOnboarding = true
    }

    func setDisplayName(firstName: String, lastName: String) {
        UserDefaults.standard.set(firstName, forKey: Self.firstNameKey)
        UserDefaults.standard.set(lastName, forKey: Self.lastNameKey)
        self.firstName = firstName
    }

    /// Existing-user migration (spec 023 R5), run once on first post-update
    /// launch. Deliberately makes this decision from **local evidence only**
    /// — no network call, no remote session check. The account layer is
    /// gone; what matters is whether *this device* already completed
    /// onboarding under the old account-based app, which is fully
    /// determinable from data that was already being cached locally before
    /// this update (the display name, per the pre-023 auth view model, and
    /// either a configured lock method or locally stored entries).
    ///
    /// This does not cover the case of a user whose entries exist only on
    /// the old server and were never opened locally on this device —
    /// per `REQ-MIG-001`, that requires a one-time server pull while a
    /// session is still valid, scoped to spec 015, and gated on confirming
    /// the real user count is non-zero (spec 013 R5, a user action — not yet
    /// confirmed as of this writing).
    func migrateFromPriorAccountIfNeeded() {
        // Already migrated, or already onboarded on this device — nothing to do.
        guard !hasCompletedOnboarding,
              UserDefaults.standard.object(forKey: Self.migratedFromAccountKey) == nil else {
            return
        }
        UserDefaults.standard.set(true, forKey: Self.migratedFromAccountKey)

        let hasCachedName = !(UserDefaults.standard.string(forKey: Self.firstNameKey) ?? "").isEmpty
        let hasSecuritySetup = SecurityService.shared.currentMode != .none
        let hasLocalEntries = LocalJournalStorage.shared.storedEntryCount > 0

        guard hasCachedName, hasSecuritySetup || hasLocalEntries else {
            // No local evidence of a prior completed setup — fresh install,
            // not a migration.
            return
        }

        AppLogger.log("[AppState] Migrated existing user from prior account-based install (local evidence: name cached, security=\(hasSecuritySetup), entries=\(hasLocalEntries))")
        completeOnboarding()
        firstName = UserDefaults.standard.string(forKey: Self.firstNameKey)
    }

    /// "Delete everything" (spec 023 R4). Interim scope: local entry storage +
    /// security/encryption Keychain entries + chat transcripts + UserDefaults +
    /// content-derived caches. Spec 015 extends this to the full five-store
    /// deletion (SwiftData, Spotlight index, TTS cache, CloudKit) per
    /// `REQ-DATA-013`.
    func deleteEverything() {
        SecurityService.shared.clearAll()
        LocalJournalStorage.shared.clearAll()
        // Destroy the key material too, after the files are gone. Previously the
        // encryption salt survived Delete Everything; now that a long-lived data
        // key exists, leaving it behind would mean "delete everything" left the
        // means to read anything restored from a backup.
        EncryptionService.shared.clearAll()
        LocalProfileStore.clearAll()
        // Chat transcripts are journal content: every stored assistant message
        // carries verbatim entry excerpts in its `sources[].preview`. They live
        // under Application Support, outside LocalJournalStorage and outside
        // UserDefaults, so nothing above reaches them — leaving them behind
        // contradicted the confirmation copy ("permanently delete every journal
        // entry") outright. Called synchronously rather than through
        // `ChatService.clearHistory()` so deletion stays deterministic: a
        // fire-and-forget Task in an erasure path can outlive the call.
        LocalChatStore.shared.clear()
        // Cached entry embedding vectors are content-derived (CONSTITUTION §4
        // rule 8), so they go too — both the in-process cache and the
        // persisted vector files under Application Support (spec 029 R8).
        EmbeddingService.shared.clearCache()
        UserDefaults.standard.removeObject(forKey: Self.firstNameKey)
        UserDefaults.standard.removeObject(forKey: Self.lastNameKey)
        UserDefaults.standard.removeObject(forKey: Self.onboardingCompleteKey)
        UserDefaults.standard.removeObject(forKey: Self.localUserIDKey)
        // Two keys that previously survived an erasure path called "Delete
        // Everything". Neither gates onboarding and neither caused a visible
        // bug — deletion was already correct — but leaving them behind
        // contradicts the confirmation copy.
        //
        // `migratedFromAccountKey` marks the pre-023 migration as done; a stale
        // `true` would suppress re-migration for a user who later restored old
        // local evidence. Clearing it is safe: the next launch re-runs
        // `migrateFromPriorAccountIfNeeded()`, finds no cached name, and
        // returns without completing onboarding. `memento_sample_entry_ids`
        // holds UUIDs of sample entries whose files have just been deleted.
        UserDefaults.standard.removeObject(forKey: Self.migratedFromAccountKey)
        UserDefaults.standard.removeObject(forKey: SampleContentService.seededIdsDefaultsKey)
        PreferencesService.shared.resetToDefaults()
        WeeklyReflectionStore.clear()
        AudioAssetStore.deleteAll()
        TTSRenderCache.deleteAll()
        Task { await FiveStoreDeletion.run() }

        firstName = nil
        hasCompletedOnboarding = false
        hasStartedOnboarding = false
    }

    /// Resets to the fresh-install state (used by launch failsafes if local state
    /// loading somehow stalls, and by tests). No network involved, so this should
    /// never actually be needed in practice — kept as a defensive fallback.
    func resetToFreshInstall(reason: String) {
        AppLogger.log("[AppState] Resetting to fresh install: \(reason)")
        hasCompletedOnboarding = false
        hasStartedOnboarding = false
        hasCheckedAuth = true
        isInitializing = false
    }

    /// Bypass local state for development/testing purposes.
    func bypassToMainApp() {
        hasCompletedOnboarding = true
        hasCheckedAuth = true
        isInitializing = false
    }

    /// Skip to onboarding flow for UI testing.
    func skipToOnboardingForTesting() {
        hasCompletedOnboarding = false
        hasStartedOnboarding = true
        hasCheckedAuth = true
        isInitializing = false
    }
}

extension AppStateStore {
    /// SwiftUI previews for screens that expect `initializeAppState()` to have
    /// finished without running it.
    static func previewReadyForWelcome() -> AppStateStore {
        let store = AppStateStore()
        store.hasCheckedAuth = true
        store.isInitializing = false
        return store
    }
}
