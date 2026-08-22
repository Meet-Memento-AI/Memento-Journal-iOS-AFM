//
//  TurnShapeCadence.swift
//  MeetMemento
//
//  Spec 037 R3 / ask@12: thread-level Open/Stop bit for the live Ask session.
//  Overlay on the [Turn:] user prompt — never two Open shapes in a row, on
//  journal or notebook-off turns. Force-stop stances (noMatch, outsideScope)
//  do not record, so the next social turn can still Open.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// Recall turn shapes from spec 037 R2. C (surface-and-stop) and D (minimal
/// ack) are prompt-described; code gates Open vs Stop on participating turns.
enum RecallTurnShape: String, Sendable, Equatable {
    /// Follow them. No question. Default after an Open, and for force-stop.
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

    /// Stances that take a turn in the Open/Stop bit. First participating turn
    /// of a thread is Open. After Open, next is Stop. After Stop, next may Open.
    /// Never two Opens in a row.
    private static func participates(_ stance: TurnStance) -> Bool {
        switch stance {
        case .casual, .sharing, .journalGrounded, .followupThread, .aboutApp:
            return true
        case .noMatch, .outsideScope:
            return false
        }
    }

    /// Resolve the shape for this stance. Force-stop stances return Stop and
    /// do not record, so an honest empty / redirect does not spend the next
    /// social Open.
    mutating func resolve(for stance: TurnStance) -> RecallTurnShape {
        guard Self.participates(stance) else { return .answerStop }
        let shape: RecallTurnShape = (lastShape == .answerOpen) ? .answerStop : .answerOpen
        lastShape = shape
        return shape
    }

    /// Second user-prompt line on participating stances. Nil for force-stop
    /// (noMatch / outsideScope) — the prompt already forbids Open there.
    ///
    /// `isGrounded` distinguishes a follow-up that actually hit the journal
    /// (Open about the evidence) from a social continuer (Open about them).
    static func overlayLine(shape: RecallTurnShape, stance: TurnStance,
                            isGrounded: Bool = false) -> String? {
        guard Self.participates(stance) else { return nil }
        let notebookOn = stance == .journalGrounded
            || (stance == .followupThread && isGrounded)
        switch shape {
        case .answerOpen:
            if stance == .aboutApp {
                return "[Shape: say what you can do together, then one question about what they want to look at. Never a second question.]"
            }
            if notebookOn {
                return "[Shape: answer, then one specific question about something in the evidence. Never a second question.]"
            }
            return "[Shape: Meet them, then one specific question about how they are or what they just said. Never about the journal unless they brought it up. Never a second question.]"
        case .answerStop:
            if notebookOn {
                // Phrased to constrain the QUESTION, not the length.
                //
                // This used to read "answer and stop — no question this turn." Shape
                // Stop is documented as being purely about not asking a question, but
                // "answer and stop" sits in the highest-attention slot of the prompt
                // (second line, right after `[Turn:]`), and a small on-device model
                // reads it as an instruction about brevity.
                return "[Shape: answer the question fully from the evidence. "
                    + "Do not end with a question this turn.]"
            }
            return "[Shape: follow what they just said. Do not end with a question this turn.]"
        }
    }
}
