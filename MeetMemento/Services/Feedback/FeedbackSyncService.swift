//
//  FeedbackSyncService.swift
//  MeetMemento
//
//  Spec 042 sync: local AnswerFeedbackStore stays the source of truth.
//  Network never blocks a thumb. Durable outbox + idempotent retries.
//

import Foundation

enum FeedbackWipeOutcome: Equatable {
    case issued
    case queuedPending
    case skippedNoConsent
    case skippedNoKeys
}

final class FeedbackSyncService: @unchecked Sendable {
    static let shared = FeedbackSyncService()

    private let client: FeedbackSubmitting
    private let outbox: FeedbackOutbox
    private let defaults: UserDefaults
    private let tombstoneURL: URL
    private let flushLock = NSLock()
    private var isFlushing = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var lastWipeOutcome: FeedbackWipeOutcome?

    init(client: FeedbackSubmitting = SupabaseFeedbackClient(),
         outbox: FeedbackOutbox = FeedbackOutbox(),
         defaults: UserDefaults = .standard,
         directory: URL? = nil) {
        self.client = client
        self.outbox = outbox
        self.defaults = defaults
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MementoFeedback", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.tombstoneURL = base.appendingPathComponent("erase-tombstone.json")
    }

    /// Enqueue a verification upload after the local store write.
    /// Reports always queue (per-event consent). Thumbs no-op when the
    /// Settings toggle is off or keys are missing.
    func record(_ row: AnswerFeedback, includeTextForReview: Bool = false) {
        let share = defaults.bool(forKey: PreferencesService.shareFeedbackKey)
        let tier = FeedbackConsent.tier(
            shareWithDeveloper: share,
            source: row.source,
            includeTextForReview: includeTextForReview
        )
        guard tier != .none else {
            AppLogger.log(
                "⚠️ [Feedback] skip \(row.source.rawValue) — ratings sharing off",
                category: AppLogger.network
            )
            return
        }
        guard client.isConfigured else {
            AppLogger.log(
                "⚠️ [Feedback] skip \(row.source.rawValue) — SUPABASE_URL / ANON_KEY missing",
                category: AppLogger.network
            )
            return
        }

        let deviceID = FeedbackDeviceIdentity.registered(defaults: defaults)
        guard let envelope = FeedbackEnvelope.make(
            from: row,
            deviceID: deviceID,
            includeTextForReview: includeTextForReview,
            shareWithDeveloper: share
        ) else { return }

        outbox.enqueue(envelope)
        AppLogger.log(
            "✅ [Feedback] queued \(envelope.kind) textIncluded=\(envelope.textIncluded)",
            category: AppLogger.network
        )
        Task { await flush() }
    }

    func resumePendingWork() {
        Task { await flushEraseTombstone() }
        Task { await flush() }
    }

    func flush() async {
        flushLock.lock()
        if isFlushing {
            flushLock.unlock()
            return
        }
        isFlushing = true
        flushLock.unlock()
        defer {
            flushLock.lock()
            isFlushing = false
            flushLock.unlock()
        }

        guard client.isConfigured else { return }
        await flushEraseTombstone()
        for item in outbox.pending() {
            do {
                try await client.submit(item.envelope)
                outbox.markSucceeded(clientEventID: item.clientEventID)
                AppLogger.log(
                    "✅ [Feedback] uploaded \(item.envelope.kind)",
                    category: AppLogger.network
                )
            } catch {
                outbox.markFailed(clientEventID: item.clientEventID)
                AppLogger.log(
                    "⚠️ [Feedback] upload failed \(item.envelope.kind): \(error)",
                    category: AppLogger.network
                )
            }
        }
    }

    /// Settings toggle turned off: attempt remote erase, keep local store.
    func withdrawConsent() {
        beginRemoteErase(clearLocalOutbox: true)
    }

    /// Delete Everything: capture the device id before local identity is wiped.
    @discardableResult
    func beginRemoteErase(clearLocalOutbox: Bool = true) -> FeedbackWipeOutcome {
        let deviceID = FeedbackDeviceIdentity.peek(defaults: defaults)
        if clearLocalOutbox {
            outbox.clear()
        }
        guard let deviceID else {
            lastWipeOutcome = .skippedNoConsent
            return .skippedNoConsent
        }
        persistTombstone(deviceID)
        FeedbackDeviceIdentity.clear(defaults: defaults)
        guard client.isConfigured else {
            lastWipeOutcome = .skippedNoKeys
            return .skippedNoKeys
        }
        lastWipeOutcome = .queuedPending
        Task { await flushEraseTombstone() }
        return .queuedPending
    }

    // MARK: - Tombstone

    private struct EraseTombstone: Codable {
        let deviceID: UUID
    }

    private func persistTombstone(_ deviceID: UUID) {
        let data = try? encoder.encode(EraseTombstone(deviceID: deviceID))
        try? data?.write(to: tombstoneURL, options: [.atomic, .completeFileProtection])
    }

    private func loadTombstone() -> UUID? {
        guard let data = try? Data(contentsOf: tombstoneURL),
              let stone = try? decoder.decode(EraseTombstone.self, from: data) else {
            return nil
        }
        return stone.deviceID
    }

    private func flushEraseTombstone() async {
        guard let deviceID = loadTombstone() else { return }
        guard client.isConfigured else { return }
        do {
            try await client.erase(deviceID: deviceID)
            try? FileManager.default.removeItem(at: tombstoneURL)
            lastWipeOutcome = .issued
        } catch {
            lastWipeOutcome = .queuedPending
        }
    }
}
