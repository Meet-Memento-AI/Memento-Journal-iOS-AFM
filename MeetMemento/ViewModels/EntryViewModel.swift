
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

    /// The user's PIN, held in memory ONLY to read entries still encrypted under
    /// the pre-data-key scheme (see `EncryptionService`). Reads and writes no
    /// longer depend on it: content is encrypted under the Keychain-resident
    /// data key, so a missing PIN can no longer make the journal unreadable.
    ///
    /// Once every entry has been lazily re-encrypted this is dead weight, but it
    /// must stay until we can prove no device still holds legacy content.
    private var legacyPIN: String?

    /// Whether a PIN is available for reading legacy content.
    /// **Not** a precondition for loading or saving entries — do not gate on it.
    var hasSessionPIN: Bool { legacyPIN != nil }

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
        self.legacyPIN = pin
        AppLogger.log("🔐 [EntryViewModel] Legacy-read PIN set")
        if entries.isEmpty {
            Task { await loadEntries() }
        }
    }

    /// Clears the legacy-read PIN (call on app lock). Entries stay readable —
    /// they are encrypted under the data key, not under this.
    func clearSessionPIN() {
        self.legacyPIN = nil
                AppLogger.log("🔐 [EntryViewModel] Legacy-read PIN cleared")
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
        //
        // This no longer gates on a PIN. Content is encrypted under the
        // Keychain-resident data key, so entries load whether or not a PIN has
        // been delivered yet — which removes the failure mode where a Keychain
        // miss left the user staring at a permanently empty journal with a save
        // error and no way out. `legacyPIN`, when present, only lets entries
        // still encrypted under the old PBKDF2(PIN) scheme be read and rewritten.
        let localEntries = JournalService.shared.loadAllEntriesLocally(legacyPIN: legacyPIN)
        self.entries = localEntries.sorted { $0.createdAt > $1.createdAt }
        updateEntriesByMonth()
        await loadUserProfile()
        hasInitiallyLoaded = true
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

    /// Creates an entry with an optimistic UI insert, then encrypts and writes
    /// it to disk. The local save IS the entire operation — there is no server
    /// and no network involved. Losing a journal entry is the one failure mode
    /// this app cannot have, so a failed disk save rolls back the insert and
    /// surfaces an error rather than pretending it worked.
    func createEntry(title: String, text: String) {
        // One ID from the start, shared by the UI entry and the local
        // encrypted file.
        let entryId = UUID()
        let resolvedTitle = title.isEmpty ? "Untitled" : title
        let now = Date()

        guard !pendingOperations.contains(entryId) else {
            AppLogger.log("⚠️ [EntryViewModel] Duplicate create operation blocked for \(entryId)")
            return
        }
        pendingOperations.insert(entryId)

        let newEntry = Entry(id: entryId, title: resolvedTitle, text: text, createdAt: now, updatedAt: now)

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
            AppLogger.log("📱 UI Mode: Created mock entry")
            #else
            // Production Mode — local-only (no accounts, spec 023). There is
            // no server: the local encrypted save below is the entire
            // operation, not a fallback for a failed network call.
            // No PIN needed: the data key comes from the Keychain, so a save can
            // no longer be blocked by PIN delivery ordering.
            let saved = JournalService.shared.saveEntryLocally(
                entryId: entryId, title: resolvedTitle, content: text,
                createdAt: now, updatedAt: now
            )
            if !saved {
                // Local save failed (e.g. disk/Keychain issue) — this is a
                // real failure: roll back the optimistic insert and say so.
                await MainActor.run {
                    self.entries.removeAll { $0.id == entryId }
                    self.updateEntriesByMonth()
                    self.errorMessage = "Failed to save entry."
                }
            }
            #endif
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
            let saved = JournalService.shared.saveEntryLocally(
                entryId: entry.id, title: entry.title, content: entry.text,
                createdAt: entry.createdAt, updatedAt: Date()
            )
            await MainActor.run {
                if let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[i] = entry
                    self.updateEntriesByMonth()
                }
                if !saved {
                    self.errorMessage = "Failed to update entry."
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
