//
//  ReplyRenderer+Recipe.swift
//  withMemento
//
//  Spec 058 R5: the reply-recipe rules Swift can hold by construction, so the
//  prompt no longer has to say them six times. Every pass here is stream-
//  stable — it may hold text back until the reply is final, but never removes
//  text a streamed snapshot already showed. No Foundation Models import.
//

import Foundation

/// The sentence a journal question with no matching entry opens with.
///
/// Swift writes it rather than asking the model to: told to "say exactly" a
/// first-person sentence under a second-person core, the model transcribed it
/// as "You can't find an entry…" (Study VI). The renderer prepends it and
/// removes the model's own restatement, so it appears once, in the app's voice,
/// from the very first streamed frame.
enum NoMatchLead {
    static let sentence = "I can't find an entry that supports that."

    /// Used when the model's own text renders to nothing.
    static let fallbackQuestion = "What were you hoping to find?"

    /// Tells the model the opening is taken without quoting it, so it has
    /// nothing to copy.
    static let promptLine = "The app opens this reply by telling them no entry supports it. "
        + "Write only what follows that opening."

    /// Journal channels on a miss: the stances whose turn line says there is
    /// nothing to quote.
    static func applies(to stance: TurnStance, channel: ReplyChannel) -> Bool {
        channel.allowsRetrieval && (stance == .noMatch || stance == .nearbyOnly)
    }
}

extension RenderPass {

    /// Report openers the core bans, in the forms that can be removed without
    /// breaking the sentence: "You wrote that …" and "In your journal, …" lose
    /// their frame and keep their content. "You mentioned feeling tired" has
    /// no such seam and is left to the prompt.
    private static let reportOpeners: [NSRegularExpression?] = [
        RenderText.regex(#"^\s*(You wrote|You mentioned|You said|You noted) that\s+"#,
                         options: [.caseInsensitive]),
        RenderText.regex(#"^\s*(Looking at|Looking back at|Going through) your (entries|journal|notebook),\s*"#,
                         options: [.caseInsensitive]),
        RenderText.regex(#"^\s*(In|From) your (journal|entries|notebook),\s*"#,
                         options: [.caseInsensitive])
    ]

    /// Every opener `reportOpeners` removes, spelled out, so a streamed reply
    /// can tell whether its first words might still become one.
    private static let reportOpenerForms: [String] = {
        let wrote = ["you wrote that ", "you mentioned that ", "you said that ", "you noted that "]
        let looking = ["looking at your ", "looking back at your ", "going through your ", "in your ", "from your "]
            .flatMap { lead in ["entries,", "journal,", "notebook,"].map { lead + $0 } }
        return wrote + looking
    }()

    /// Strips a banned report opener from the start of the reply. While
    /// streaming, a reply whose first words could still grow into an opener is
    /// held back, so the opener is never shown and then retracted.
    mutating func stripReportOpener(in text: String, isFinal: Bool) -> String {
        if !isFinal {
            let opening = text.drop(while: { $0.isWhitespace }).lowercased()
            if !opening.isEmpty, Self.reportOpenerForms.contains(where: { $0.hasPrefix(opening) }) {
                return ""
            }
        }
        var out = text
        for pattern in Self.reportOpeners {
            out = RenderText.replacing(pattern, in: out) { _ in
                self.stats.strippedOpenerCount += 1
                return String(RenderToken.removal)
            }
        }
        return out
    }

    private static let leadRestatement = RenderText.regex(
        #"\b(I|You)\s+(can't|can’t|cannot|can not|couldn't|couldn’t|could not)\s+find\s+(an|any)\s+"#
            + #"entr(y|ies)\s+that\s+supports?\s+(that|this|it)\s*[.!]?"#,
        options: [.caseInsensitive]
    )

    /// Removes the model's own version of the no-match sentence, in either
    /// person, so the prepended lead is not said twice.
    mutating func droppingLeadRestatement(in text: String) -> String {
        RenderText.replacing(Self.leadRestatement, in: text) { _ in
            self.stats.droppedLeadRestatementCount += 1
            return String(RenderToken.removal)
        }
    }

    /// Exactly one question, and it closes the reply.
    ///
    /// Everything up to the end of the first question is the reply's head.
    /// While streaming, the tail is held back, which is what keeps this stable:
    /// a later question can never retract text already on screen. At the end,
    /// the tail's own questions are dropped and its statements are kept, so a
    /// doubled close ("What was that like? And what stayed with you?") loses
    /// the second question and nothing else.
    mutating func keepingOneQuestion(in text: String, isFinal: Bool) -> String {
        let lines = text.components(separatedBy: "\n")
        var head: [String] = []
        var sameLineRest = ""
        var tail: [String] = []
        var found = false
        for line in lines {
            if found {
                tail.append(line)
                continue
            }
            let sentences = RenderText.sentences(of: line)
            guard let index = sentences.firstIndex(where: Self.isQuestion) else {
                head.append(line)
                continue
            }
            found = true
            head.append(sentences[...index].joined())
            sameLineRest = sentences[(index + 1)...].joined()
        }
        guard found else { return text }
        guard isFinal else { return head.joined(separator: "\n") }
        head[head.count - 1] += statements(of: sameLineRest)
        var kept: [String] = []
        for line in tail { kept.append(statements(of: line)) }
        return (head + kept).joined(separator: "\n")
    }

    private mutating func statements(of line: String) -> String {
        let sentences = RenderText.sentences(of: line)
        let statements = sentences.filter { !Self.isQuestion($0) }
        stats.droppedQuestionCount += sentences.count - statements.count
        return statements.joined()
    }

    private static let trailingClosers: Set<Character> = ["\"", "”", "’", "'", ")", "*", "_"]

    private static func isQuestion(_ sentence: String) -> Bool {
        var trimmed = Substring(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = trimmed.last, trailingClosers.contains(last) { trimmed = trimmed.dropLast() }
        return trimmed.last == "?"
    }
}

extension RenderText {

    /// The rendered body with the no-match lead in front. When the model's
    /// own text rendered to nothing, a final reply still closes with a
    /// question rather than stopping at the lead.
    static func prependingLead(_ lead: String, to body: String, isFinal: Bool) -> String {
        guard hasContent(body) else {
            return isFinal ? lead + " " + NoMatchLead.fallbackQuestion : lead
        }
        return lead + " " + body
    }
}
