//
//  TurnClassifier.swift
//  MeetMemento
//
//  Deterministic classification of the CURRENT chat message into a
//  conversational turn type. The ~3B on-device model cannot reliably infer
//  conversational stance, so stance is computed here and handed to it as an
//  explicit instruction (see RetrievalPolicy.TurnStance).
//
//  Precision-biased by design: the no-retrieval types (social,
//  acknowledgement, meta, offdomain) fire only on high-precision,
//  short-message patterns. Anything ambiguous falls through to share /
//  journalQuery, where the retrieval confidence bar — not this classifier —
//  decides whether the reply is grounded. A misfire therefore degrades to a
//  conversational reply, never to the bot going deaf to a journal ask.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// The conversational role of a single user message.
enum TurnType: String, Sendable, Equatable, CaseIterable {
    case social             // greeting / thanks / small talk
    case acknowledgement    // "yeah", "haha", "i guess" — continuers
    case meta               // about the app/assistant itself
    case share              // states feelings/events without asking anything
    case followup           // refers to the assistant's previous turn
    case journalQuery       // explicit ask about entries/patterns/their past
    case reflectiveQuestion // "why do I keep doing this?"
    case offdomain          // general-knowledge question about the world
}

enum TurnClassifier {

    // MARK: - Lexicons (the single tuning surface)

    /// Whole-message social openers/closers (matched against the normalized
    /// message, or its prefix for greetings that carry a name: "hey memento").
    static let socialPhrases: Set<String> = [
        "hi", "hey", "hello", "yo", "hiya", "heya", "howdy", "good morning", "good afternoon",
        "good evening", "good night", "goodnight", "morning", "evening",
        "how are you", "how's it going", "hows it going", "how are you doing",
        "what's up", "whats up", "sup", "how have you been",
        "thanks", "thank you", "thx", "ty", "thanks a lot", "thank you so much",
        "bye", "goodbye", "see you", "later", "talk soon", "take care"
    ]

    /// Single-token openers used as a greeting prefix ("hello memento",
    /// "hey there"). Two-word social phrases ("good morning") are handled
    /// separately via `socialPhrases`.
    static let greetingPrefixes: Set<String> = [
        "hi", "hey", "hello", "yo", "hiya", "heya", "howdy", "sup",
        "morning", "evening", "thanks", "thx", "ty", "bye", "goodbye"
    ]

    /// Continuer words: a short message made only of these is an acknowledgement.
    static let continuerWords: Set<String> = [
        "yeah", "yea", "yep", "yes", "no", "nah", "ok", "okay", "k", "kk",
        "sure", "cool", "nice", "great", "perfect", "got", "it", "right", "true",
        "fair", "makes", "sense", "i", "guess", "hmm", "hm", "mm", "wow", "oh",
        "haha", "hahaha", "lol", "lmao", "interesting", "totally", "exactly",
        "agreed", "same", "sounds", "good", "thanks", "thank", "you"
    ]

    /// App/assistant-capability questions.
    static let metaPatterns: [String] = [
        #"^(what can you do|what do you do|who are you|what are you)\b"#,
        #"^(how do(es)? (you|this|memento) work)\b"#,
        #"^(are you (an )?ai|are you a (robot|bot|human))\b"#,
        #"^help$"#
    ]

    /// Phrases that point back at the assistant's previous turn.
    static let followupPhrases: [String] = [
        "what do you mean", "tell me more", "say more", "go on", "keep going",
        "like what", "how so", "such as", "for example", "can you elaborate",
        "elaborate", "expand on that", "why is that", "why do you say that",
        "what else", "anything else", "and then", "what about that"
    ]

    /// Deictic tokens that, in a very short question, refer to the prior turn.
    static let deicticWords: Set<String> = ["that", "it", "this", "those", "these", "one"]

    /// Words that make a message an explicit journal ask.
    static let journalWords: Set<String> = [
        "journal", "journals", "entry", "entries", "wrote", "written", "write",
        "logged", "log", "noted", "notes", "diary"
    ]

