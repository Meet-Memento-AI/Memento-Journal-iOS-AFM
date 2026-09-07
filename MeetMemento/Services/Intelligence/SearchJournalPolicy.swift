//
//  SearchJournalPolicy.swift
//  MeetMemento
//
//  Session 10 / 044 R4: when the search tool may attach and when a call
//  is admitted. Pure Swift so tests do not need the iOS 27 Tool type.
//

import Foundation

/// Per-turn tool counter + extra retrievals (Session 10). No FoundationModels.
final class SearchJournalTurnState: @unchecked Sendable {
    private let lock = NSLock()
    private var callsSoFar = 0
    private(set) var extraEntries: [RetrievedEntry] = []

    var toolsCalled: Int {
        lock.lock()
        defer { lock.unlock() }
        return callsSoFar
    }

    func beginCall() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let prior = callsSoFar
        callsSoFar += 1
        return prior
    }

    func ingest(_ entries: [RetrievedEntry]) {
        lock.lock()
        extraEntries.append(contentsOf: entries)
        lock.unlock()
    }
}

enum SearchJournalPolicy {
    static let maxCallsPerTurn = 2
    static let exhaustedMessage = "No further search this turn."

    /// Attach only on channels that already retrieve (notebook / thread).
    static func shouldAttach(channel: ReplyChannel) -> Bool {
        channel.allowsRetrieval
    }

    /// Chat-speed: do not put the tool on the live plan (that misses
    /// `prewarmConversation`). Attach only after a speculative miss, and
    /// only when the journal has something to search. Compiler / OS
    /// availability is gated in the importer.
    static func shouldAttachOnMiss(
        channel: ReplyChannel,
        speculativeHit: Bool,
        journalIsEmpty: Bool
    ) -> Bool {
        !speculativeHit && !journalIsEmpty && shouldAttach(channel: channel)
    }

    /// `callsSoFar` is the number of tool invocations already completed.
    static func admit(callsSoFar: Int) -> String? {
        callsSoFar >= maxCallsPerTurn ? exhaustedMessage : nil
    }
}
