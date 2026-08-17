//
//  StreamingSentenceChunker.swift
//  MeetMemento
//
//  Turns the *cumulative* body of a streaming AI reply into newly completed
//  sentences for per-sentence TTS enqueueing (VoicePlaybackService's
//  beginUtteranceSession / enqueue / finishEnqueueing seam — the sanctioned
//  workaround for AVSpeechSynthesizer's inability to consume streaming text,
//  spec 06-speech-and-audio §B1).
//
//  Every `consume` call receives the whole body-so-far, not a delta, because
//  that is what ChatService's `.delta` events carry. The chunker remembers how
//  many sentences it has already emitted and returns only the ones that
//  completed since the last call.
//

import Foundation

struct StreamingSentenceChunker {
    /// Sentences already handed to the caller. Progress is tracked as a
    /// *count*, not a character offset: reference-marker stripping can make
    /// the cumulative body shrink between snapshots (see the guard in
    /// `AIOutputComponent.startDrainIfNeeded`), so byte positions are unsafe
    /// while sentence identity is stable.
    private(set) var emittedCount = 0

    /// Fragments shorter than this are merged into the following sentence so
    /// abbreviations ("e.g.", "Dr.") and stray list numbers don't become
    /// staccato utterances of their own.
    private static let minSentenceLength = 15

    /// Feed the latest cumulative text. Returns the sentences that have
    /// completed since the previous call, in order. While `isFinal` is false
    /// the trailing fragment is held back — it may still be growing; passing
    /// `isFinal: true` flushes it.
    ///
    /// No sanitizing happens here: `VoicePlaybackService.enqueue` runs every
    /// sentence through `SpeechTextSanitizer` — the single choke point.
    mutating func consume(_ cumulative: String, isFinal: Bool) -> [String] {
        var sentences = Self.split(cumulative)

        // Streaming: hold back a trailing sentence that may still change —
        // either it is mid-word (no boundary yet), or it is short enough that
        // the merge rule would fold it into whatever streams in next. Emitting
        // it now would freeze `emittedCount` past text that later regroups,
        // silently dropping words from speech.
        if !isFinal, let last = sentences.last,
           !Self.endsAtBoundary(cumulative) || last.count < Self.minSentenceLength {
            sentences.removeLast()
        }

        // The cleaned body shrank below what was already spoken (marker
        // stripping) — nothing new to say; spoken text stays spoken.
        guard sentences.count > emittedCount else { return [] }

        let fresh = Array(sentences[emittedCount...])
        emittedCount = sentences.count
        return fresh
    }

    // MARK: - Splitting

    /// Whether the text's trailing (non-whitespace) character terminates a
    /// sentence, meaning the last split piece is complete rather than mid-word.
    private static func endsAtBoundary(_ text: String) -> Bool {
        guard let last = text.reversed().first(where: { !$0.isWhitespace }) else {
            return false
        }
        return isTerminator(last) || text.hasSuffix("\n")
    }

    private static func isTerminator(_ character: Character) -> Bool {
        ".!?…:".contains(character)
    }

    /// Splits on terminal punctuation runs and newline runs, keeping the
    /// punctuation with its sentence, then merges too-short fragments forward.
    ///
    /// Pieces are carried as *raw substrings* until the merge settles, so a
    /// false split inside an abbreviation ("E.g." → "E." + "g.") re-joins to
    /// the original text instead of gaining an invented space.
    private static func split(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""

        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()
        while let char = pending {
            current.append(char)
            let next = iterator.next()
            pending = next

            let isBreak: Bool
            if char == "\n" {
                isBreak = true
            } else if isTerminator(char) {
                // End of a punctuation run: don't split "..." or "?!" apart.
                isBreak = next.map { !isTerminator($0) } ?? true
            } else {
                isBreak = false
            }

            if isBreak {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }

        return mergeShortFragments(pieces)
    }

    /// A fragment whose *trimmed* length is below the minimum joins the piece
    /// after it (raw concatenation — original spacing preserved). The final
    /// piece is allowed to stay short — there is nothing to merge into, and a
    /// short closing sentence ("Take care.") is legitimate speech. Emitted
    /// sentences are trimmed at their edges only.
    private static func mergeShortFragments(_ pieces: [String]) -> [String] {
        var merged: [String] = []
        var carry = ""
        for piece in pieces {
            let candidate = carry + piece
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).count < minSentenceLength {
                carry = candidate
            } else {
                merged.append(candidate.trimmingCharacters(in: .whitespacesAndNewlines))
                carry = ""
            }
        }
        let tail = carry.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { merged.append(tail) }
        return merged
    }
}
