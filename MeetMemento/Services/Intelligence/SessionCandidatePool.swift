//
//  SessionCandidatePool.swift
//  MeetMemento
//
//  Spec 037 follow-on: retrieve-wide (up to 20), reveal-narrow (3–5 in the
//  Ask prompt). Session-scoped; reset when Ask history is empty.
//

import Foundation

struct SessionCandidatePool: Sendable, Equatable {
    static let capacity = 20

    private(set) var rankedIDs: [UUID] = []
    private(set) var surfacedIDs: Set<UUID> = []

    mutating func reset() {
        rankedIDs = []
        surfacedIDs = []
    }

    mutating func ingest(_ entries: [RetrievedEntry]) {
        for entry in entries where !rankedIDs.contains(entry.id) {
            rankedIDs.append(entry.id)
        }
        if rankedIDs.count > Self.capacity {
            rankedIDs = Array(rankedIDs.prefix(Self.capacity))
        }
    }

    mutating func markSurfaced(_ ids: [UUID]) {
        surfacedIDs.formUnion(ids)
    }

    /// Prefer entries not already used this thread, then top up with ones that
    /// have been, so the prompt is always filled to `cap`.
    ///
    /// The top-up is the point. This used to fall back to the ranked slice only
    /// when `fresh` was *entirely* empty — so a thread with one weak unsurfaced
    /// entry left handed the model that single entry instead of five. By the
    /// fourth or fifth turn the strong hits are all denylisted, and a prompt
    /// carrying one marginal entry alongside "everything you claim must come
    /// from the evidence block" earns exactly the one thin sentence it asks
    /// for. Novelty is still preferred; it just no longer starves the turn.
    func sliceForPrompt(_ entries: [RetrievedEntry], cap: Int) -> [RetrievedEntry] {
        let fresh = entries.filter { !surfacedIDs.contains($0.id) }
        let reused = entries.filter { surfacedIDs.contains($0.id) }
        return (fresh + reused).prefix(cap).enumerated().map { index, entry in
            RetrievedEntry(
                ref: index + 1,
                id: entry.id,
                date: entry.date,
                text: entry.text,
                quotedSpan: entry.quotedSpan
            )
        }
    }
}
