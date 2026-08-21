//
//  JournalContainer.swift
//  MeetMemento
//
//  Spec 015 R2: SwiftData store with CloudKit private-DB mirroring.
//  The device is the system of record — CloudKit failure degrades to local.
//

import Foundation
import SwiftData

enum JournalContainer {
    static let cloudKitIdentifier = JournalSchema.cloudKitContainerID

    @MainActor
    static func make() -> ModelContainer {
        let schema = JournalSchema.schema
        do {
            let mirrored = ModelConfiguration(
                "memento-journal",
                schema: schema,
                cloudKitDatabase: .private(cloudKitIdentifier)
            )
            return try ModelContainer(for: schema, configurations: mirrored)
        } catch {
            AppLogger.log("[JournalContainer] CloudKit configuration failed; local-only. \(error.localizedDescription)")
            let local = ModelConfiguration(
                "memento-journal-local",
                schema: schema,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: local)
            } catch {
                AppLogger.log("[JournalContainer] Local SwiftData store failed: \(error.localizedDescription)")
                return try! ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                )
            }
        }
    }
}
