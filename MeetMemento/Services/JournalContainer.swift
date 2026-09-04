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

    private static let lock = NSLock()
    private static var cached: ModelContainer?

    /// Process-wide container so UI `.modelContainer` and store writes share one store.
    static func make() -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        // Unit tests must not open the CloudKit-backed on-disk store.
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let built = runningTests ? makeInMemory() : build(inMemory: false)
        if !runningTests {
            applyFileProtection(to: built)
        }
        cached = built
        return built
    }

    static func makeInMemory() -> ModelContainer {
        let schema = JournalSchema.schema
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }

    /// Tests replace the cached container so they do not share production files.
    static func resetCacheForTests(to container: ModelContainer? = nil) {
        lock.lock()
        cached = container
        lock.unlock()
    }

    private static func build(inMemory: Bool) -> ModelContainer {
        let schema = JournalSchema.schema
        if inMemory {
            return makeInMemory()
        }
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
                return makeInMemory()
            }
        }
    }

    /// Spec 015 R3 / 040 R3: store file uses Data Protection, not the DEK.
    private static func applyFileProtection(to _: ModelContainer) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: support,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in items where url.lastPathComponent.contains("memento-journal") {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
    }
}
