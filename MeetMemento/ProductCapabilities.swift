//
//  ProductCapabilities.swift
//  MeetMemento
//
//  Compile-time product flavor. `includesGenerativeAI` is true only when the
//  MeetMemento target sets SWIFT_ACTIVE_COMPILATION_CONDITIONS = MEMENTO_AI.
//  The flag is reserved for a future journal-only flavor that would leave it
//  absent so coordinators and Foundation Models never ship. Do not use
//  PreferencesService.aiEnabled as this gate.
//

import Foundation

enum ProductCapabilities {
    static var includesGenerativeAI: Bool {
        #if MEMENTO_AI
        true
        #else
        false
        #endif
    }

    /// Full product mirrors the journal via CloudKit. A journal-only flavor
    /// would be device-local only — no iCloud container, so CKContainer must not
    /// be constructed.
    static var includesCloudKit: Bool { includesGenerativeAI }
}
