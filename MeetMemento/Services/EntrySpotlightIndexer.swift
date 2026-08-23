//
//  EntrySpotlightIndexer.swift
//  MeetMemento
//
//  Spec 016 Plan B (DEC-002): donation is opt-in, default off.
//  Retrieval uses EntryRetriever (REQ-IDX-007), not SpotlightSearchTool.
//  IndexedEntity / Core Spotlight donation only runs when the user opts in.
//

import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum IndexingPreferences {
    private static let key = "spotlightIndexingOptIn"

    /// DEC-002 / REQ-IDX-006: excludedFromIndex defaults true.
    static var spotlightOptIn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum EntrySpotlightIndexer {
    static let domainIdentifier = "com.sebastianmendo.MeetMemento.entries"
    static let namedIndex = "memento-entries"

    static func donate(_ entry: Entry) async {
        guard IndexingPreferences.spotlightOptIn else { return }
        let item = makeSearchableItem(entry)
        do {
            try await CSSearchableIndex.default().indexSearchableItems([item])
        } catch {
            AppLogger.log("[Spotlight] donate failed: \(error.localizedDescription)")
        }
    }

    static func remove(id: UUID) async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])
        } catch {
            AppLogger.log("[Spotlight] remove failed: \(error.localizedDescription)")
        }
    }

    /// Spec 016 / 040: rebuild the local index from SwiftData (inbound CloudKit rows).
    static func rebuildFromStore(container: ModelContainer? = nil) async {
        guard IndexingPreferences.spotlightOptIn else { return }
        let entries = MementoDataStore.allEntries(container: container)
        for entry in entries {
            await donate(entry)
        }
    }

    static func removeAll() async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
        } catch {
            AppLogger.log("[Spotlight] removeAll failed: \(error.localizedDescription)")
        }
    }

    static func makeSearchableItem(_ entry: Entry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
        attributes.title = entry.displayTitle
        attributes.textContent = IndexingPreferences.spotlightOptIn ? entry.text : nil
        attributes.contentCreationDate = entry.createdAt
        attributes.contentModificationDate = entry.updatedAt
        attributes.identifier = entry.id.uuidString
        return CSSearchableItem(
            uniqueIdentifier: entry.id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}
