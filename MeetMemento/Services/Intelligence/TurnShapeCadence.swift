//
//  TurnShapeCadence.swift
//  MeetMemento
//
//  Spec 037 R3: last journal shape for the live Ask session. Overlay on the
//  [Turn:] user prompt — never two B (answer-and-open) shapes in a row.
//  Non-journal stances do not advance the journal cadence.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// Recall turn shapes from spec 037 R2. C (surface-and-stop) and D (minimal
/// ack) are prompt-described; code only gates A vs B on journal-grounded turns.
enum RecallTurnShape: String, Sendable, Equatable {
    /// Answer from evidence, then stop. No question. Default.
    case answerStop
    /// Answer, then one specific question about something in the evidence.
    case answerOpen
}

/// Session-local journal cadence. Reset when Ask history is empty (new chat).
struct TurnShapeCadence: Sendable, Equatable {
    private(set) var lastJournalShape: RecallTurnShape?

    mutating func reset() {
        lastJournalShape = nil
    }

    /// After a journal A, the next journal turn may be B. After B, the next is
    /// A. Non-journal stances return A and do not record.
    ///
    /// The FIRST journal turn of a thread opens (B) rather than stopping. It
    /// used to be forced to A, which made the very first grounded reply in
    /// every new conversation the tersest one the user ever sees — the worst
    /// possible first impression, and the opposite of conversational.
    mutating func resolve(for stance: TurnStance) -> RecallTurnShape {
        guard stance == .journalGrounded else { return .answerStop }
        let shape: RecallTurnShape
        if lastJournalShape == .answerOpen {
            shape = .answerStop
        } else if lastJournalShape == .answerStop {
            shape = .answerOpen
        } else {
            shape = .answerOpen
        }
        lastJournalShape = shape
        return shape
    }

    /// Second user-prompt line on journal-grounded turns. Nil otherwise.
    static func overlayLine(shape: RecallTurnShape, stance: TurnStance) -> String? {
        guard stance == .journalGrounded else { return nil }
        switch shape {
        case .answerStop:
            // Phrased to constrain the QUESTION, not the length.
            //
            // This used to read "answer and stop — no question this turn." Shape
            // A is documented as being purely about not asking a question, but
            // "answer and stop" sits in the highest-attention slot of the prompt
            // (second line, right after `[Turn:]`), and a small on-device model
            // reads it as an instruction about brevity. Stacked on top of the
            // length cap and the ban list, it was the single largest reason
            // replies collapsed to one sentence.
            return "[Shape: answer the question fully from the evidence. "
                + "Do not end with a question this turn.]"
        case .answerOpen:
            return "[Shape: answer, then one specific question about something in the evidence. Never a second question.]"
        }
    }
}
