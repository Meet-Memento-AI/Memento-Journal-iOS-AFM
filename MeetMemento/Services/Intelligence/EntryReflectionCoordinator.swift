//
//  EntryReflectionCoordinator.swift
//  MeetMemento
//
//  Session 8 / 045 R3: post-save entry reflection and warm-queue backfill.
//  No `import FoundationModels`.
//

import Foundation

/// Testable save-side hook: reflection never runs when the disk write failed.
enum EntrySaveSideEffects {
    static var onSchedule: ((Entry) -> Void)?

    static func afterSuccessfulSave(_ entry: Entry, saved: Bool) {
        guard saved else { return }
        if let onSchedule {
            onSchedule(entry)
            return
        }
        EntryReflectionCoordinator.scheduleAfterSave(entry)
    }

    static func reset() {
        onSchedule = nil
    }
}

enum EntryReflectionCoordinator {
    /// After a successful local save. Save-failure must not call this.
    static func scheduleAfterSave(_ entry: Entry) {
        guard PreferencesService.shared.aiEnabled else { return }
        Task.detached(priority: .utility) {
            await reflectIfNeeded(entry, intelligence: FoundationModelsIntelligenceService.shared)
        }
    }

    /// Same utility queue as `EntryRetriever.warmEmbeddings`. One at a time.
    static func backfill(
        _ entries: [Entry],
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared
    ) async {
        guard PreferencesService.shared.aiEnabled else { return }
        var tracker = RefusalOutageTracker()
        let pending = MementoDataStore.entriesNeedingEntryReflection(from: entries)
        for entry in pending {
            let outcome = await reflectIfNeeded(entry, intelligence: intelligence)
            switch outcome {
            case .refused:
                if tracker.recordRefusal() { return }
            case .succeeded:
                tracker.recordSuccess()
            case .skipped, .failed:
                break
            }
        }
    }

    enum Outcome: Sendable {
        case succeeded, refused, skipped, failed
    }

    @discardableResult
    static func reflectIfNeeded(
        _ entry: Entry,
        intelligence: IntelligenceService
    ) async -> Outcome {
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skipped }
        if MementoDataStore.hasEntryReflection(entryID: entry.id) { return .skipped }

        do {
            let generated = try await intelligence.reflect(on: entry)
            persist(generated.value, for: entry, zone: generated.zoneUsed)
            return .succeeded
        } catch let error as IntelligenceError {
            switch error {
            case .guardrailRefusal, .crisisResource, .safetyRefusal:
                return .refused
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    private static func persist(
        _ result: EntryReflectionResult,
        for entry: Entry,
        zone: TrustZone
    ) {
        let observation = EntryReflectionPolicy.shouldWriteObservation(salience: result.salience)
            ? result.summary
            : ""
        MementoDataStore.persistEntryReflection(
            entryID: entry.id,
            moodLabels: result.moods.map(\.rawValue),
            topicLabels: result.topics.map(\.rawValue),
            body: observation,
            zoneRaw: zone.identifier,
            promptVersion: result.promptVersion,
            vocabularyVersion: result.vocabularyVersion
        )
    }
}
