//
//  ConversationalMove.swift
//  MeetMemento
//
//  Spec 039 R9: short warm cues for the kind of turn, not scripts. AFM
//  writes the reply. Light user prompts are cue + latest message +
//  optional don't-repeat — never [Turn:] + [Shape:] + [Move:] stacked
//  on a hello. No `import FoundationModels` — pure Swift.
//

import Foundation

/// The conversational skill for this turn. One warm sentence of guidance.
enum ConversationalMove: String, Sendable, Equatable, CaseIterable {
    case greetAndAsk
    case answerHowAreYou
    case thanks
    case farewell
    case continuer
    case reflectAndAsk
    case answerThenAsk
    case patternThenAsk
    case emptyThenAsk
    case redirectThenAsk

    /// Farewells may close without a question. Every other move asks once.
    var skipsQuestion: Bool { self == .farewell }

    /// Hello / thanks / goodbye may address them. How-are-you may, but must
    /// not lead with the name instead of answering.
    var invitesName: Bool {
        switch self {
        case .greetAndAsk, .thanks, .farewell: return true
        default: return false
        }
    }

    /// Continuer and notebook Sit: the beat is the content, not the name.
    var avoidsName: Bool {
        switch self {
        case .continuer, .patternThenAsk: return true
        default: return false
        }
    }

    /// One-line cue prepended to the user prompt.
    var cueLine: String {
        switch self {
        case .greetAndAsk:
            return "[Move: Warm hello in one sentence, then one real question. A first or last name is welcome if it fits.]"
        case .answerHowAreYou:
            return "[Move: Answer in a few words, then ask about their day. Do not echo \"how are you.\" A name is optional; do not lead with it instead of answering.]"
        case .thanks:
            return "[Move: Warm and brief. One light question if the thread is open. A first or last name is welcome if it fits.]"
        case .farewell:
            return "[Move: Warm close. No interrogation. A first or last name is welcome if it fits.]"
        case .continuer:
            return "[Move: One short reaction, then a new question. Do not recap the journal. Do not use their name.]"
        case .reflectAndAsk:
            return "[Move: Show you heard the specific thing they said; one question about that.]"
        case .answerThenAsk:
            return "[Move: Answer first, then one question.]"
        case .patternThenAsk:
            return "[Move: One connection from the evidence, then one question. No counts, no emotion labels. Do not use their name.]"
        case .emptyThenAsk:
            return "[Move: Honest that you don't see it, then one question back toward them.]"
        case .redirectThenAsk:
            return "[Move: That's outside what you can see; then one question toward them.]"
        }
    }

    /// Pick the kind of turn. Journal lexicon / stance already won upstream;
    /// this only chooses the cue.
    static func resolve(
        turn: TurnType,
        message: String,
        history: [ChatTurn],
        hasEvidence: Bool
    ) -> ConversationalMove {
        switch turn {
        case .social:
            return socialMove(for: message, hasHistory: !history.isEmpty)
        case .acknowledgement:
            return .continuer
        case .meta, .followup:
            return hasEvidence ? .patternThenAsk : .answerThenAsk
        case .share, .reflectiveQuestion:
            return hasEvidence ? .patternThenAsk : .reflectAndAsk
        case .journalQuery:
            return hasEvidence ? .patternThenAsk : .emptyThenAsk
        case .offdomain:
            return .redirectThenAsk
        }
    }

    /// Last assistant question, for the anti-repeat line.
    static func lastAssistantQuestion(in history: [ChatTurn]) -> String? {
        guard let text = history.last(where: { $0.role == .assistant })?.text else {
            return nil
        }
        guard let qMark = text.lastIndex(of: "?") else { return nil }
        let upToQ = text[...qMark]
        let start = upToQ.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "\n" })
        let slice: Substring
        if let start, start < qMark {
            slice = upToQ[upToQ.index(after: start)...]
        } else {
            slice = upToQ
        }
        let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func antiRepeatLine(from history: [ChatTurn]) -> String? {
        guard let question = lastAssistantQuestion(in: history) else { return nil }
        return "[Don't ask that again: \"\(question)\"]"
    }

    // MARK: - Social sub-kinds

    private static let farewellNeedles: [String] = [
        "bye", "goodbye", "see you", "talk soon", "take care",
        "good night", "goodnight"
    ]

    private static let thanksNeedles: [String] = [
        "thanks", "thank you", "thx", "ty", "thanks a lot", "thank you so much"
    ]

    private static let howAreYouNeedles: [String] = [
        "how are you", "how's it going", "hows it going", "how are you doing",
        "what's up", "whats up", "how have you been"
    ]

    /// Whole-message closers that are too short to use as a contains-needle
    /// (`"later"` would false-positive inside other sentences).
    private static let farewellExact: Set<String> = [
        "later", "bye", "goodbye", "good night", "goodnight"
    ]

    private static func socialMove(for message: String, hasHistory _: Bool) -> ConversationalMove {
        let folded = fold(message)
        if farewellExact.contains(folded) { return .farewell }
        if farewellNeedles.contains(where: { folded == $0 || folded.hasPrefix($0 + " ") || folded.hasSuffix(" " + $0) || folded.contains(" " + $0 + " ") }) {
            return .farewell
        }
        if thanksNeedles.contains(where: { folded == $0 || folded.contains($0) }) {
            return .thanks
        }
        if howAreYouNeedles.contains(where: { folded.contains($0) }) || folded == "sup" {
            return .answerHowAreYou
        }
        return .greetAndAsk
    }

    private static func fold(_ message: String) -> String {
        message
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .map { ch -> Character in
                switch ch {
                case ",", ";", ":", "…": return " "
                default: return ch
                }
            }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .split { $0.isWhitespace }
            .joined(separator: " ")
    }
}
