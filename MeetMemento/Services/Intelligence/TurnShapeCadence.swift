//
//  TurnShapeCadence.swift
//  MeetMemento
//
//  Spec 037 R3 / 039 R6: generated Ask turns Open. Overlay says *how* to
//  ask, never "do not end with a question." Light channels skip the overlay
//  (ConversationalMove already carries the ask). Farewells skip the question
//  via the Move cue, not cadence Stop.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// Recall turn shapes from spec 037 R2. C (surface-and-stop) and D (minimal
/// ack) are prompt-described; code always Opens on generated turns.
enum RecallTurnShape: String, Sendable, Equatable {
    /// Follow them. No question. Unused on the live path (always Open).
    case answerStop
    /// Follow them, then one specific question.
    case answerOpen
}

/// Session-local Open/Stop cadence. Reset when Ask history is empty (new chat).
struct TurnShapeCadence: Sendable, Equatable {
    private(set) var lastShape: RecallTurnShape?

    mutating func reset() {
        lastShape = nil
    }

    /// Every generated stance Opens. Farewell skips the question via
    /// `ConversationalMove.skipsQuestion`, not this bit.
    mutating func resolve(for _: TurnStance) -> RecallTurnShape {
        lastShape = .answerOpen
        return .answerOpen
    }

    /// Second user-prompt line on the heavy path. Nil for casual — the light
    /// Move cue already asks. Never "Do not end with a question this turn."
    ///
    /// `isGrounded` distinguishes a follow-up that actually hit the journal
    /// (Open about the evidence) from a social continuer (Open about them).
    static func overlayLine(shape _: RecallTurnShape, stance: TurnStance,
                            isGrounded: Bool = false) -> String? {
        guard stance != .casual else { return nil }
        let notebookOn = stance == .journalGrounded
            || (stance == .followupThread && isGrounded)
        if stance == .aboutApp {
            return "[Shape: say what you can do together, then one question about what they want to look at. Never a second question.]"
        }
        if stance == .noMatch {
            return "[Shape: be honest you don't see it, then one question back toward them. Never a second question.]"
        }
        if stance == .outsideScope {
            return "[Shape: that's outside what you can see, then one question toward them. Never a second question.]"
        }
        if notebookOn {
            return "[Shape: connect one pattern from the evidence, then one specific question about that. Never a second question. No counts, no emotion labels.]"
        }
        return "[Shape: Meet them, then one specific question about how they are or what they just said. Never about the journal unless they brought it up. Never a second question.]"
    }
}
