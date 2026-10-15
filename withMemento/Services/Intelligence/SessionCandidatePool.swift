//
//  SessionCandidatePool.swift
//  withMemento
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

    /// Tool results continue the ref sequence instead of restarting at 1.
    static func renumber(_ entries: [RetrievedEntry], startingAt: Int) -> [RetrievedEntry] {
        entries.enumerated().map { offset, entry in
            RetrievedEntry(
                ref: startingAt + offset,
                id: entry.id,
                date: entry.date,
                text: entry.text,
                quotedSpan: entry.quotedSpan
            )
        }
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

    /// Prefer entries not already used this thread. When any are still fresh,
    /// top up with already-shown ones so the prompt fills to `cap`.
    ///
    /// The top-up is the point when something new is left. This used to fall
    /// back to the ranked slice only when `fresh` was *entirely* empty — so a
    /// thread with one weak unsurfaced entry left handed the model that single
    /// entry instead of five. Novelty is still preferred; it just no longer
    /// starves a turn that still has a fresh hit.
    ///
    /// When every entry was already shown, return those reused entries only if
    /// `reuseSurfaced` is true (an explicit "tell me more"). Otherwise return
    /// an empty slice so the same citation is not attached again. The default
    /// is false: the Ask path passes the flag explicitly, and a caller that
    /// omits it must not reattach a fully surfaced pool. Call sites that still
    /// have fresh entries are unaffected.
    func sliceForPrompt(
        _ entries: [RetrievedEntry],
        cap: Int,
        reuseSurfaced: Bool = false
    ) -> [RetrievedEntry] {
        let fresh = entries.filter { !surfacedIDs.contains($0.id) }
        let reused = entries.filter { surfacedIDs.contains($0.id) }
        let chosen: [RetrievedEntry]
        if fresh.isEmpty {
            chosen = reuseSurfaced ? Array(reused.prefix(cap)) : []
        } else {
            chosen = Array((fresh + reused).prefix(cap))
        }
        return chosen.enumerated().map { index, entry in
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
