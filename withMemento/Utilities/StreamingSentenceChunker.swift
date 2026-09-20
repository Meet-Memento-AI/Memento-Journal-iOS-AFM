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

    /// First-audio: speak a clause once it has this many complete words
    /// (read-back / typed). Conversation profile uses a shorter bar.
    static let firstClauseMinWords = FirstChunkProfile.readBack.firstClauseMinWords
    /// First-audio fallback: speak a stable prefix of this many complete words
    /// when no clause punctuation has appeared yet (read-back / typed).
    static let firstPrefixMinWords = FirstChunkProfile.readBack.firstPrefixMinWords
    /// Subsequent-sentence dead-air prefetch (P6): emit a held tail this long.
    static let stableTailMinWords = 12

    /// Word bars for the first speakable chunk. Conversation speaks sooner;
    /// read-back keeps the original 12 / 10 so typed playback is unchanged.
    struct FirstChunkProfile: Equatable, Sendable {
        var firstClauseMinWords: Int
        var firstPrefixMinWords: Int

        static let readBack = FirstChunkProfile(firstClauseMinWords: 12, firstPrefixMinWords: 10)
        static let conversation = FirstChunkProfile(firstClauseMinWords: 6, firstPrefixMinWords: 5)
    }

    private let profile: FirstChunkProfile

    /// A short opener ("Sure.") emitted immediately via the first-sentence
    /// fast path (spec 029 R4). The forward-merge rule will later fold it into
    /// the next sentence; `reconcileOpener` splits it back out so the already-
    /// spoken prefix keeps its identity and the remainder is emitted fresh.
    private var pendingOpenerPrefix: String?

    init(profile: FirstChunkProfile = .readBack) {
        self.profile = profile
    }

    /// Feed the latest cumulative text. Returns the sentences that have
    /// completed since the previous call, in order. While `isFinal` is false
    /// the trailing fragment is held back — it may still be growing; passing
    /// `isFinal: true` flushes it.
    ///
    /// Exception (spec 029 R4, time-to-first-audio): the very first sentence
    /// of a session is emitted the moment it is boundary-complete, even when
    /// it is shorter than the merge minimum — a reply opening with "Sure."
    /// starts audio immediately instead of waiting for the next sentence.
    ///
    /// No sanitizing happens here: `VoicePlaybackService.enqueue` runs every
    /// sentence through `SpeechTextSanitizer` — the single choke point.
    mutating func consume(_ cumulative: String, isFinal: Bool, allowStableTail: Bool = false) -> [String] {
        var sentences = Self.split(cumulative)
        reconcileOpener(&sentences)

        // First-chunk fast path: speak a clause or a stable word prefix
        // before a period arrives, so narration does not wait on a long
        // opener. Reuses `pendingOpenerPrefix` so a later period does not
        // re-speak the prefix.
        if !isFinal, emittedCount == 0, sentences.count == 1, let growing = sentences.first {
            let completeSentence = Self.endsAtBoundary(growing) && Self.isLikelySentence(growing)
            if !completeSentence, let prefix = firstChunkPrefix(growing) {
                pendingOpenerPrefix = prefix
                emittedCount = 1
                return [prefix]
            }
        }

        // Streaming: hold back a trailing sentence that may still change —
        // either it is mid-word (no boundary yet), or it is short enough that
        // the merge rule would fold it into whatever streams in next. Emitting
        // it now would freeze `emittedCount` past text that later regroups,
        // silently dropping words from speech. The first sentence of the
        // session is exempt from the too-short hold (fast path; the opener
        // reconciliation above keeps later regrouping consistent).
        if !isFinal, let last = sentences.last {
            let isFirstSentenceFastPath = emittedCount == 0 && sentences.count == 1
                && Self.isLikelySentence(last)
            let tooShort = last.count < Self.minSentenceLength && !isFirstSentenceFastPath
            let emitStableTail = allowStableTail && emittedCount > 0
                && Self.completeWordCount(last) >= Self.stableTailMinWords
            if !emitStableTail, !Self.endsAtBoundary(cumulative) || tooShort {
                sentences.removeLast()
            } else if emitStableTail, !Self.endsAtBoundary(cumulative),
                      let prefix = Self.completeWordPrefix(last) {
                // Queue is dry and the tail is long enough — speak the
                // complete words, then treat them as an opener so a later
                // period reconciles.
                sentences[sentences.count - 1] = prefix
                pendingOpenerPrefix = prefix
            }
        }

        // The cleaned body shrank below what was already spoken (marker
        // stripping) — nothing new to say; spoken text stays spoken.
        guard sentences.count > emittedCount else { return [] }

        let fresh = Array(sentences[emittedCount...])
        if emittedCount == 0, let opener = fresh.first,
           opener.count < Self.minSentenceLength {
            pendingOpenerPrefix = opener
        }
        emittedCount = sentences.count
        return fresh
    }

    /// If the merge rule folded the fast-path opener into the first piece,
    /// split it back apart: the opener stays sentence 0 (already spoken) and
    /// the remainder becomes its own new sentence. If the body reshaped so the
    /// opener is no longer a prefix (a shrink/rewrite), fall back to plain
    /// counting — spoken text stays spoken either way.
    private mutating func reconcileOpener(_ sentences: inout [String]) {
        guard let opener = pendingOpenerPrefix, emittedCount >= 1,
              let first = sentences.first, first != opener else { return }
        guard first.hasPrefix(opener) else {
            pendingOpenerPrefix = nil
            return
        }
        let remainder = String(first.dropFirst(opener.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sentences[0] = opener
        if !remainder.isEmpty {
            sentences.insert(remainder, at: 1)
        }
    }

    // MARK: - Splitting

    /// Whether a short boundary-complete piece reads as a real sentence rather
    /// than an abbreviation false-split — only real sentences ("Sure.",
    /// "Yes!") take the first-sentence fast path; "E.g." / "Dr." keep waiting
    /// for their merge so they never become staccato utterances.
    static func isLikelySentence(_ piece: String) -> Bool {
        let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        if "!?…".contains(last) { return true }
        guard last == "." || last == ":" else { return false }
        // The word before the terminator: single letters and truncation-style
        // tokens are abbreviation halves, not sentences.
        let word = String(trimmed.dropLast().reversed().prefix(while: \.isLetter).reversed())
            .lowercased()
        guard word.count >= 3 else { return false }
        return !["etc", "approx", "misc"].contains(word)
    }

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

    private static func isClauseBoundary(_ character: Character) -> Bool {
        character == "," || character == ";" || character == "—" || character == "–"
    }

    /// Complete words — the last token is excluded while it is still growing
    /// (no trailing whitespace or punctuation).
    static func completeWordCount(_ text: String) -> Int {
        let words = text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        guard let last = text.last else { return 0 }
        if last.isWhitespace || isClauseBoundary(last) || isTerminator(last) {
            return words.count
        }
        return max(0, words.count - 1)
    }

    /// First speakable chunk of a still-growing opener: a clause of at least
    /// `firstClauseMinWords`, or a stable prefix of `firstPrefixMinWords`.
    static func firstChunkPrefix(_ text: String) -> String? {
        firstChunkPrefix(text, profile: .readBack)
    }

    private func firstChunkPrefix(_ text: String) -> String? {
        Self.firstChunkPrefix(text, profile: profile)
    }

    static func firstChunkPrefix(_ text: String, profile: FirstChunkProfile) -> String? {
        let firstPrefixMinWords = profile.firstPrefixMinWords
        let firstClauseMinWords = profile.firstClauseMinWords
        let complete = completeWordCount(text)
        guard complete >= firstPrefixMinWords else { return nil }

        var wordRanges: [Range<String.Index>] = []
        var wordStart: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isWhitespace {
                if let start = wordStart {
                    wordRanges.append(start..<i)
                    wordStart = nil
                }
            } else if wordStart == nil {
                wordStart = i
            }
            i = text.index(after: i)
        }
        if let start = wordStart { wordRanges.append(start..<text.endIndex) }
        guard wordRanges.count >= firstPrefixMinWords else { return nil }

        let searchable = min(wordRanges.count, complete)
        if complete >= firstClauseMinWords {
            for idx in (firstPrefixMinWords - 1)..<searchable {
                let range = wordRanges[idx]
                if let last = text[range].last, isClauseBoundary(last) || isTerminator(last) {
                    return String(text[..<range.upperBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if range.upperBound < text.endIndex {
                    let next = text[range.upperBound]
                    if isClauseBoundary(next) || isTerminator(next) {
                        let end = text.index(after: range.upperBound)
                        return String(text[..<end])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        let end = wordRanges[firstPrefixMinWords - 1].upperBound
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The leading complete words of a still-growing fragment.
    static func completeWordPrefix(_ text: String) -> String? {
        let n = completeWordCount(text)
        guard n > 0 else { return nil }
        var count = 0
        var wordStart: String.Index?
        var end = text.startIndex
        var i = text.startIndex
        while i < text.endIndex {
            if text[i].isWhitespace {
                if wordStart != nil {
                    end = i
                    count += 1
                    wordStart = nil
                    if count == n { break }
                }
            } else if wordStart == nil {
                wordStart = i
            }
            i = text.index(after: i)
        }
        if count < n, wordStart != nil {
            end = text.endIndex
        }
        let prefix = String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
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
