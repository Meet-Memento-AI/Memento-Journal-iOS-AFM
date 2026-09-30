//
//  ConversationQuality.swift
//  withMemento
//
//  Deterministic conversation-quality checks (ask chat 100/100, CQ1).
//  Counts and violation codes are content-free; no reply text is logged here.
//

import Foundation
import NaturalLanguage

/// Per-turn inputs for `conv.*` scorers and telemetry counters.
struct ConversationQualityTurn: Sendable, Equatable {
    let body: String
    let latestUserMessage: String
    let priorAssistantBodies: [String]
    let turnType: TurnType?
    let questionShape: QuestionShape?
    let responsePolicy: ResponsePolicy?
    let channel: ReplyChannel?
    let evidenceState: EvidenceState?
    let placedEvidence: Bool
    let exactRung: Bool
    let isMetaTurn: Bool
    let isCrisisTurn: Bool
    let spoken: Bool
}

enum ConversationQuality {

    struct Telemetry: Sendable, Equatable {
        var questionClosed = false
        var repeatedOpening = false
        var hedgeCount = 0
        var stockPhraseHit = false
        var contractionPresent = false
    }

    // MARK: - Telemetry (ReplyRenderStats)

    static func telemetry(for turn: ConversationQualityTurn) -> Telemetry {
        let body = turn.body.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = Telemetry()
        out.questionClosed = closesWithQuestion(body)
        out.repeatedOpening = repeatedOpening(body, prior: turn.priorAssistantBodies)
        out.hedgeCount = hedgeCount(in: body)
        out.stockPhraseHit = stockEmpathyHit(body)
        out.contractionPresent = hasContraction(body)
        return out
    }

    // MARK: - Per-turn violations (report-only `conv.*`)

    static func turnViolations(_ turn: ConversationQualityTurn) -> [(code: String, detail: String)] {
        let body = turn.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }
        var out: [(String, String)] = []

