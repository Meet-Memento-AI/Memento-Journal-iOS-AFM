import XCTest
@testable import MeetMemento

/// Replaces AuthViewModelTests (spec 023 removes accounts; spec 011 R3
/// retargets this test's acceptance criteria to the local app-state machine).
/// `AppStateStore` has no network path at all now, so these tests exercise
/// the state transitions directly rather than mocking a session.
@MainActor
final class AppStateStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    private func clearPersistedState() {
        let defaults = UserDefaults.standard
        for key in [
            "memento_onboarding_completed", "memento_first_name", "memento_last_name",
            "memento_local_user_id", "memento_migrated_from_account",
        ] {
            defaults.removeObject(forKey: key)
        }
        SecurityService.shared.setSecurityMode(.none)
    }

    func test_freshInstall_resolvesToNotOnboarded() {
        let store = AppStateStore()
        XCTAssertFalse(store.hasCheckedAuth)

        store.initializeAppState()

        XCTAssertTrue(store.hasCheckedAuth)
        XCTAssertFalse(store.isInitializing)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func test_initializeAppState_underTest_resolvesWithoutNetwork() {
        // AppStateStore makes zero network calls by construction — this test
        // exists to keep that invariant explicit and regression-tested.
        let store = AppStateStore()
        store.initializeAppState()

        XCTAssertTrue(store.hasCheckedAuth)
    }

    func test_completeOnboarding_persistsLocally() {
        let store = AppStateStore()
        store.completeOnboarding()

        XCTAssertTrue(store.hasCompletedOnboarding)

        // A fresh instance reading the same UserDefaults should see it too —
        // this is the "existing users never see onboarding again" contract.
        let secondLaunch = AppStateStore()
        secondLaunch.initializeAppState()
        XCTAssertTrue(secondLaunch.hasCompletedOnboarding)
    }

    func test_setDisplayName_persistsLocally() {
        let store = AppStateStore()
        store.setDisplayName(firstName: "Ada", lastName: "Lovelace")

        XCTAssertEqual(store.firstName, "Ada")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "memento_first_name"), "Ada")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "memento_last_name"), "Lovelace")
    }

    func test_localUserID_isStableAcrossReads() {
        let first = AppStateStore.localUserID
        let second = AppStateStore.localUserID
        XCTAssertEqual(first, second)
    }

    func test_deleteEverything_resetsOnboardingAndName() {
        let store = AppStateStore()
        store.completeOnboarding()
        store.setDisplayName(firstName: "Ada", lastName: "Lovelace")

        store.deleteEverything()

        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertNil(store.firstName)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "memento_onboarding_completed"))
    }

    /// Regression: chat transcripts used to survive "Delete Everything". They
    /// live under Application Support, outside both LocalJournalStorage and
    /// UserDefaults, and every stored assistant message carries verbatim entry
    /// excerpts in its `sources[].preview` — so leaving them behind contradicted
    /// the confirmation copy and left journal content on disk.
    func test_deleteEverything_removesChatTranscripts() throws {
        let sessionId = UUID()
        let store = LocalChatStore.shared
        store.upsertSession(id: sessionId, title: "How was my week?")
        store.appendMessage(role: "user", content: "How was my week?", to: sessionId)
        store.appendMessage(
            role: "assistant",
            content: ChatService.assistantContentJSON(
                body: "You wrote about the move.",
                heading1: nil,
                heading2: nil,
                sources: [ChatSource(id: UUID().uuidString,
                                     createdAt: "2026-08-01T00:00:00Z",
                                     preview: "verbatim journal excerpt")]
            ),
            to: sessionId
        )

        XCTAssertFalse(store.sessions().isEmpty, "precondition: a transcript exists")
        XCTAssertFalse(store.messages(for: sessionId).isEmpty)

        AppStateStore().deleteEverything()

        XCTAssertTrue(store.sessions().isEmpty, "transcripts must not survive Delete Everything")
        XCTAssertTrue(store.messages(for: sessionId).isEmpty, "message bodies carry journal excerpts")
    }

    func test_bypassToMainApp_setsOnboardedWithoutNetwork() {
        let store = AppStateStore()
        store.bypassToMainApp()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertTrue(store.hasCheckedAuth)
    }

    func test_skipToOnboardingForTesting_startsOnboardingFlow() {
        let store = AppStateStore()
        store.skipToOnboardingForTesting()

        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertTrue(store.hasStartedOnboarding)
    }

    func test_migrateFromPriorAccountIfNeeded_freshInstall_staysNotOnboarded() {
        let store = AppStateStore()
        store.initializeAppState() // runs migration internally

        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func test_migrateFromPriorAccountIfNeeded_existingUserEvidence_completesOnboarding() {
        // Simulate local evidence a pre-023 install already left behind: a
        // cached display name (written by the old AuthViewModel/onboarding)
        // with no local onboarding-complete flag yet (that flag didn't exist
        // before this update).
        UserDefaults.standard.set("Ada", forKey: "memento_first_name")
        UserDefaults.standard.set("Lovelace", forKey: "memento_last_name")
        SecurityService.shared.setSecurityMode(.pin)

        let store = AppStateStore()
        store.migrateFromPriorAccountIfNeeded()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.firstName, "Ada")
    }

    func test_migrateFromPriorAccountIfNeeded_isIdempotent() {
        UserDefaults.standard.set("Ada", forKey: "memento_first_name")
        SecurityService.shared.setSecurityMode(.pin)

        let store = AppStateStore()
        store.migrateFromPriorAccountIfNeeded()
        store.deleteEverything() // simulate the user deleting everything post-migration
        store.migrateFromPriorAccountIfNeeded() // must not re-migrate and undo the deletion

        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func test_resetToFreshInstall_isIdempotent() {
        let store = AppStateStore()
        store.resetToFreshInstall(reason: "first")
        store.resetToFreshInstall(reason: "second")

        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertTrue(store.hasCheckedAuth)
    }
}
