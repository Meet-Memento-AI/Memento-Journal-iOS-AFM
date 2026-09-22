//
//  DialogueDiffusion.swift
//  MeetMemento
//
//  Spec 050. Discrete diffusion over a finished reply.
//
//  The harness already decided how this turn should talk (`ResponsePolicy`).
//  The on-device render drifts by a few spans: a question on a goodbye, a
//  second question, "you should", a perception verb, a narrative join.
//  Diffusion here is a repair, not a second generator and not a diffusion
//  language model. The forward step marks only the spans that violate the
//  policy. The reverse step is closed-form when the constraint is structural
//  (the question budget). Semantic spans stay in the text and are named for
//  one later infill. This type never imports FoundationModels.
//

import Foundation
import NaturalLanguage

enum DialogueDiffusion {

    struct Infill: Equatable, Sendable {
        var code: String
        var sentence: String
    }

    struct Result: Equatable, Sendable {
        /// Reply after the closed-form reverse step. Identical to the input
        /// when nothing structural was wrong.
        var body: String
        /// Edits that already landed in `body`.
        var applied: [String]
        /// Spans that still violate the policy and would need one model infill.
        var infill: [Infill]
    }

    /// How many question marks this policy may keep. Acknowledge keeps none.
    /// Every other policy keeps one. Reflect and abstain still owe that one;
    /// list, answer, and retract may have zero.
    static func questionBudget(_ policy: ResponsePolicy) -> Int {
        switch policy {
        case .acknowledge:
            return 0
        case .answer, .list, .reflect, .retract, .abstain:
            return 1
        }
    }

    static func denoise(body: String, policy: ResponsePolicy, userTurn: String) -> Result {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(body: body, applied: [], infill: [])
        }

        var sentences = tokenize(trimmed)
        if sentences.isEmpty {
            sentences = [Sentence(text: trimmed)]
        }

        var applied: [String] = []
        let budget = questionBudget(policy)
        let questionIndexes = sentences.indices.filter { sentences[$0].text.contains("?") }

        if questionIndexes.count > budget {
            let dropCount = questionIndexes.count - budget
            let dropping = Set(questionIndexes.prefix(dropCount))
            let kept = sentences.enumerated().compactMap { index, sentence -> Sentence? in
                dropping.contains(index) ? nil : sentence
            }
            if kept.isEmpty {
                let flattened = flattenQuestion(sentences[sentences.count - 1].text)
                sentences = [Sentence(text: flattened)]
                applied.append("dialogue.questionOnAcknowledge")
            } else {
                sentences = kept
                applied.append(budget == 0 ? "dialogue.questionOnAcknowledge" : "dialogue.surplusQuestion")
            }
        }

        var infill: [Infill] = []
        // Flattening "Goodnight?" is already a close. Flattening "What are you
        // holding onto?" still reads as a question, so name it for one rewrite.
        if applied.contains("dialogue.questionOnAcknowledge"),
           sentences.count == 1,
           !sentences[0].text.contains("?"),
           tokenize(trimmed).allSatisfy({ $0.text.contains("?") }),
           stillReadsAsQuestion(sentences[0].text) {
            infill.append(Infill(code: "dialogue.questionOnAcknowledge", sentence: sentences[0].text))
        }

        let questionsNow = sentences.filter { $0.text.contains("?") }.count
        if ResponsePolicyResolver.openRequired(policy: policy, bodyIsEmpty: false), questionsNow == 0 {
            infill.append(Infill(code: "dialogue.missingOpen", sentence: ""))
        }

        let user = userTurn.lowercased()
        for (index, sentence) in sentences.enumerated() {
            let lower = sentence.text.lowercased()
            if index == 0, bannedOpeners.contains(where: { lower.hasPrefix($0) }) {
                infill.append(Infill(code: "dialogue.bannedOpener", sentence: sentence.text))
            }
            if lower.contains("you should"), !user.contains("you should") {
                infill.append(Infill(code: "dialogue.youShould", sentence: sentence.text))
            }
            if claimsPerception(sentence.text) {
                infill.append(Infill(code: "dialogue.perception", sentence: sentence.text))
            }
            if narrativeJoinPhrases.contains(where: { lower.contains($0) && !user.contains($0) }) {
                infill.append(Infill(code: "dialogue.narrativeJoin", sentence: sentence.text))
            }
        }

        let rebuilt = applied.isEmpty ? body : sentences.map(\.text).joined(separator: " ")
        return Result(body: rebuilt, applied: applied, infill: infill)
    }

    /// The one line a future typed-only infill call would append. Not a generation.
    static func infillInstruction(for infill: Infill, policy: ResponsePolicy) -> String {
        switch infill.code {
        case "dialogue.missingOpen":
            return "Add one question as the final sentence. Do not add a second. Keep every other sentence. \(PromptRegistry.policySuffix(policy))"
        case "dialogue.youShould":
            return "Rewrite only this sentence as an option they already named, without \"you should\": \(infill.sentence)"
        case "dialogue.perception":
            return "Rewrite only this sentence so you do not claim you saw, heard, felt, noticed, smelled, or remembered their scene. \"I hear you\" stays legal: \(infill.sentence)"
        case "dialogue.narrativeJoin":
            return "Rewrite only this sentence onto words they used. Do not join fragments they did not write: \(infill.sentence)"
        case "dialogue.bannedOpener":
            return "Rewrite only this opening so it does not start with \"You wrote\", \"You mentioned\", \"Looking at your entries\", or \"In your journal\": \(infill.sentence)"
        case "dialogue.questionOnAcknowledge":
            return "Rewrite only this sentence as a close with no question: \(infill.sentence)"
        default:
            return PromptRegistry.policySuffix(policy)
        }
    }

    // MARK: - Sentences

    private struct Sentence {
        var text: String
    }

    private static func tokenize(_ text: String) -> [Sentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [Sentence] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let piece = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { sentences.append(Sentence(text: piece)) }
            return true
        }
        return sentences
    }

    private static func flattenQuestion(_ text: String) -> String {
        guard let mark = text.lastIndex(of: "?") else { return text }
        var copy = text
        copy.replaceSubrange(mark...mark, with: ".")
        return copy
    }

    private static func stillReadsAsQuestion(_ text: String) -> Bool {
        let cues: Set<String> = [
            "who", "what", "when", "where", "why", "how",
            "did", "do", "does", "are", "is", "was", "were",
            "can", "could", "would", "will"
        ]
        let first = text.lowercased().split(separator: " ").first.map(String.init) ?? ""
        return cues.contains(first)
    }

    // MARK: - Semantic noise

    private static let bannedOpeners = [
        "you wrote",
        "you mentioned",
        "looking at your entries",
        "in your journal"
    ]

    /// Same joins spec 049 reports. A phrase already in the user turn is theirs.
    private static let narrativeJoinPhrases = [
        "you keep tracing",
        "the pattern",
        "you're holding"
    ]

    /// "I hear you" and "I'm here" do not match. Past-tense perception does.
    private static let perceptionPattern = #"(?i)\bi (saw|heard|felt|noticed|smelled|remembered)\b"#

    private static func claimsPerception(_ sentence: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: perceptionPattern) else { return false }
        let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
        return re.firstMatch(in: sentence, range: range) != nil
    }
}
