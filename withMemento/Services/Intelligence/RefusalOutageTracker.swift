//
//  RefusalOutageTracker.swift
//  MeetMemento
//
//  Tells a run of refusals apart from a content decision. No
//  `import FoundationModels` — pure Swift, so the rule is testable without a
//  model.
//

import Foundation

/// Counts consecutive generation refusals with no success in between.
///
/// A single refusal is a *designed* empty state: the chat fills the bubble with
/// authored copy, shows no alert and offers no retry, deliberately
/// indistinguishable from a real content decision. That is right for one turn
/// and wrong for a run of them.
///
/// A run is not a content decision at all — it is the signature of a broken
/// model asset, where every call refuses in milliseconds and the person is told
/// "I don't have an observation for this one." about every message they will
/// ever send, with no error and no way to tell that anything is wrong. Measured
/// on an iOS 26.0 simulator on 2026-08-23: 19 of 19 generations refused,
/// including a bare session with no app instructions, while `availability()`
/// went on reporting `.available`.
///
/// Not thread-safe by design — callers guard it with the lock they already hold
/// for adjacent state.
struct RefusalOutageTracker {

    /// Refusals in a row before the run stops being treated as a content
    /// decision. Three is well past coincidence for genuine refusals — which
    /// are uncommon, and rarer still three deep with nothing succeeding between
    /// — while still catching a total outage within a few messages.
    static let defaultThreshold = 3

    private let threshold: Int
    private(set) var consecutiveRefusals = 0

    init(threshold: Int = RefusalOutageTracker.defaultThreshold) {
        self.threshold = threshold
    }

    /// Records a refusal. Returns `true` when this one takes the run to the
    /// threshold, i.e. when the caller should stop calling it an empty state.
    ///
    /// Keeps counting past the threshold so the run length stays available for
    /// logging, and so every subsequent refusal in an ongoing outage also
    /// reports `true` rather than only the one that crossed it.
    mutating func recordRefusal() -> Bool {
        consecutiveRefusals += 1
        return consecutiveRefusals >= threshold
    }

    /// Clears the run. Called whenever the model actually produced output, so an
    /// occasional genuine refusal never accumulates across a healthy session.
    mutating func recordSuccess() {
        consecutiveRefusals = 0
    }
}
