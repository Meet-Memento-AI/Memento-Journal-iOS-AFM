import XCTest
@testable import MeetMemento

final class FeedbackVerificationTests: XCTestCase {

    private func sampleRow(
        source: AnswerFeedbackSource = .thumbsUp,
        rating: AnswerFeedbackRating = .positive,
        flagged: Bool = false,
        prompt: String = "How was Tuesday?",
        reply: String = "You wrote about eggs.",
        citation: UUID = UUID()
    ) -> AnswerFeedback {
        AnswerFeedback(
            messageID: UUID(),
            rating: rating,
            flaggedForReview: flagged,
            category: source == .thumbsUp ? nil : .wrongRecall,
            note: source == .thumbsUp ? nil : "Cited the wrong day",
            source: source,
            userPrompt: prompt,
            assistantReply: reply,
            citationEntryIDs: [citation],
            promptVersion: "ask@14",
            modelIdentifier: "on-device",
            zone: "z0Device"
        )
    }

    // MARK: - Consent / envelope redaction

    func test_consent_off_enqueuesNothing() {
        let envelope = FeedbackEnvelope.make(
            from: sampleRow(),
            deviceID: UUID(),
            includeTextForReview: true,
            shareWithDeveloper: false
        )
        XCTAssertNil(envelope)
    }

