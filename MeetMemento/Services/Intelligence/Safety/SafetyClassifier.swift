//
//  SafetyClassifier.swift
//  MeetMemento
//
//  Deterministic, precision-biased pre-model safety classification (spec 026).
//  Never calls AFM — lexicon/regex only, same posture as TurnClassifier.
//

import Foundation

enum SafetyClassifier {

    // MARK: - Public API

    /// Classify a chat user message (or free-text input to summarize/estimate).
    static func classify(_ text: String) -> SafetyDecision {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return .clear }

        var hits: [SafetyCategory] = []

        if matches(normalized, anyOf: csamRegexes) { hits.append(.csam) }
        if matches(normalized, anyOf: terrorismRegexes) { hits.append(.terrorismMassViolence) }
        if matches(normalized, anyOf: violenceRegexes) { hits.append(.violenceOthers) }
        if matches(normalized, anyOf: crisisRegexes) { hits.append(.selfHarmCrisis) }
        if matches(normalized, anyOf: hateRegexes) { hits.append(.hateHarassment) }
        if matches(normalized, anyOf: jailbreakRegexes) { hits.append(.jailbreak) }
        if matches(normalized, anyOf: regulatedAdviceRegexes) { hits.append(.regulatedAdvice) }

        guard let top = hits.min(by: { $0.precedence < $1.precedence }) else {
            return .clear
        }
        return SafetyDecision(
            category: top,
            action: SafetyRouter.action(for: top),
            confidence: 1
        )
    }

    /// Same classifier for journal entry text (phase-2 surfaces; available now).
    static func classifyJournalText(_ text: String) -> SafetyDecision {
        classify(text)
    }

    // MARK: - Pattern packs

    /// Sexual content involving minors — hard refuse.
    static let csamPatterns: [String] = [
        #"\b(child|children|kid|kids|minor|minors|underage|under[\s-]?age)\b.{0,40}\b(sex|sexual|porn|nude|naked|explicit)\b"#,
        #"\b(sex|sexual|porn|nude|naked|explicit)\b.{0,40}\b(child|children|kid|kids|minor|minors|underage)\b"#,
        #"\b(csam|child\s*porn)\b"#
    ]

    /// Terrorism / mass violence as actionable assistance (not pure history trivia).
    static let terrorismPatterns: [String] = [
        #"\b(how (do|can|to)|help me|teach me|show me|plan|build|make|assemble)\b.{0,60}\b(bomb|explosive|ied|pipe bomb|mass (shooting|casualty)|terror(ist|ism)?)\b"#,
        #"\b(bomb|explosive|ied|pipe bomb)\b.{0,40}\b(how (do|can|to)|instructions|recipe|build|make)\b"#,
        #"\b(carry out|commit|plan)\b.{0,40}\b(terror(ist|ism)? attack|mass (murder|shooting|killing)|9[\s/]?11 (attack|replay)?)\b"#,
        #"\b(glorify|praise|celebrate)\b.{0,30}\b(terror(ist|ism)?|mass shooting|9[\s/]?11)\b"#,
        #"\b(join|recruit)\b.{0,30}\b(isis|al[\s-]?qaeda|terror(ist)? (group|cell))\b"#
    ]

    /// Violence / harm toward others as assistance or planning.
    static let violencePatterns: [String] = [
        #"\b(how (do|can|to)|help me|teach me|show me)\b.{0,50}\b(kill|murder|stab|poison|strangle|hurt|harm|attack)\b.{0,40}\b(him|her|them|someone|my (boss|partner|ex|wife|husband|neighbor))\b"#,
        #"\b(kill|murder|stab|poison|hurt|harm)\b.{0,30}\b(my (boss|partner|ex|wife|husband|neighbor)|him|her|them)\b.{0,20}\b(how|plan|tonight|tomorrow)\b"#,
        #"\b(revenge plan|plan (my )?revenge|hire a hitman|hitman)\b"#,
        #"\b(write|draft)\b.{0,30}\b(threat(ening)? letter|death threat)\b"#
    ]

    /// Acute self-harm / suicide / goodbye notes — static crisis card.
    static let crisisPatterns: [String] = [
        #"\b(kill myself|killing myself|end my life|take my (own )?life|suicide|suicidal)\b"#,
        #"\b(hurt|harm|cut)\s+myself\b"#,
        #"\b(i want to die|i('m| am) going to (die|kill myself)|don'?t want to (be )?alive)\b"#,
        #"\b(better off without me|no (point|reason) (in|to) (living|being here|anything anymore))\b"#,
        #"\b(write|draft)\b.{0,40}\b(goodbye|suicide|final)\s+(note|letter)\b"#,
        #"\b(not be around (much )?longer|won'?t be here (much )?longer)\b"#,
        #"\bi don'?t see the point of anything anymore\b"#
    ]

    /// Calls to harm a protected class / group — hard refuse assistance.
    static let hatePatterns: [String] = [
        #"\b(how (do|can|to)|help me)\b.{0,40}\b(attack|hurt|harm|kill)\b.{0,40}\b(jews|muslims|christians|immigrants|gays|trans|black people|white people)\b"#,
        #"\b(genocide|ethnic cleansing)\b.{0,30}\b(how|plan|start)\b"#
    ]

    /// Jailbreak / persona override attempts.
    static let jailbreakPatterns: [String] = [
        #"\b(ignore|disregard|forget)\b.{0,40}\b(system (prompt|instructions)|your (rules|instructions|guidelines)|previous instructions)\b"#,
        #"\b(dan mode|do anything now|developer mode|jailbreak)\b"#,
        #"\byou are now\b.{0,40}\b(unrestricted|uncensored|without (rules|limits|guardrails))\b"#,
        #"\b(pretend|act as if)\b.{0,40}\b(no (safety|content) (rules|filters|policies)|you have no restrictions)\b"#
    ]

    /// Directive medical / legal / financial advice seeking → constrained continue.
    static let regulatedAdvicePatterns: [String] = [
        #"\b(should i|i should|what should i|give me a plan|tell me what to do)\b"#,
        #"\b(diagnose|diagnosis|do i have|am i (depressed|bipolar|adhd)|mental health conditions?)\b"#,
        #"\b(prove (it|i have)|do my entries prove)\b"#,
        #"\b(prescribe|prescription|dosage|medication plan)\b"#,
        #"\b(legal advice|is it legal|sue them|draft a (will|contract))\b"#,
        #"\b(invest(ment)? advice|which stock|guaranteed return)\b"#
    ]

    // MARK: - Precompiled packs (spec 029 Amendment A)
    //
    // Each pack is compiled once at first touch of the static — a plain array
    // walk on the hot path, no lock and no long-pattern-string hash per call
    // (the dictionary cache below cost up to ~24 lock+hash round trips per
    // classification, and OutputSafetyScanner re-runs classification per
    // streamed snapshot). `compactMap` drops an invalid pattern, the same
    // silent no-match the `try?` compile gave. Options stay `.caseInsensitive`,
    // exactly like the per-call compile these packs always used.

    static let csamRegexes = compile(csamPatterns)
    static let terrorismRegexes = compile(terrorismPatterns)
    static let violenceRegexes = compile(violencePatterns)
    static let crisisRegexes = compile(crisisPatterns)
    static let hateRegexes = compile(hatePatterns)
    static let jailbreakRegexes = compile(jailbreakPatterns)
    static let regulatedAdviceRegexes = compile(regulatedAdvicePatterns)

    static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    // MARK: - Helpers

    /// Collapses runs of whitespace (same `\s+` the old inline regex used).
    private static let whitespaceRunRegex = try? NSRegularExpression(pattern: #"\s+"#, options: [.caseInsensitive])

    static func normalize(_ text: String) -> String {
        let lowered = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = whitespaceRunRegex else { return lowered }
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        return regex.stringByReplacingMatches(in: lowered, options: [], range: range, withTemplate: " ")
    }

    static func matches(_ text: String, anyOf regexes: [NSRegularExpression]) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for regex in regexes {
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// String-pattern entry point, kept for OutputSafetyScanner's packs and the
    /// parity tests. Off the classify() hot path — that walks the precompiled
    /// arrays above.
    static func matches(_ text: String, any patterns: [String]) -> Bool {
        for pattern in patterns {
            if let regex = cachedRegex(pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Regex cache

    /// Compile-once cache for callers that hold string patterns
    /// (OutputSafetyScanner). Compiled regexes are immutable and thread-safe;
    /// the lock only guards the dictionary. Same `.caseInsensitive` semantics
    /// as the precompiled packs above.
    private static let regexLock = NSLock()
    private static var regexCache: [String: NSRegularExpression] = [:]

    /// Internal (not private) so tests can assert the cache returns the same
    /// compiled instance. Returns nil only for an invalid pattern — the same
    /// silent no-match the old `try?` gave.
    static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        regexCache[pattern] = regex
        return regex
    }
}
