//
//  TurnShapeCadence.swift
//  withMemento
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
            return "Say what you can do together, then ask one question about what they want to look at."
        }
        if stance == .nearbyOnly || stance == .noMatch {
            return "Ask one question back toward them about what they were hoping to find."
        }
        if stance == .outsideScope {
            return "Say that's outside what you can see, then ask one question toward them."
        }
        if notebookOn {
            return "Stay with the moment you placed, then ask one specific question about it. No counts, no emotion labels."
        }
        return "Meet them, then ask one specific question about how they are or what they just said. "
            + "Keep the journal out of it unless they brought it up."
    }
}