    /// Retrospective-question openers about their own past.
    static let retrospectivePatterns: [String] = [
        #"^(have|did|when did|how often (do|did|have)|what did) i\b"#,
        #"\bwhat (have|did) i (say|write|mention)\b"#,
        #"\b(lately|recently|last (week|month|year)|this (week|month|year)|past few)\b"#
    ]

    /// First-person pattern markers for reflective questions.
    static let reflectivePatterns: [String] = [
        #"^why (do|am|can't|cant|don't|dont|won't|wont) i\b"#,
        #"^why do i (keep|always|never)\b"#,
        #"^(how can|how do) i (stop|change|improve|get better|deal with|handle)\b"#,
        #"^what (should|could) i\b"#,
        #"^am i\b"#
    ]

    /// Conservative world-fact markers: only used when the message is a
    /// question containing no first/second-person reference at all.
    static let offdomainPatterns: [String] = [
        #"^(who|what|when|where) (is|are|was|were) (the|a|an)\b"#,
        #"\b(capital of|population of|weather|score|won the|price of|stock|news)\b"#,
        #"^(define|explain) (?!my|me)\b"#
    ]

    private static let firstOrSecondPerson: Set<String> = [
        "i", "me", "my", "mine", "myself", "im", "ive", "id", "you", "your", "we"
    ]

    // MARK: - Precompiled packs (spec 029 Amendment A)
    //
    // Each pack is compiled once at first touch of the static — a plain array
    // walk on the hot path, no lock and no pattern-string hash per call (the
    // dictionary cache below cost a lock+hash round trip per pattern, and
    // classification runs per streamed snapshot via the history memo). Options
    // stay empty (case-SENSITIVE), exactly like `range(of:options:)`'s default;
    // `compactMap` drops an invalid pattern, the same silent no-match
    // `range(of:)` gave.

    static let metaRegexes = compile(metaPatterns)
    static let retrospectiveRegexes = compile(retrospectivePatterns)
    static let reflectiveRegexes = compile(reflectivePatterns)
    static let offdomainRegexes = compile(offdomainPatterns)

