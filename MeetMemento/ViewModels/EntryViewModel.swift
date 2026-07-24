
//
//  EntryViewModel.swift
//  MeetMemento
//
//  Manages journal entries using Supabase JournalService.
//  Bridges local 'Entry' model with remote 'JournalEntry' model.
//

import Foundation
import SwiftUI
import Supabase

@MainActor
class EntryViewModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var isLoading = false
    @Published var hasInitiallyLoaded = false
    @Published var errorMessage: String?
    @Published var userFirstName: String = ""

    /// Cached month groups for efficient SwiftUI diffing
    @Published private(set) var entriesByMonth: [MonthGroup] = []

    /// Session PIN stored in memory for encryption operations (cleared on lock)
    private var sessionPIN: String?

    /// Whether we have a valid session PIN for encryption
    var hasSessionPIN: Bool { sessionPIN != nil }

    /// Tracks pending entry operations to prevent race conditions
    private var pendingOperations: Set<UUID> = []

    /// Flag to prevent concurrent load operations
    private var isLoadingEntries = false

    /// Recomputes the cached `entriesByMonth` grouping.
    /// Call this after any mutation to `entries`.
    private func updateEntriesByMonth() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .month, for: entry.createdAt)?.start ?? entry.createdAt
        }
        self.entriesByMonth = grouped.map { (monthStart, entries) in
            MonthGroup(monthStart: monthStart, entries: entries.sorted { $0.createdAt > $1.createdAt })
        }.sorted { $0.monthStart > $1.monthStart }
    }

    // MARK: - Session PIN Management

    /// Sets the session PIN for encryption operations (call after unlock)
    func setSessionPIN(_ pin: String) {
        self.sessionPIN = pin
                AppLogger.log("🔐 [EntryViewModel] Session PIN set")
    }

    /// Clears the session PIN (call on app lock)
    func clearSessionPIN() {
        self.sessionPIN = nil
                AppLogger.log("🔐 [EntryViewModel] Session PIN cleared")
    }

    // MARK: - Search

    /// Filter entries by title or content text
    /// - Parameter query: Search query string
    /// - Returns: Filtered entries sorted by most recent first
    func searchEntries(query: String) -> [Entry] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return entries
        }
        let searchTerms = query.lowercased()
        return entries.filter { entry in
            entry.title.lowercased().contains(searchTerms) ||
            entry.text.lowercased().contains(searchTerms)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - CRUD Operations

    func loadEntries() async {
        // Prevent concurrent load operations
        guard !isLoadingEntries else {
            AppLogger.log("⚠️ [EntryViewModel] Concurrent load blocked - already loading")
            return
        }

        isLoadingEntries = true
        defer { isLoadingEntries = false }

        isLoading = true
        errorMessage = nil

        #if DISABLE_SUPABASE
        // UI Testing Mode - Use mock data
        try? await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
        self.entries = MockDataProvider.shared.mockEntries
        self.userFirstName = MockDataProvider.shared.mockUserFirstName
        updateEntriesByMonth()
        AppLogger.log("📱 UI Mode: Loaded \(entries.count) mock entries")
        #else
        // Production Mode - Use Supabase with retry for cancelled requests
        var retryCount = 0
        let maxRetries = 3

        while retryCount < maxRetries {
            do {
                // Use PIN-encrypted fetch if session PIN is available
                let userEntries: [JournalEntry]
                if let pin = sessionPIN {
                    userEntries = try await JournalService.shared.fetchEntries(withPIN: pin)
                } else {
                    userEntries = try await JournalService.shared.fetchEntries()
                }
                var mapped = userEntries.map { mapToEntry($0) }
                if let pin = sessionPIN {
                    mapped = mergeInPendingSync(into: mapped, pin: pin)
                }
                self.entries = mapped
                updateEntriesByMonth()

                // Load user profile to get first name
                await loadUserProfile()
                break // Success, exit retry loop
            } catch let error as NSError where error.code == NSURLErrorCancelled {
                // Request was cancelled (often during auth state transitions)
                retryCount += 1
                AppLogger.log("⚠️ Request cancelled (attempt \(retryCount)/\(maxRetries)), retrying...")

                if retryCount < maxRetries {
                    // Wait briefly for session to stabilize before retrying
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                } else {
                    AppLogger.log("Error loading entries after \(maxRetries) retries: \(error)")
                    self.errorMessage = "Failed to load. Please pull to refresh."
                }
            } catch {
                AppLogger.log("Error loading entries: \(error)")
                self.errorMessage = "Failed to load: \(error.localizedDescription)"
                break // Non-retryable error, exit loop
            }
        }
        #endif

        hasInitiallyLoaded = true
        isLoading = false
    }

    // MARK: - Offline Resilience (spec-007)

    /// Reconciles a freshly-fetched server entry list with anything still
    /// queued locally: drops entries queued for deletion (so an offline
    /// delete doesn't reappear after a fetch), marks entries with a queued
    /// update as pending, and injects entries that only exist locally
    /// because their create never reached the server yet.
    private func mergeInPendingSync(into serverEntries: [Entry], pin: String) -> [Entry] {
        let pendingOps = LocalJournalStorage.shared.allPendingSyncOperations()
        guard !pendingOps.isEmpty else { return serverEntries }

        let opsByEntryId = Dictionary(uniqueKeysWithValues: pendingOps.map { ($0.entryId, $0) })
        let serverEntryIds = Set(serverEntries.map(\.id))

        var merged = serverEntries.compactMap { entry -> Entry? in
            guard let op = opsByEntryId[entry.id] else { return entry }
            if op.opType == .delete { return nil }
            var pending = entry
            pending.syncStatus = .pending
            return pending
        }

        // Entries queued as `.create` that never reached the server aren't
        // in `serverEntries` at all — reconstruct them from local storage.
        for op in pendingOps where op.opType == .create && !serverEntryIds.contains(op.entryId) {
            guard let title = EncryptionService.shared.decrypt(op.encryptedTitle, withPIN: pin),
                  let contentData = LocalJournalStorage.shared.loadEncrypted(entryId: op.entryId),
                  let content = EncryptionService.shared.decrypt(contentData, withPIN: pin) else {
                continue
            }
            merged.append(Entry(id: op.entryId, title: title, text: content, createdAt: op.timestamp, updatedAt: op.timestamp, syncStatus: .pending))
        }

        return merged.sorted { $0.createdAt > $1.createdAt }
    }

    /// Retries every queued write. Called on reconnect and app-foreground
    /// (see `ContentView`). Safe to call opportunistically — it's a no-op
    /// when the queue is empty, and each operation is independent so one
    /// failure doesn't block the rest.
    func drainPendingSync() async {
        guard let pin = sessionPIN else { return }
        let pendingOps = LocalJournalStorage.shared.allPendingSyncOperations()
        guard !pendingOps.isEmpty else { return }

        // No accounts (spec 023) — this is a stable local identifier, not an
        // authenticated session. The subsequent JournalService network calls
        // will fail (no valid Supabase session) until spec 015 replaces this
        // sync target with SwiftData/CloudKit; each failure re-queues below,
        // exactly as it already does for any other transient sync failure.
        let userId = AppStateStore.localUserID

        for op in pendingOps {
            switch op.opType {
            case .create, .update:
                guard let title = EncryptionService.shared.decrypt(op.encryptedTitle, withPIN: pin),
                      let contentData = LocalJournalStorage.shared.loadEncrypted(entryId: op.entryId),
                      let content = EncryptionService.shared.decrypt(contentData, withPIN: pin) else {
                    // Can't reconstruct this op (e.g. content was deleted locally
                    // some other way) — drop it rather than retry forever.
                    LocalJournalStorage.shared.dequeuePendingSync(entryId: op.entryId)
                    continue
                }

                let journalEntry = JournalEntry(id: op.entryId, userId: userId, title: title, content: content)
                do {
                    if op.opType == .create {
                        let created = try await JournalService.shared.createEntry(journalEntry)
                        markSynced(created.id)
                    } else {
                        try await JournalService.shared.updateEntry(journalEntry)
                        markSynced(op.entryId)
                    }
                    LocalJournalStorage.shared.dequeuePendingSync(entryId: op.entryId)
                } catch {
                    AppLogger.log("⚠️ [EntryViewModel] Drain retry failed for \(op.entryId), will retry later: \(error)")
                }

            case .delete:
                do {
                    try await JournalService.shared.deleteEntry(id: op.entryId)
                    LocalJournalStorage.shared.dequeuePendingSync(entryId: op.entryId)
                } catch {
                    AppLogger.log("⚠️ [EntryViewModel] Drain delete retry failed for \(op.entryId), will retry later: \(error)")
                }
            }
        }
    }

    /// No accounts (spec 023) — the display name is a local cache, not a
    /// server-fetched profile.
    private func loadUserProfile() async {
        self.userFirstName = UserDefaults.standard.string(forKey: "memento_first_name") ?? ""
    }
    
    /// Wrapper for loadEntries() - provides semantic clarity at call sites
    /// where entries should only be loaded if needed (e.g., on first view appear)
    func loadEntriesIfNeeded() async {
        await loadEntries()
    }

    /// Wrapper for loadEntries() - provides semantic clarity at call sites
    /// where entries should be explicitly refreshed (e.g., pull-to-refresh)
    func refreshEntries() async {
        await loadEntries()
    }

    /// Creates an entry local-first (spec-007): the entry is encrypted and
    /// written to disk before any network call, so it's durable even if the
    /// device is offline or the request fails. A sync failure queues the
    /// entry for retry on reconnect instead of rolling back the optimistic
    /// UI insert — losing a journal entry to a network error is the one
    /// failure mode this app cannot have.
    func createEntry(title: String, text: String) {
        // One ID from the start, shared by the UI entry, the local encrypted
        // file, and the eventual server row — no ID swap needed later.
        let entryId = UUID()
        let resolvedTitle = title.isEmpty ? "Untitled" : title
        let now = Date()

        guard !pendingOperations.contains(entryId) else {
            AppLogger.log("⚠️ [EntryViewModel] Duplicate create operation blocked for \(entryId)")
            return
        }
        pendingOperations.insert(entryId)

        let newEntry = Entry(id: entryId, title: resolvedTitle, text: text, createdAt: now, updatedAt: now, syncStatus: .pending)

        // Optimistic insert - UI updates instantly
        entries.insert(newEntry, at: 0)
        updateEntriesByMonth()

        Task { [weak self] in
            guard let self = self else { return }

            defer {
                Task { @MainActor in
                    self.pendingOperations.remove(entryId)
                }
            }

            #if DISABLE_SUPABASE
            // UI Testing Mode - Add to mock data
            MockDataProvider.shared.addMockEntry(newEntry)
            await MainActor.run { self.markSynced(entryId) }
            AppLogger.log("📱 UI Mode: Created mock entry")
            #else
            // Production Mode — no accounts (spec 023): this is a stable local
            // identifier, not an authenticated session. The JournalService
            // network call below will fail until spec 015 replaces the sync
            // target with SwiftData/CloudKit; that failure is caught and the
            // entry is queued for retry via the existing pending-sync path,
            // same as any other transient sync failure — it is never rolled back.
            let userId = AppStateStore.localUserID

            let newJournalEntry = JournalEntry(
                id: entryId,
                userId: userId,
                title: resolvedTitle,
                content: text,
                createdAt: now,
                updatedAt: now
            )

            // Local-first: encrypt and persist immediately, before attempting the network.
            if let pin = self.sessionPIN {
                JournalService.shared.saveEncryptedLocally(entryId: entryId, content: text, withPIN: pin)
            }

            do {
                let created = try await JournalService.shared.createEntry(newJournalEntry)
                await MainActor.run {
                    if let index = self.entries.firstIndex(where: { $0.id == entryId }) {
                        var serverEntry = self.mapToEntry(created)
                        serverEntry.syncStatus = .synced
                        self.entries[index] = serverEntry
                    }
                }
                LocalJournalStorage.shared.dequeuePendingSync(entryId: entryId)
            } catch {
                AppLogger.log("⚠️ [EntryViewModel] Create sync failed, queuing for retry: \(error)")
                if let pin = self.sessionPIN {
                    JournalService.shared.queuePendingSync(entryId: entryId, opType: .create, title: resolvedTitle, withPIN: pin)
                    await MainActor.run { self.markPending(entryId) }
                } else {
                    // No PIN session means no local encrypted copy exists to retry from —
                    // there's nothing durable to keep, so this falls back to the old
                    // rollback behavior rather than silently pretending it's queued.
                    await MainActor.run {
                        self.entries.removeAll { $0.id == entryId }
                        self.updateEntriesByMonth()
                        self.errorMessage = "Failed to save: \(error.localizedDescription)"
                    }
                }
            }
            #endif
        }
    }

    /// Marks an entry as synced in the in-memory list, if still present.
    private func markSynced(_ entryId: UUID) {
        if let index = entries.firstIndex(where: { $0.id == entryId }) {
            entries[index].syncStatus = .synced
        }
    }

    /// Marks an entry as pending sync in the in-memory list, if still present.
    private func markPending(_ entryId: UUID) {
        if let index = entries.firstIndex(where: { $0.id == entryId }) {
            entries[index].syncStatus = .pending
        }
    }

    func updateEntry(_ entry: Entry) {
        // Prevent concurrent operations on the same entry
        guard !pendingOperations.contains(entry.id) else {
                       AppLogger.log("⚠️ [EntryViewModel] Duplicate update operation blocked", type: .error)
            return
        }

        pendingOperations.insert(entry.id)

        Task { [weak self] in
            guard let self = self else { return }

            defer {
                Task { @MainActor in
                    self.pendingOperations.remove(entry.id)
                }
            }

            await MainActor.run { self.isLoading = true }

            #if DISABLE_SUPABASE
            // UI Testing Mode - Update mock data
            MockDataProvider.shared.updateMockEntry(entry)
            await MainActor.run {
                if let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[i] = entry
                    self.updateEntriesByMonth()
                }
            }
            AppLogger.log("📱 UI Mode: Updated mock entry")
            #else
            // Production Mode — no accounts (spec 023); see createEntry's comment above.
            let userId = AppStateStore.localUserID

            // Map back to JournalEntry
            let updatedJournalEntry = JournalEntry(
                id: entry.id,
                userId: userId,
                title: entry.title,
                content: entry.text,
                createdAt: entry.createdAt,
                updatedAt: Date()
            )

            // Local-first: encrypt and persist immediately, before attempting the network.
            if let pin = self.sessionPIN {
                JournalService.shared.saveEncryptedLocally(entryId: entry.id, content: entry.text, withPIN: pin)
            }

            do {
                try await JournalService.shared.updateEntry(updatedJournalEntry)
                await MainActor.run {
                    if let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                        var synced = entry
                        synced.syncStatus = .synced
                        self.entries[i] = synced
                        self.updateEntriesByMonth()
                    }
                }
                LocalJournalStorage.shared.dequeuePendingSync(entryId: entry.id)
            } catch {
                AppLogger.log("⚠️ [EntryViewModel] Update sync failed, queuing for retry: \(error)")
                if let pin = self.sessionPIN {
                    JournalService.shared.queuePendingSync(entryId: entry.id, opType: .update, title: entry.title, withPIN: pin)
                    await MainActor.run {
                        if let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                            var pending = entry
                            pending.syncStatus = .pending
                            self.entries[i] = pending
                            self.updateEntriesByMonth()
                        }
                    }
                } else {
                    await MainActor.run {
                        self.errorMessage = "Failed to update entry."
                    }
                }
            }
            #endif

            await MainActor.run { self.isLoading = false }
        }
    }

    func deleteEntry(id: UUID) {
        // Prevent concurrent operations on the same entry
        guard !pendingOperations.contains(id) else {
            AppLogger.log("⚠️ [EntryViewModel] Duplicate delete operation blocked for \(id)")
            return
        }

        // Store for rollback
        guard let deletedEntry = entries.first(where: { $0.id == id }),
              let deletedIndex = entries.firstIndex(where: { $0.id == id }) else { return }

        pendingOperations.insert(id)

        // Optimistic + local-first delete - UI and local copy update instantly.
        entries.removeAll { $0.id == id }
        updateEntriesByMonth()
        LocalJournalStorage.shared.deleteEncrypted(entryId: id)

        Task { [weak self] in
            guard let self = self else { return }

            defer {
                Task { @MainActor in
                    self.pendingOperations.remove(id)
                }
            }

            #if DISABLE_SUPABASE
            // UI Testing Mode - Remove from mock data
            MockDataProvider.shared.deleteMockEntry(id: id)
            AppLogger.log("📱 UI Mode: Deleted mock entry")
            #else
            // Production Mode - Use Supabase
            do {
                try await JournalService.shared.deleteEntry(id: id)
                LocalJournalStorage.shared.dequeuePendingSync(entryId: id)
            } catch {
                AppLogger.log("Error deleting entry, queuing for retry: \(error)")
                if let pin = self.sessionPIN {
                    // A delete a user made while offline should stay deleted from
                    // their view — queue the server-side delete instead of
                    // bringing the entry back, which would look like the
                    // deletion silently failed.
                    JournalService.shared.queuePendingSync(entryId: id, opType: .delete, title: "", withPIN: pin)
                } else {
                    // No PIN session to queue against — surface the failure by
                    // rolling back rather than losing track of it silently.
                    await MainActor.run {
                        self.entries.insert(deletedEntry, at: min(deletedIndex, self.entries.count))
                        self.updateEntriesByMonth()
                        self.errorMessage = "Failed to delete entry."
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Mappers

    private func mapToEntry(_ je: JournalEntry) -> Entry {
        return Entry(
            id: je.id,
            title: je.title,
            text: je.content,
            createdAt: je.createdAt,
            updatedAt: je.updatedAt
        )
    }
}

// MARK: - Month Group Model

public struct MonthGroup: Identifiable {
    /// Stable ID based on month start date - ensures SwiftUI can efficiently diff
    public var id: Date { monthStart }
    public let monthStart: Date
    public let entries: [Entry]

    public var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthStart)
    }

    public var entryCount: Int { entries.count }
}

// MARK: - Mock Data Support
extension EntryViewModel {
    func loadMockEntries() {
        self.entries = Entry.sampleEntries
        updateEntriesByMonth()
    }

    /// Returns a view model with sample entries for previews (e.g. ContentView Insights tab with entries).
    static func withPreviewEntries() -> EntryViewModel {
        let vm = EntryViewModel()
        vm.entries = Entry.sampleEntries
        vm.updateEntriesByMonth()
        return vm
    }
}
