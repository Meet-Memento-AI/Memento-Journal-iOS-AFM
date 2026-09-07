//
//  WeeklyReflectionCoordinator.swift
//  MeetMemento
//
//  Session 9 / 045 R4: foreground weekly PeriodReflection. No FoundationModels.
//

import Foundation

enum WeeklyReflectionCoordinator {
    static let quietCopy = "A quiet week. Not every week has something worth saying."

    /// Previous ISO week, if it has at least one entry and is not yet covered.
    static func previousUncoveredWeek(
        entries: [Entry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval? {
        let iso = InsightEngine.isoCalendar(calendar)
        guard let thisWeek = iso.dateInterval(of: .weekOfYear, for: now),
              let cursor = iso.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
              let previous = iso.dateInterval(of: .weekOfYear, for: cursor)
        else { return nil }
        let window = InsightEngine.orderedInterval(start: previous.start, end: previous.end)
        guard !WeeklyReflectionStore.isCovered(weekStart: window.start) else { return nil }
        let n = entries.filter { window.contains($0.createdAt) }.count
        return n >= 1 ? window : nil
    }

    static func generateIfNeeded(
        entries: [Entry],
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared,
        now: Date = Date()
    ) async {
        guard PreferencesService.shared.aiEnabled else { return }
        guard let week = previousUncoveredWeek(entries: entries, now: now) else { return }
        WeeklyReflectionStore.beginWriting()
        defer { WeeklyReflectionStore.endWriting() }

        do {
            let outcome = try await intelligence.weeklyReflection(for: week, entries: entries)
            await persist(outcome.value, weekStart: week.start, zone: outcome.zoneUsed, entries: entries)
        } catch {
            persistQuiet(weekStart: week.start)
        }
    }

    @MainActor
    static func persist(
        _ result: PeriodReflectionResult,
        weekStart: Date,
        zone: TrustZone,
        entries: [Entry]
    ) {
        if result.hasNothingToSay {
            persistQuiet(weekStart: weekStart, zoneRaw: zone.identifier, promptVersion: result.promptVersion)
            return
        }
        let body = result.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let observation = result.observation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isSpeakable(body) || !isSpeakable(observation) {
            persistQuiet(weekStart: weekStart, zoneRaw: zone.identifier, promptVersion: result.promptVersion)
            return
        }
        WeeklyReflectionStore.save(
            body: body,
            weekStart: weekStart,
            observation: observation,
            citationIDs: result.groundedEntryIDs,
            hasNothingToSay: false,
            zoneRaw: zone.identifier,
            promptVersion: result.promptVersion
        )
        MementoDataStore.upsertWeeklyReflection(
            body: body,
            weekStart: weekStart,
            observation: observation,
            citationIDs: result.groundedEntryIDs,
            zoneRaw: zone.identifier,
            promptVersion: result.promptVersion,
            entries: entries
        )
    }

    static func persistQuiet(
        weekStart: Date,
        zoneRaw: String = TrustZone.z0Device.identifier,
        promptVersion: String = "weekly@1"
    ) {
        WeeklyReflectionStore.save(
            body: quietCopy,
            weekStart: weekStart,
            observation: "",
            citationIDs: [],
            hasNothingToSay: true,
            zoneRaw: zoneRaw,
            promptVersion: promptVersion
        )
        MementoDataStore.upsertWeeklyReflection(
            body: quietCopy,
            weekStart: weekStart,
            observation: "",
            citationIDs: [],
            zoneRaw: zoneRaw,
            promptVersion: promptVersion,
            entries: []
        )
    }

    private static func isSpeakable(_ text: String) -> Bool {
        if text.isEmpty { return true }
        do {
            try SpeakabilityLinter.validate(text)
            return true
        } catch {
            return false
        }
    }
}