    static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }

    // MARK: - Classification

    /// Classifies ONLY the current message. `hasHistory` gates `followup` —
    /// without prior turns there is nothing to follow up on.
    static func classify(_ message: String, hasHistory: Bool) -> TurnType {
        let normalized = normalize(message)
        let words = normalized.split(separator: " ").map(String.init)
        let isQuestion = message.contains("?")
            || normalized.hasPrefix("what ") || normalized.hasPrefix("why ")
            || normalized.hasPrefix("how ") || normalized.hasPrefix("when ")
            || normalized.hasPrefix("who ") || normalized.hasPrefix("where ")
            || normalized.hasPrefix("have i") || normalized.hasPrefix("did i")
            || normalized.hasPrefix("am i")

        if normalized.isEmpty { return .acknowledgement }

        // 1. social — exact phrases, or a greeting plus a social/name tail.
        // Journal lexicon always wins (checked here so "hello, what did I write"
        // never lands in phatic). Cap ~8 words (spec 039 R3).
        if words.count <= 8 {
            if socialPhrases.contains(normalized) { return .social }
            if isSocialGreeting(words, isQuestion: isQuestion) { return .social }
        }

        // 2. acknowledgement — ≤ 4 words, all continuers, not a question.
        if words.count <= 4, !isQuestion, words.allSatisfy({ continuerWords.contains($0) }) {
            return .acknowledgement
        }

        // 3. meta — about the app/assistant.
        if matches(normalized, anyOf: metaRegexes) { return .meta }

        // 4. followup — needs history.
        if hasHistory {
            if followupPhrases.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") || normalized.hasSuffix(" " + $0) }) {
                return .followup
            }
            if normalized == "why" || normalized == "why not" || normalized == "really" {
                return .followup
            }
            // Short question whose only content words are deictic ("what about that?").
            if isQuestion, words.count <= 8 {
                let content = words.filter { !stopwordsForDeixis.contains($0) }
                if !content.isEmpty, content.allSatisfy({ deicticWords.contains($0) }) {
                    return .followup
                }
            }
        }

        // 5. journalQuery — journal lexicon or retrospective shape.
        if words.contains(where: { journalWords.contains($0) }) { return .journalQuery }
        if matches(normalized, anyOf: retrospectiveRegexes), mentionsSelf(words) { return .journalQuery }

        // 6. reflectiveQuestion — first-person pattern questions.
        if isQuestion, matches(normalized, anyOf: reflectiveRegexes) { return .reflectiveQuestion }

        // 7. offdomain — a question with zero self/you reference + world markers.
        if isQuestion, !words.contains(where: { firstOrSecondPerson.contains($0) }),
           matches(normalized, anyOf: offdomainRegexes) {
            return .offdomain
        }

        // 8. default: questions go to journalQuery (retrieval decides), and
        // statements are shares — both retrieve, so ambiguity is never deafness.
        return isQuestion ? .journalQuery : .share
    }

    // MARK: - Helpers

    private static let stopwordsForDeixis: Set<String> = [
        "what", "whats", "about", "is", "was", "does", "mean", "means", "do",
        "you", "with", "the", "a", "an", "so", "and", "then", "of"
    ]

    /// Continuer / name tokens allowed after a greeting ("hey there",
    /// "hello memento") without turning the turn into a share.
    private static let socialTailTokens: Set<String> = {
        var tokens = continuerWords
        tokens.insert("memento")
        tokens.insert("there")
        for phrase in socialPhrases where !phrase.contains(" ") {
            tokens.insert(phrase)
        }
        return tokens
    }()

    /// Greeting prefix plus a social remainder: "hello memento", "hey there",
    /// "Hello, how are you". Not a share ("hello I had a long day") and not
    /// a journal ask (journal words already excluded).
    private static func isSocialGreeting(_ words: [String], isQuestion: Bool) -> Bool {
        guard !words.contains(where: { journalWords.contains($0) }) else { return false }
        guard let consumed = leadingGreetingWordCount(words) else { return false }
        let rest = Array(words.dropFirst(consumed))
        if rest.isEmpty { return true }
        let restJoined = rest.joined(separator: " ")
        if socialPhrases.contains(restJoined) { return true }
        // A real question after a greeting ("hello, what's the capital?") is
        // not small talk. Continuer/name tails are statements.
        if isQuestion { return false }
        return rest.allSatisfy { socialTailTokens.contains($0) }
    }

    private static func leadingGreetingWordCount(_ words: [String]) -> Int? {
        if let first = words.first, greetingPrefixes.contains(first) { return 1 }
        if words.count >= 2 {
            let two = words[0] + " " + words[1]
            if socialPhrases.contains(two) { return 2 }
        }
        return nil
    }

    private static func normalize(_ message: String) -> String {
        let lowered = message
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
        // Clause punctuation becomes spaces so "Hello, how are you" matches
        // the social lexicon (spec 039 R3). Sentence-ending marks stay
        // trimmed from the ends.
        let spaced = lowered.map { ch -> Character in
            switch ch {
            case ",", ";", ":", "…": return " "
            default: return ch
            }
        }
        return String(spaced)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .split { $0.isWhitespace }
            .joined(separator: " ")
    }

    private static func matches(_ text: String, anyOf regexes: [NSRegularExpression]) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regexes.contains { regex in
            regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    // MARK: - Regex cache

    /// Compile-once cache, kept for the string-pattern lookups the tests pin.
    /// The classify() hot path walks the precompiled arrays above instead.
    /// Options stay empty (case-SENSITIVE), exactly like `range(of:)`'s
    /// default; the packs above are all-lowercase and are matched against the
    /// lowercased message, so sensitivity never mattered — but it must not
    /// change. Compiled regexes are immutable and thread-safe; the lock only
    /// guards the dictionary.
    private static let regexLock = NSLock()
    private static var regexCache: [String: NSRegularExpression] = [:]

    /// Internal (not private) so tests can assert the cache returns the same
    /// compiled instance. Returns nil only for an invalid pattern — the same
    /// silent no-match `range(of:)` gave.
    static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        regexCache[pattern] = regex
        return regex
    }

    private static func mentionsSelf(_ words: [String]) -> Bool {
        words.contains { ["i", "my", "me", "im", "ive"].contains($0) }
    }
}