    func test_thumbs_metadata_omitsJournalText() throws {
        let envelope = try XCTUnwrap(FeedbackEnvelope.make(
            from: sampleRow(source: .thumbsDown, rating: .negative),
            deviceID: UUID(),
            includeTextForReview: true,
            shareWithDeveloper: true
        ))
        XCTAssertNil(envelope.userPrompt)
        XCTAssertNil(envelope.assistantReply)
        XCTAssertFalse(envelope.textIncluded)
        XCTAssertEqual(envelope.note, "Cited the wrong day")
        XCTAssertEqual(envelope.category, "wrongRecall")
        XCTAssertEqual(envelope.citationCount, 1)
        XCTAssertEqual(envelope.kind, "thumbs_down")
        let data = try JSONEncoder().encode(envelope)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("How was Tuesday?"))
        XCTAssertFalse(json.contains("You wrote about eggs."))
        XCTAssertFalse(json.contains("citationEntryIDs"))
    }

    func test_report_withoutIncludeText_omitsJournalText() throws {
        let envelope = try XCTUnwrap(FeedbackEnvelope.make(
            from: sampleRow(source: .report, rating: .none, flagged: true),
            deviceID: UUID(),
            includeTextForReview: false,
            shareWithDeveloper: true
        ))
        XCTAssertNil(envelope.userPrompt)
        XCTAssertNil(envelope.assistantReply)
        XCTAssertFalse(envelope.textIncluded)
        XCTAssertEqual(envelope.kind, "report")
    }

    func test_report_includeText_sendsPromptAndReply_notCitationIDs() throws {
        let citation = UUID()
        let envelope = try XCTUnwrap(FeedbackEnvelope.make(
            from: sampleRow(source: .report, rating: .none, flagged: true, citation: citation),
            deviceID: UUID(),
            includeTextForReview: true,
            shareWithDeveloper: true
        ))
        XCTAssertEqual(envelope.userPrompt, "How was Tuesday?")
        XCTAssertEqual(envelope.assistantReply, "You wrote about eggs.")
        XCTAssertTrue(envelope.textIncluded)
        XCTAssertEqual(envelope.citationCount, 1)
        let data = try JSONEncoder().encode(envelope)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(citation.uuidString))
        XCTAssertFalse(json.contains("citationEntryIDs"))
    }

    func test_config_fromBundle_missingKeys_isNil() {
        XCTAssertNil(FeedbackSupabaseConfig.fromBundle(Bundle(for: type(of: self))))
    }

    // MARK: - Sync no-op / outbox

    func test_record_withoutKeys_isNoOp() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: PreferencesService.shareFeedbackKey)
        let client = RecordingFeedbackClient(configured: false)
        let outbox = FeedbackOutbox(directory: makeTempDir())
        let sync = FeedbackSyncService(
            client: client,
            outbox: outbox,
            defaults: defaults,
            directory: makeTempDir()
        )
        sync.record(sampleRow())
        XCTAssertEqual(outbox.count, 0)
        XCTAssertEqual(client.submitCount, 0)
    }

    func test_record_withConsentAndKeys_enqueuesThenFlushSendsOnce() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: PreferencesService.shareFeedbackKey)
        let client = RecordingFeedbackClient(configured: true)
        let outbox = FeedbackOutbox(directory: makeTempDir())
        let sync = FeedbackSyncService(
            client: client,
            outbox: outbox,
            defaults: defaults,
            directory: makeTempDir()
        )
        let row = sampleRow()
        sync.record(row)
        await sync.flush()
        await sync.flush()
        XCTAssertEqual(client.submitCount, 1)
        XCTAssertEqual(outbox.count, 0)
        XCTAssertNotNil(FeedbackDeviceIdentity.peek(defaults: defaults))
    }

    func test_record_withoutConsent_isNoOpEvenWhenConfigured() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: PreferencesService.shareFeedbackKey)
        let client = RecordingFeedbackClient(configured: true)
        let outbox = FeedbackOutbox(directory: makeTempDir())
        let sync = FeedbackSyncService(
            client: client,
            outbox: outbox,
            defaults: defaults,
            directory: makeTempDir()
        )
        sync.record(sampleRow())
        XCTAssertEqual(outbox.count, 0)
        XCTAssertEqual(client.submitCount, 0)
    }

    func test_outbox_duplicateClientEventID_isIdempotent() throws {
        let dir = makeTempDir()
        let outbox = FeedbackOutbox(directory: dir)
        let eventID = UUID()
        let first = try XCTUnwrap(FeedbackEnvelope.make(
            from: sampleRow(),
            deviceID: UUID(),
            clientEventID: eventID,
            includeTextForReview: false,
            shareWithDeveloper: true
        ))
        let second = try XCTUnwrap(FeedbackEnvelope.make(
            from: sampleRow(source: .thumbsDown, rating: .negative),
            deviceID: UUID(),
            clientEventID: eventID,
            includeTextForReview: false,
            shareWithDeveloper: true
        ))
        outbox.enqueue(first)
        outbox.enqueue(second)
        XCTAssertEqual(outbox.count, 1)
        XCTAssertEqual(outbox.pending().first?.clientEventID, eventID)
        XCTAssertEqual(outbox.pending().first?.envelope.source, "thumbsUp")

        outbox.markFailed(clientEventID: eventID, now: Date())
        XCTAssertEqual(outbox.count, 1)
        XCTAssertEqual(outbox.pending(now: Date().addingTimeInterval(10)).first?.clientEventID, eventID)

        outbox.flush()
        let reloaded = FeedbackOutbox(directory: dir)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.pending(now: Date().addingTimeInterval(10)).first?.clientEventID, eventID)

        outbox.markSucceeded(clientEventID: eventID)
        XCTAssertEqual(outbox.count, 0)
    }

    func test_erase_withoutRegisteredDevice_isSkippedNoConsent() {
        let defaults = makeDefaults()
        let sync = FeedbackSyncService(
            client: RecordingFeedbackClient(configured: true),
            outbox: FeedbackOutbox(directory: makeTempDir()),
            defaults: defaults,
            directory: makeTempDir()
        )
        XCTAssertEqual(sync.beginRemoteErase(), .skippedNoConsent)
    }

    func test_erase_capturesDeviceIDBeforeClear() throws {
        let defaults = makeDefaults()
        let deviceID = FeedbackDeviceIdentity.registered(defaults: defaults)
        let client = RecordingFeedbackClient(configured: false)
        let dir = makeTempDir()
        let sync = FeedbackSyncService(
            client: client,
            outbox: FeedbackOutbox(directory: makeTempDir()),
            defaults: defaults,
            directory: dir
        )
        XCTAssertEqual(sync.beginRemoteErase(), .skippedNoKeys)
        XCTAssertNil(FeedbackDeviceIdentity.peek(defaults: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("erase-tombstone.json").path))
        let data = try Data(contentsOf: dir.appendingPathComponent("erase-tombstone.json"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(deviceID.uuidString))
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let name = "FeedbackVerification-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackVerification-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private final class RecordingFeedbackClient: FeedbackSubmitting {
    let isConfigured: Bool
    var submitCount = 0
    var erased: [UUID] = []

    init(configured: Bool) {
        isConfigured = configured
    }

    func submit(_ envelope: FeedbackEnvelope) async throws {
        submitCount += 1
    }

    func erase(deviceID: UUID) async throws {
        erased.append(deviceID)
    }
}
