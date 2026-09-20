//
//  RunningTranscript.swift
//  MeetMemento
//
//  Accumulates SpeechAnalyzer segment finals + the current volatile tail
//  into one utterance. Last-final-wins dropped earlier words and flashed
//  the live bubble empty on every sentence boundary.
//

import Foundation

struct RunningTranscript: Equatable, Sendable {
    private(set) var committed: String = ""
    private(set) var volatile: String = ""

    /// Text to show and to send. Cumulative volatiles (engine restates the
    /// whole utterance) win over committed+tail so we never double.
    var display: String {
        let committed = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let volatile = volatile.trimmingCharacters(in: .whitespacesAndNewlines)
        if volatile.isEmpty { return committed }
        if committed.isEmpty { return volatile }
        if volatile.hasPrefix(committed) { return volatile }
        return committed + " " + volatile
    }

    mutating func apply(_ update: TranscriptionUpdate) {
        switch update {
        case .volatile(let text):
            volatile = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .finalized(let text):
            let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                commit(piece)
            } else if !volatile.isEmpty {
                commit(volatile)
            }
            volatile = ""
        }
    }

    mutating func reset() {
        committed = ""
        volatile = ""
    }

    private mutating func commit(_ piece: String) {
        if committed.isEmpty {
            committed = piece
        } else if piece.hasPrefix(committed) {
            committed = piece
        } else if committed.hasPrefix(piece) {
            // Shorter final of an already-committed prefix — keep committed.
        } else {
            committed += " " + piece
        }
    }
}
