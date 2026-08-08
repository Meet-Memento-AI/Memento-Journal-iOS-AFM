
//
//  EntryViewModel.swift
//  MeetMemento
//
//  Manages journal entries. No accounts (spec 023): entries are read from
//  and written to on-device encrypted storage only, via JournalService's
//  local-only methods — there is no server.
//

import Foundation
import SwiftUI

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

    /// Sets the session PIN for encryption operations (call after unlock).
    /// Self-healing: if the entry list hasn't been populated yet (e.g. an
    /// earlier `loadEntries` ran before any PIN existed and had nothing to
    /// decrypt with), kick a load now. This resolves every ordering race
    /// between view-appear loads and PIN delivery in one place, instead of
    /// requiring each PIN call site to remember to also reload.
    func setSessionPIN(_ pin: String) {
        self.sessionPIN = pin
        AppLogger.log("🔐 [EntryViewModel] Session PIN set")
        if entries.isEmpty {
            Task { await loadEntries() }
        }
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

        #if USE_MOCK_DATA
        // UI Testing Mode - Use mock data
        try? await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
        self.entries = MockDataProvider.shared.mockEntries
        self.userFirstName = MockDataProvider.shared.mockUserFirstName
        updateEntriesByMonth()
        AppLogger.log("📱 UI Mode: Loaded \(entries.count) mock entries")
        #else
        // Production Mode — local-only (no accounts, spec 023): entries are
        // read directly from on-device encrypted storage. There is no server
        // to fetch from anymore, so this is authoritative, not a cache.
        if let pin = sessionPIN {
            let localEntries = JournalService.shared.loadAllEntriesLocally(withPIN: pin)
            self.entries = localEntries.sorted { $0.createdAt > $1.createdAt }
            updateEntriesByMonth()
            await loadUserProfile()
            hasInitiallyLoaded = true
        } else {
            // No session PIN yet (e.g. this view loaded before PIN delivery
            // finished) — nothing can be decrypted, so this wasn't a real
            // load attempt. Deliberately do NOT set `hasInitiallyLoaded`:
            // that would flip the UI to the "no entries yet" empty state,
            // which is a lie. Leaving it false keeps the loading state until
            // `setSessionPIN` triggers the real load.
            AppLogger.log("⚠️ [EntryViewModel] loadEntries called with no session PIN")
        }
        #endif

        #if USE_MOCK_DATA
        hasInitiallyLoaded = true
        #endif
        isLoading = false
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

            #if USE_MOCK_DATA
            // UI Testing Mode - Add to mock data
            MockDataProvider.shared.addMockEntry(newEntry)
            await MainActor.run { self.markSynced(entryId) }
            AppLogger.log("📱 UI Mode: Created mock entry")
            #else
            // Production Mode — local-only (no accounts, spec 023). There is
            // no server: the local encrypted save below is the entire
            // operation, not a fallback for a failed network call.
            if let pin = self.sessionPIN {
                let saved = JournalService.shared.saveEntryLocally(
                    entryId: entryId, title: resolvedTitle, content: text,
                    createdAt: now, updatedAt: now, withPIN: pin
                )
                if saved {
                    await MainActor.run { self.markSynced(entryId) }
                } else {
                    // Local save itself failed (e.g. disk/Keychain issue) — this is
                    // a real failure, not a network hiccup to retry later.
                    await MainActor.run {
                        self.entries.removeAll { $0.id == entryId }
                        self.updateEntriesByMonth()
                        self.errorMessage = "Failed to save entry."
                    }
                }
            } else {
                // No PIN session means nothing can be encrypted/persisted —
                // there's nothing durable to keep.
                await MainActor.run {
                    self.entries.removeAll { $0.id == entryId }
                    self.updateEntriesByMonth()
                    self.errorMessage = "Failed to save: no active session."
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

            #if USE_MOCK_DATA
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
            // Production Mode — local-only (no accounts, spec 023). No server:
            // the local encrypted save below is the entire operation.
            if let pin = self.sessionPIN {
                let saved = JournalService.shared.saveEntryLocally(
                    entryId: entry.id, title: entry.title, content: entry.text,
                    createdAt: entry.createdAt, updatedAt: Date(), withPIN: pin
                )
                await MainActor.run {
                    if let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                        var updated = entry
                        updated.syncStatus = saved ? .synced : entry.syncStatus
                        self.entries[i] = updated
                        self.updateEntriesByMonth()
                    }
                    if !saved {
                        self.errorMessage = "Failed to update entry."
                    }
                }
            } else {
                await MainActor.run {
                    self.errorMessage = "Failed to update entry: no active session."
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

        pendingOperations.insert(id)
        defer { pendingOperations.remove(id) }

        // Local-only (no accounts, spec 023): deleting the on-device encrypted
        // file *is* the entire operation — there's no server copy to also
        // delete, so this is fully synchronous with no retry or rollback path.
        entries.removeAll { $0.id == id }
        updateEntriesByMonth()
        LocalJournalStorage.shared.deleteEncrypted(entryId: id)

        #if USE_MOCK_DATA
        // UI Testing Mode - Remove from mock data
        MockDataProvider.shared.deleteMockEntry(id: id)
        AppLogger.log("📱 UI Mode: Deleted mock entry")
        #endif
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