        if let unanchored = unanchoredDetail(turn) {
            out.append(("conv.unanchored", unanchored))
        }
        if let deferred = deferredAnswerDetail(turn) {
            out.append(("conv.deferredAnswer", deferred))
        }
        if stockEmpathyHit(body) {
            out.append(("conv.stockEmpathy", "stock empathy phrase"))
        }
        for clinical in clinicalHits(body) {
            out.append(("conv.clinical", clinical))
        }
        if noContractionEligible(body) && !hasContraction(body) {
            out.append(("conv.noContraction", "no contraction in 12+ words"))
        }
        if repeatedOpening(body, prior: turn.priorAssistantBodies) {
            out.append(("conv.repeatedOpening", openingPrefix(body)))
        }
        if body.lowercased().hasPrefix("it sounds like") {
            out.append(("conv.itSoundsLike", "It sounds like opener"))
        }
        if let generic = genericQuestionDetail(body) {
            out.append(("conv.genericQuestion", generic))
        }
        if let hedge = overHedgeDetail(body, exactRung: turn.exactRung) {
            out.append(("conv.overHedge", hedge))
        }
        for disclaimer in disclaimerHits(body, turn: turn) {
            out.append(("conv.disclaimer", disclaimer))
        }
        if let band = lengthOutOfBandDetail(turn) {
            out.append(("conv.lengthOutOfBand", band))
        }
        if let repeatQ = repeatedQuestionDetail(body, prior: turn.priorAssistantBodies) {
            out.append(("conv.repeatedQuestion", repeatQ))
        }
        return out
    }

    /// Conversation-level checks after all assistant turns are known.
    static func conversationViolations(
        assistantBodies: [String],
        userBodies: [String],
        questionClosedFlags: [Bool],
        fallbackBodies: [String]
    ) -> [(code: String, detail: String)] {
        var out: [(String, String)] = []
        if flatRhythm(assistantBodies) {
            out.append(("conv.flatRhythm", "low sentence-length variation"))
        }
        if skeletonRun(assistantBodies) {
            out.append(("conv.skeletonRun", "4+ replies same shape signature"))
        }
        if interrogation(questionClosed: questionClosedFlags, userBodies: userBodies) {
            out.append(("conv.interrogation", "3+ question closes on short user turns"))
        }
        if repeatedFallback(fallbackBodies) {
            out.append(("conv.repeatedFallback", "same fallback twice"))
        }
        if let dropped = droppedThreadDetail(assistantBodies: assistantBodies, userBodies: userBodies) {
            out.append(("conv.droppedThread", dropped))
        }
        return out
    }

    // MARK: - Internals

    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "to", "of", "in", "on", "for", "with",
        "at", "by", "from", "as", "is", "was", "are", "were", "be", "been", "being",
        "i", "you", "he", "she", "it", "we", "they", "me", "my", "your", "that", "this",
        "what", "how", "when", "where", "who", "why", "do", "did", "does", "just", "so",
        "not", "no", "yes", "yeah", "ok", "okay", "about", "up", "out", "all", "some"
    ]

    private static let stockEmpathyPhrases = [
        "that sounds really hard", "that sounds really tough", "that sounds tough",
        "it's completely understandable", "it's understandable", "it's okay to feel",
        "it's valid to feel", "thank you for sharing", "i'm here for you",
        "you're not alone", "it's important to", "remember that", "be gentle with yourself"
    ]

    private static let clinicalPhrases = [
        "entry indicates", "the data", "according to your journal", "noted", "the user"
    ]

    private static let hedgeTokens = [
        "maybe", "perhaps", "might", "it seems", "it sounds like", "i think",
        "possibly", "could be", "i'm not sure", "im not sure"
    ]

    private static let disclaimerPhrases = [
        "as an ai", "i'm just a journaling companion", "im just a journaling companion",
        "i'm not a therapist", "im not a therapist"
    ]

    private static let genericQuestions = [
        "how does that make you feel", "what's on your mind", "whats on your mind",
        "anything else", "how are you feeling about that"
    ]

    private static let stockAcknowledgements = [
        "great question", "good question", "that's a great question", "thats a great question"
    ]

    private static let contractionPattern =
        #"(?i)\b(i'm|i've|i'll|i'd|you're|you've|you'll|you'd|it's|it'll|that's|that'll|"#
        + #"there's|here's|what's|who's|don't|doesn't|didn't|won't|wouldn't|can't|couldn't|"#
        + #"shouldn't|isn't|aren't|wasn't|weren't|haven't|hasn't|hadn't)\b"#

    static func contentLemmas(_ text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var lemmas = Set<String>()
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let raw = String(text[range]).lowercased()
            let lemma = (tag?.rawValue ?? raw).lowercased()
            guard lemma.count > 2, !stopwords.contains(lemma), !stopwords.contains(raw) else { return true }
            lemmas.insert(lemma)
            return true
        }
        if lemmas.isEmpty {
            for word in text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }) {
                let token = String(word)
                if token.count > 2, !stopwords.contains(token) { lemmas.insert(token) }
            }
        }
        return lemmas
    }

    static func closesWithQuestion(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return last == "?"
    }

    static func hedgeCount(in body: String) -> Int {
        let lower = body.lowercased()
        return hedgeTokens.reduce(0) { partial, token in
            partial + lower.components(separatedBy: token).count - 1
        }
    }

    static func hasContraction(_ body: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: contractionPattern) else { return false }
        let range = NSRange(body.startIndex..., in: body)
        return re.firstMatch(in: body, range: range) != nil
    }

    private static func noContractionEligible(_ body: String) -> Bool {
        body.split(whereSeparator: { $0.isWhitespace }).count >= 12
    }

    private static func stockEmpathyHit(_ body: String) -> Bool {
        let lower = body.lowercased()
        return stockEmpathyPhrases.contains { lower.contains($0) }
    }

    private static func clinicalHits(_ body: String) -> [String] {
        let lower = body.lowercased()
        return clinicalPhrases.filter { lower.contains($0) }
    }

    private static func openingPrefix(_ body: String) -> String {
        let words = body.split(whereSeparator: { $0.isWhitespace }).prefix(3).map(String.init)
        return words.joined(separator: " ").lowercased()
    }

    private static func repeatedOpening(_ body: String, prior: [String]) -> Bool {
        let prefix = openingPrefix(body)
        guard !prefix.isEmpty else { return false }
        return prior.contains { openingPrefix($0) == prefix }
    }

    private static func isPhatic(_ turn: ConversationQualityTurn) -> Bool {
        switch turn.turnType {
        case .social, .acknowledgement, .meta: return true
        case .none: return false
        default: return false
        }
    }

    private static func unanchoredDetail(_ turn: ConversationQualityTurn) -> String? {
        guard !isPhatic(turn) else { return nil }
        if turn.placedEvidence { return nil }
        let userLemmas = contentLemmas(turn.latestUserMessage)
        guard !userLemmas.isEmpty else { return nil }
        let replyLemmas = contentLemmas(turn.body)
        if userLemmas.isDisjoint(with: replyLemmas) {
            return "no lemma overlap with user turn"
        }
        return nil
    }

    private static func directQuestionShape(_ shape: QuestionShape?) -> Bool {
        switch shape {
        case .specific, .entity, .temporal, .inventory: return true
        default: return false
        }
    }

    private static func firstSentence(_ body: String) -> String {
        let separators = CharacterSet(charactersIn: ".!?\n")
        if let range = body.rangeOfCharacter(from: separators) {
            return String(body[..<range.lowerBound])
        }
        return body
    }

    private static func deferredAnswerDetail(_ turn: ConversationQualityTurn) -> String? {
        guard directQuestionShape(turn.questionShape) else { return nil }
        let first = firstSentence(turn.body).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if first.contains("?") { return "opened with a question" }
        if stockAcknowledgements.contains(where: { first.hasPrefix($0) }) {
            return "stock acknowledgement"
        }
        return nil
    }

    private static func genericQuestionDetail(_ body: String) -> String? {
        guard let qEnd = body.lastIndex(of: "?") else { return nil }
        let before = body[..<qEnd]
        let qStart = before.lastIndex(of: "?").map { body.index(after: $0) } ?? body.startIndex
        let question = String(body[qStart...qEnd]).lowercased()
        if let hit = genericQuestions.first(where: { question.contains($0) }) {
            return hit
        }
        return nil
    }

    private static func overHedgeDetail(_ body: String, exactRung: Bool) -> String? {
        let count = hedgeCount(in: body)
        if count >= 3 { return "\(count) hedges" }
        if exactRung, count >= 1 { return "hedge on exact rung" }
        return nil
    }

    private static func disclaimerHits(_ body: String, turn: ConversationQualityTurn) -> [String] {
        guard !turn.isMetaTurn, !turn.isCrisisTurn else { return [] }
        let lower = body.lowercased()
        return disclaimerPhrases.filter { lower.contains($0) }
    }

    private static func lengthLimits(channel: ReplyChannel?, spoken: Bool, hasEvidence: Bool)
        -> (minWords: Int, maxWords: Int)? {
        guard let channel else { return nil }
        switch channel {
        case .phatic, .redirect, .continuer, .statistic:
            return (1, 30)
        case .meta:
            return (1, 40)
        case .companion:
            return (1, spoken ? 60 : 60)
        case .thread, .notebook:
            let max = spoken ? 60 : (hasEvidence ? 110 : 80)
            return (hasEvidence ? 2 : 1, max)
        }
    }

    private static func lengthOutOfBandDetail(_ turn: ConversationQualityTurn) -> String? {
        guard let limits = lengthLimits(
            channel: turn.channel,
            spoken: turn.spoken,
            hasEvidence: turn.placedEvidence || turn.evidenceState == .matched
        ) else { return nil }
        let words = turn.body.split(whereSeparator: { $0.isWhitespace }).count
        if words < limits.minWords { return "\(words) words < \(limits.minWords)" }
        if words > limits.maxWords { return "\(words) words > \(limits.maxWords)" }
        return nil
    }

    private static func questionText(_ body: String) -> String? {
        guard let questionEnd = body.lastIndex(of: "?") else { return nil }
        let start = body[..<questionEnd].lastIndex(of: "?").map { body.index(after: $0) } ?? body.startIndex
        return String(body[start...questionEnd])
    }

    private static func tokenJaccard(_ left: String, _ right: String) -> Double {
        let leftTokens = Set(
            left.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        )
        let rightTokens = Set(
            right.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        )
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        return Double(leftTokens.intersection(rightTokens).count) / Double(leftTokens.union(rightTokens).count)
    }

    private static func repeatedQuestionDetail(_ body: String, prior: [String]) -> String? {
        guard let question = questionText(body) else { return nil }
        for earlier in prior {
            guard let priorQ = questionText(earlier) else { continue }
            if tokenJaccard(question, priorQ) >= 0.6 {
                return "similar to earlier question"
            }
        }
        return nil
    }

    private static func sentenceLengths(_ body: String) -> [Int] {
        body.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.split(whereSeparator: { $0.isWhitespace }).count }
            .filter { $0 > 0 }
    }

    private static func coefficientOfVariation(_ values: [Int]) -> Double {
        guard values.count >= 2 else { return 1 }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
        return sqrt(variance) / mean
    }

    private static func flatRhythm(_ bodies: [String]) -> Bool {
        guard bodies.count >= 6 else { return false }
        let lengths = bodies.flatMap { sentenceLengths($0) }
        guard lengths.count >= 6 else { return false }
        return coefficientOfVariation(lengths) < 0.25
    }

    private static func shapeSignature(_ body: String) -> String {
        let hasQuote = body.contains("*") || body.contains("{{")
        let closes = closesWithQuestion(body) ? "q" : "s"
        let sentences = sentenceLengths(body).count
        return "\(sentences)-\(hasQuote ? "quote" : "plain")-\(closes)"
    }

    private static func skeletonRun(_ bodies: [String]) -> Bool {
        guard bodies.count >= 4 else { return false }
        let sigs = bodies.map(shapeSignature)
        var run = 1
        for index in 1..<sigs.count {
            if sigs[index] == sigs[index - 1] {
                run += 1
                if run > 3 { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    private static func interrogation(questionClosed: [Bool], userBodies: [String]) -> Bool {
        guard questionClosed.count >= 3, userBodies.count >= 3 else { return false }
        var streak = 0
        let pairs = min(questionClosed.count, userBodies.count)
        for index in 0..<pairs {
            let shortUser = userBodies[index].split(whereSeparator: { $0.isWhitespace }).count < 6
            if questionClosed[index], shortUser {
                streak += 1
                if streak > 3 { return true }
            } else {
                streak = 0
            }
        }
        return false
    }

    private static func repeatedFallback(_ bodies: [String]) -> Bool {
        let fallbacks = bodies.filter {
            $0 == ReplyRenderer.emptyFallback || $0.contains("Say a little more")
        }
        return Set(fallbacks).count < fallbacks.count
    }

    private static func droppedThreadDetail(assistantBodies: [String], userBodies: [String]) -> String? {
        guard assistantBodies.count >= 2, userBodies.count >= 2 else { return nil }
        let priorAssistant = assistantBodies[assistantBodies.count - 2]
        let latestUser = userBodies[userBodies.count - 1]
        guard priorAssistant.contains("?") else { return nil }
        let userLemmas = contentLemmas(latestUser)
        let replyLemmas = contentLemmas(assistantBodies.last ?? "")
        if !userLemmas.isEmpty, userLemmas.isDisjoint(with: replyLemmas) {
            return "no overlap with user's answer"
        }
        return nil
    }
}
