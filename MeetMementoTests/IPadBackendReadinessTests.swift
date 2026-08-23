import SwiftData
import XCTest
@testable import MeetMemento

@MainActor
final class IPadBackendReadinessTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = JournalContainer.makeInMemory()
        JournalContainer.resetCacheForTests(to: container)
        MementoDataStore.clearImportFlag()
        LocalJournalStorage.shared.clearAll()
        LocalChatStore.shared.clear()
        FiveStoreDeletion.lastCloudKitOutcome = nil
        UserDefaults.standard.removeObject(forKey: "memento_cloudkit_deletion_pending")
    }

    override func tearDown() {
        MementoDataStore.clearImportFlag()
        LocalJournalStorage.shared.clearAll()
        LocalChatStore.shared.clear()
        JournalContainer.resetCacheForTests(to: nil)
        container = nil
        super.tearDown()
    }

    // MARK: - Persist across a new ModelContext

    func test_entryPersistsAcrossNewModelContext() {
        let id = UUID()
        MementoDataStore.upsertEntry(
            id: id,
            title: "Morning",
            transcript: "Wrote on this device",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            hasPhoto: false,
            container: container
        )

        let fetched = MementoDataStore.entry(id: id, container: container)
        XCTAssertEqual(fetched?.title, "Morning")
        XCTAssertEqual(fetched?.text, "Wrote on this device")
        XCTAssertEqual(MementoDataStore.entryCount(container: container), 1)

        MementoDataStore.deleteEntry(id: id, container: container)
        XCTAssertNil(MementoDataStore.entry(id: id, container: container))
        XCTAssertEqual(MementoDataStore.entryCount(container: container), 0)
    }

    func test_conversationPersistsAcrossNewModelContext() {
        let id = UUID()
        MementoDataStore.upsertConversation(id: id, title: "Hello", container: container)
        MementoDataStore.appendTurn(
            conversationId: id,
            role: "user",
            text: "hi",
            container: container
        )
        MementoDataStore.appendTurn(
            conversationId: id,
            role: "assistant",
            text: "hello",
            container: container
        )

        let sessions = MementoDataStore.conversations(container: container)
        XCTAssertEqual(sessions.first?.id, id)
        XCTAssertEqual(sessions.first?.title, "Hello")
        let turns = MementoDataStore.turns(conversationId: id, container: container)
        XCTAssertEqual(turns.map(\.role), ["user", "assistant"])
        XCTAssertEqual(turns.map(\.content), ["hi", "hello"])
    }

    func test_profilePersistsAsStoredProfile() {
        MementoDataStore.upsertProfile(
            firstName: "Ada",
            lastName: "Lovelace",
            personalizationText: "I journal to notice patterns",
            experience: nil,
            aiEnabled: true,
            processOnDeviceOnly: false,
            container: container
        )
        let row = MementoDataStore.loadProfile(container: container)
        XCTAssertEqual(row?.firstName, "Ada")
        XCTAssertEqual(row?.lastName, "Lovelace")
        XCTAssertEqual(row?.personalizationText, "I journal to notice patterns")
        XCTAssertTrue(row?.aiEnabled ?? false)
    }

    // MARK: - Legacy import

    func test_importFixtures_preservesUUIDs_andSecondRunIsNoOp() {
        let encryption = EncryptionService(keychain: InMemoryKeychainStore())
        let service = JournalService(encryptionService: encryption)
        let entryId = UUID()
        let created = Date(timeIntervalSince1970: 1_710_000_000)
        XCTAssertTrue(service.saveEntryLocally(
            entryId: entryId,
            title: "Imported",
            content: "From EncryptedJournals",
            createdAt: created,
            updatedAt: created
        ))
        XCTAssertGreaterThan(LocalJournalStorage.shared.storedEntryCount, 0)

        let sessionId = UUID()
        LocalChatStore.shared.upsertSession(id: sessionId, title: "Prior chat")
        LocalChatStore.shared.appendMessage(role: "user", content: "hello there", to: sessionId)

        XCTAssertFalse(MementoDataStore.hasCompletedLegacyImport)
        XCTAssertTrue(LegacyStoreImporter.importIfNeeded(
            encryptionService: encryption,
            container: container
        ))
        XCTAssertTrue(MementoDataStore.hasCompletedLegacyImport)

        let imported = MementoDataStore.entry(id: entryId, container: container)
        XCTAssertEqual(imported?.id, entryId)
        XCTAssertEqual(imported?.title, "Imported")
        XCTAssertEqual(imported?.text, "From EncryptedJournals")
        XCTAssertEqual(LocalJournalStorage.shared.storedEntryCount, 0)

        let chats = MementoDataStore.conversations(container: container)
        XCTAssertTrue(chats.contains { $0.id == sessionId })
        XCTAssertEqual(
            MementoDataStore.turns(conversationId: sessionId, container: container).first?.content,
            "hello there"
        )

        XCTAssertFalse(LegacyStoreImporter.importIfNeeded(
            encryptionService: encryption,
            container: container
        ))
    }

    func test_saveAfterImport_doesNotWriteLegacyFiles() {
        MementoDataStore.markLegacyImportComplete()
        let encryption = EncryptionService(keychain: InMemoryKeychainStore())
        let service = JournalService(encryptionService: encryption)
        let entryId = UUID()
        XCTAssertTrue(service.saveEntryLocally(
            entryId: entryId,
            title: "Fresh",
            content: "SwiftData only",
            createdAt: Date(),
            updatedAt: Date()
        ))
        XCTAssertEqual(LocalJournalStorage.shared.storedEntryCount, 0)
        XCTAssertEqual(MementoDataStore.entry(id: entryId, container: container)?.text, "SwiftData only")
    }

    // MARK: - Five-store deletion

    func test_fiveStoreDeletion_emptiesSwiftDataIncludingProfile() async {
        MementoDataStore.upsertEntry(
            id: UUID(),
            title: "Gone",
            transcript: "wipe me",
            createdAt: Date(),
            updatedAt: Date(),
            hasPhoto: false,
            container: container
        )
        MementoDataStore.upsertProfile(
            firstName: "Ada",
            lastName: "L",
            personalizationText: "x",
            experience: nil,
            aiEnabled: true,
            processOnDeviceOnly: false,
            container: container
        )
        MementoDataStore.markLegacyImportComplete()

        await FiveStoreDeletion.run(container: container)

        XCTAssertEqual(MementoDataStore.entryCount(container: container), 0)
        XCTAssertNil(MementoDataStore.loadProfile(container: container))
        XCTAssertFalse(MementoDataStore.hasCompletedLegacyImport)
        XCTAssertNotNil(FiveStoreDeletion.lastCloudKitOutcome)
        XCTAssertTrue(
            FiveStoreDeletion.lastCloudKitOutcome == .issued
                || FiveStoreDeletion.lastCloudKitOutcome == .queuedPending
                || FiveStoreDeletion.lastCloudKitOutcome == .skippedNoAccount
        )
    }

    // MARK: - Selection contracts

    func test_entryRouteEditUsesUUID() {
        let id = UUID()
        let route = EntryRoute.edit(id)
        XCTAssertEqual(route.id, "edit-\(id)")
        XCTAssertEqual(route.zoomSourceID, "edit-\(id.uuidString)")
    }

    func test_selectedEntryIdAndLookup() {
        let id = UUID()
        MementoDataStore.upsertEntry(
            id: id,
            title: "Selected",
            transcript: "body",
            createdAt: Date(),
            updatedAt: Date(),
            hasPhoto: false,
            container: container
        )
        let viewModel = EntryViewModel()
        viewModel.selectedEntryId = id
        XCTAssertEqual(viewModel.selectedEntryId, id)
        XCTAssertEqual(viewModel.entry(id: id)?.title, "Selected")
    }

    func test_currentSessionIdAndNavigationState() {
        let sessionId = UUID()
        let chat = ChatViewModel()
        chat.currentSessionId = sessionId
        XCTAssertEqual(chat.currentSessionId, sessionId)

        let navigation = AppNavigationState()
        navigation.primarySection = .chat
        XCTAssertEqual(navigation.primarySection, .chat)
    }

    func test_deviceCopyIsDeviceNeutral() {
        XCTAssertFalse(DeviceCopy.signedOutSync.contains("nothing leaves"))
        XCTAssertTrue(
            DeviceCopy.signedOutSync.contains("this iPhone")
                || DeviceCopy.signedOutSync.contains("this iPad")
                || DeviceCopy.signedOutSync.contains("this device")
        )
    }
}
