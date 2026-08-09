//
//  FoundationModelsIntelligenceService.swift
//  MeetMemento
//
//  THE single Apple Foundation Models importer (architecture principle P3 /
//  REQ-INT-001, spec 017 R1). Nothing else in the app imports FoundationModels;
//  everything depends on the `IntelligenceService` protocol. If a second file
//  imports FoundationModels, the CI gate
//  (scripts/ci/check_single_intelligence_importer.sh) fails.
//
//  This pass: on-device (`SystemLanguageModel`, Z0) generation for Ask + Chat
//  summary, replacing the former server-side `chat` / `summarize-chat` functions.
//  The Private Cloud Compute (Z1) path is wired behind `if #available(iOS 27)`
//  + availability so it auto-upgrades once the app is approved (spec 017 R2).
//

import Foundation
import FoundationModels

// MARK: - Structured output (guided generation, no JSON parsing) — spec 017 R5

/// The Ask reply, produced by constrained decoding. `citedRefs` are the [ref]
/// numbers from the context block the model actually used — reconciled against
/// the provided set so a citation can never be fabricated.
@Generable
struct AskAnswer {
    @Guide(description: "Optional short heading for analytical, multi-part answers. Empty for casual replies.")
    let heading1: String?

    @Guide(description: "Optional rare subheading. Usually empty.")
    let heading2: String?

    @Guide(description: "The reply, in plain spoken prose — no markdown, no bullet points, no headings, no emoji, and no reference markers such as [ref 2], (ref 2), ref 2, or [2]. Name an entry by its date or subject instead. Second person. Three to ten sentences.")
    let body: String

    @Guide(description: "The [ref] numbers of the journal entries from the context block that were actually referenced. Empty if none. These belong here only — never in the body.")
    let citedRefs: [Int]
}

/// Closed-vocab onboarding estimate. Theme ids are reconciled against ThemeCatalog in Swift.
@Generable
struct ProfileEstimateAnswer {
    @Guide(description: "3 to 4 primary theme ids from the provided catalog only.")
    let themeIds: [String]

    @Guide(description: "Up to 2 secondary theme ids from the catalog. May be empty.")
    let secondaryThemeIds: [String]

    @Guide(description: "1 to 3 short third-person sentences guiding tone and questions. Under 400 characters. No therapy language.")
    let promptLens: String
}

// MARK: - Service

final class FoundationModelsIntelligenceService: IntelligenceService, @unchecked Sendable {
    static let shared = FoundationModelsIntelligenceService()

    init() {}

    private let stateLock = NSLock()

    /// Cached availability. Once the model reports `.available` it stays
    /// available for the process, so we resolve it once instead of querying
    /// `SystemLanguageModel.default.availability` on every ask/summary/estimate.
    private var cachedAvailability: IntelligenceAvailability?

    /// A prewarmed session held so the first send doesn't pay the cold model
    /// load. Prewarming any session loads the shared on-device model weights,
    /// which benefits the next `respond` regardless of which session runs it.
    /// (Phase 3 extends this into a per-conversation persistent session.)
    private var warmSession: LanguageModelSession?
    private var warmInstructions: String?

    // MARK: Availability

    func availability() async -> IntelligenceAvailability {
        stateLock.lock()
        if case .available = cachedAvailability, let cached = cachedAvailability {
            stateLock.unlock()
            return cached
        }
        stateLock.unlock()

        // On-device (Z0) only against the iOS 26 SDK. The Private Cloud Compute
        // (Z1) path — `PrivateCloudComputeLanguageModel`, reasoning levels, quota
        // governance (spec 017 R2/R3) — is an iOS-27-SDK type; it re-enables when
        // the app builds against Xcode 27 and is approved for PCC. On-device-first.
        let resolved: IntelligenceAvailability
        switch SystemLanguageModel.default.availability {
        case .available:
            resolved = .available(.onDevice)
        case .unavailable(let reason):
            resolved = .unavailable(Self.map(reason))
        @unknown default:
            resolved = .unavailable(.other("Intelligence is unavailable on this device."))
        }
        // Only cache the positive result — an "unavailable" (still downloading)
        // can flip to available later, so keep re-checking that case.
        if case .available = resolved {
            stateLock.lock(); cachedAvailability = resolved; stateLock.unlock()
        }
        return resolved
    }

    // MARK: Prewarm

    /// Warms the on-device model ahead of the first send (call when the chat
    /// view appears / the input gains focus). Cheap and idempotent; safe to
    /// call when the model is unavailable (the session simply can't run).
    func prewarm() {
        let instructions = PromptRegistry.instructions(
            for: .ask,
            personalization: PromptPersonalization.fromLocalProfile()
        ).text
        stateLock.lock()
        let needsNew = (warmSession == nil || warmInstructions != instructions)
        if needsNew {
            let session = LanguageModelSession(instructions: instructions)
            warmSession = session
            warmInstructions = instructions
            stateLock.unlock()
            session.prewarm()
        } else {
            let session = warmSession
            stateLock.unlock()
            session?.prewarm()
        }
    }

    private static func map(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> IntelligenceUnavailableReason {
        switch reason {
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .modelNotReady
        case .modelNotReady: return .modelNotReady
        @unknown default: return .other("On-device intelligence is unavailable right now.")
        }
    }

    // MARK: Ask

    /// Everything the model call needs, computed once and shared by the
    /// one-shot `ask` and the streaming `askStream`.
    private struct AskPreparation {
        let zone: IntelligenceZone
        let retrieval: RetrievalResult
        let stance: TurnStance
        let prompt: String
        let resolved: ResolvedPrompt
    }

    /// Availability → turn classification → retrieval → stance → prompt +
    /// instructions. Pure aside from the availability await.
    private func prepareAsk(question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskPreparation {
        let availability = await availability()
        guard case .available(let zone) = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        // Conversational turn architecture: classify the current message,
        // decide retrieval by policy, then hand the model an explicit stance —
        // logic decides the stance, the prompt obeys it.
        let turn = TurnClassifier.classify(question, hasHistory: !history.isEmpty)
        let retrieval: RetrievalResult
        switch RetrievalPolicy.mode(for: turn) {
        case .none:
            retrieval = .empty
        case .reusePrevious:
            if let anchor = RetrievalPolicy.followupAnchor(history: history) {
                retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: anchor), entries: entries)
            } else {
                retrieval = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question, historyContext: Self.historyContext(history)),
                    entries: entries
                )
            }
        case .currentOnly(let highBar):
            retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: question, highBar: highBar), entries: entries)
        case .currentWeighted:
            retrieval = EntryRetriever.retrieve(
                RetrievalQuery(currentMessage: question, historyContext: Self.historyContext(history)),
                entries: entries
            )
        }
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let prompt = Self.buildAskPrompt(question: question, history: history, retrieval: retrieval, stance: stance)
        let resolved = PromptRegistry.instructions(
            for: .ask,
            degraded: false,
            personalization: PromptPersonalization.fromLocalProfile()
        )
        return AskPreparation(zone: zone, retrieval: retrieval, stance: stance, prompt: prompt, resolved: resolved)
    }

    /// Builds the final `AskResult` (citations reconciled, reference markers
    /// stripped) from either the whole-answer `respond` or the last streamed
    /// snapshot. Reference stripping happens here so the live reply and the
    /// JSON ChatService persists both carry the cleaned body.
    private func makeResult(heading1: String?, heading2: String?, body: String, citedRefs: [Int],
                            prep: AskPreparation, question: String) -> AskResult {
        let citations = Self.reconcileCitations(
            citedRefs, retrieval: prep.retrieval, question: question
        )
        return AskResult(
            heading1: heading1?.isEmpty == true ? nil : heading1,
            heading2: heading2?.isEmpty == true ? nil : heading2,
            body: Self.strippingReferenceMarkers(body),
            citations: citations,
            zoneUsed: prep.zone,
            wasDegraded: false,
            promptVersion: prep.resolved.version,
            modelIdentifier: Self.modelIdentifier(for: prep.zone)
        )
    }

    func ask(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskResult {
        let prep = try await prepareAsk(question: question, history: history, entries: entries)
        let session = LanguageModelSession(instructions: prep.resolved.text)
        do {
            let response = try await session.respond(
                to: prep.prompt,
                generating: AskAnswer.self,
                options: GenerationOptions(temperature: 0.7)
            )
            let answer = response.content
            return makeResult(heading1: answer.heading1, heading2: answer.heading2,
                              body: answer.body, citedRefs: answer.citedRefs,
                              prep: prep, question: question)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    func askStream(_ question: String, history: [ChatTurn], entries: [Entry]) -> AsyncThrowingStream<AskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prep = try await prepareAsk(question: question, history: history, entries: entries)
                    let session = LanguageModelSession(instructions: prep.resolved.text)
                    let stream = session.streamResponse(
                        to: prep.prompt,
                        generating: AskAnswer.self,
                        options: GenerationOptions(temperature: 0.7)
                    )
                    // The journals retrieval surfaced for a grounded turn — known
                    // now, before the first token. Emitting them on every delta
                    // lets the "Reviewed your journals" link appear right away
                    // instead of waiting for the model's final citedRefs. Empty on
                    // non-grounded turns (reconcile returns [] when not grounded).
                    // `.final` supersedes these with the model's cited subset.
                    let reviewed = Self.reconcileCitations(
                        [], retrieval: prep.retrieval, question: question
                    )
                    var lastHeading1: String?
                    var lastHeading2: String?
                    var lastBody = ""
                    var lastCitedRefs: [Int] = []
                    for try await snapshot in stream {
                        let content = snapshot.content
                        lastBody = content.body ?? ""
                        lastHeading1 = content.heading1 ?? nil
                        lastHeading2 = content.heading2 ?? nil
                        if let refs = content.citedRefs { lastCitedRefs = refs }
                        // Emit the cleaned body-so-far so the live reply matches
                        // exactly what gets persisted at the end.
                        continuation.yield(.delta(
                            bodySoFar: Self.strippingReferenceMarkers(lastBody),
                            heading1: lastHeading1?.isEmpty == true ? nil : lastHeading1,
                            heading2: lastHeading2?.isEmpty == true ? nil : lastHeading2,
                            reviewedCitations: reviewed
                        ))
                    }
                    let result = makeResult(heading1: lastHeading1, heading2: lastHeading2,
                                            body: lastBody, citedRefs: lastCitedRefs,
                                            prep: prep, question: question)
                    continuation.yield(.final(result))
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.mapGenerationError(error))
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: IntelligenceError.generationFailed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Profile estimate (onboarding)

    func estimateProfile(reflection: String) async throws -> ProfileEstimateResult {
        let availability = await availability()
        guard case .available(let zone) = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntelligenceError.generationFailed("Reflection text is empty.")
        }

        let resolved = PromptRegistry.instructions(for: .profileEstimate, degraded: false)
        let session = LanguageModelSession(instructions: resolved.text)
        let prompt = Self.buildProfileEstimatePrompt(reflection: trimmed)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: ProfileEstimateAnswer.self,
                options: GenerationOptions(temperature: 0.4)
            )
            let answer = response.content
            let primary = ThemeCatalog.validate(answer.themeIds, max: ThemeCatalog.defaultSuggestionCount)
            let secondary = ThemeCatalog.validate(answer.secondaryThemeIds, max: 2)
                .filter { !primary.contains($0) }
            var lens = answer.promptLens.trimmingCharacters(in: .whitespacesAndNewlines)
            if lens.count > PromptRegistry.maxPromptLensChars {
                lens = String(lens.prefix(PromptRegistry.maxPromptLensChars))
            }
            // If the model returned nothing usable, fall back to keyword overlap.
            let themes = primary.isEmpty
                ? ThemeCatalog.suggestFromKeywords(trimmed)
                : primary
            return ProfileEstimateResult(
                themeIds: themes,
                secondaryThemeIds: secondary,
                promptLens: lens,
                zoneUsed: zone,
                wasDegraded: false,
                promptVersion: resolved.version,
                modelIdentifier: Self.modelIdentifier(for: zone)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    private static func buildProfileEstimatePrompt(reflection: String) -> String {
        // Compact catalog projection — id + display name only — to protect context.
        let catalogLines = ThemeCatalog.all
            .map { "\($0.id): \($0.displayName)" }
            .joined(separator: "\n")
        let cappedReflection = reflection.count > 800
            ? String(reflection.prefix(800)) + "…"
            : reflection
        return """
        Catalog (id: DisplayName) — choose only from these ids:
        \(catalogLines)

        Their reflection:
        \"\(cappedReflection)\"
        """
    }

    // MARK: Summarize

    func summarizeConversation(_ turns: [ChatTurn]) async throws -> String {
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let resolved = PromptRegistry.instructions(for: .summary)
        let session = LanguageModelSession(instructions: resolved.text)
        let conversation = turns.map { turn in
            (turn.role == .user ? "User: " : "Assistant: ") + turn.text
        }.joined(separator: "\n")
        let prompt = "Here is the conversation to summarize:\n\n\(conversation)"

        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.7))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt assembly

    /// Recent history condensed for the retrieval assist vector (not the prompt).
    private static func historyContext(_ history: [ChatTurn]) -> String? {
        guard !history.isEmpty else { return nil }
        let condensed = history.suffix(4).map { String($0.text.prefix(300)) }.joined(separator: " ")
        return condensed.isEmpty ? nil : condensed
    }

    private static func buildAskPrompt(question: String, history: [ChatTurn], retrieval: RetrievalResult, stance: TurnStance) -> String {
        // The stance line is the first thing the model reads for this turn —
        // the deterministic instruction that stops it from grounding casual
        // conversation in journal entries.
        var parts: [String] = [stance.promptLine]
        if !retrieval.contextBlock.isEmpty {
            // Frame as optional evidence so the model does not treat the block
            // as a script to paraphrase ("you wrote this, this, and this").
            parts.append(
                "Journal evidence (use only if this turn's stance needs it; do not summarize all of it):\n"
                + retrieval.contextBlock
            )
        } else if stance == .noMatch || stance.isGrounded {
            parts.append("[No journal entries matched this topic]")
        }
        // Casual / about-app / outside-scope / sharing-without-context turns get
        // no journal block at all — the stance line already says how to reply.
        // Six turns keeps ample thread context while trimming the prompt the
        // small on-device model has to ingest (faster time-to-first-token).
        let recent = history.suffix(6)
        if !recent.isEmpty {
            let convo = recent
                .map { ($0.role == .user ? "You: " : "Memento: ") + String($0.text.prefix(320)) }
                .joined(separator: "\n")
            parts.append("Conversation so far (most recent last):\n\(convo)")
            parts.append(
                "Do not reuse openings, questions, or entry summaries already present in Conversation so far."
            )
        }
        parts.append("The person's latest message: \(question)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Reference-marker stripping

    /// Removes `[ref 2]`, `(ref 2)`, `ref 2`, and bare `[2]` from a reply.
    ///
    /// The prompt and the `body` @Guide both ban these, but the `[ref N]` labels
    /// are sitting right there in the model's context as the naming convention
    /// for entries, and a small on-device model leaks them into prose. Nothing
    /// downstream strips markers — `RichTextParser` only handles bold, italic,
    /// and bullets — so anything the model writes reaches the screen verbatim.
    /// This is the backstop.
    ///
    /// Inline citations return in a later release; this whole function goes
    /// away then, along with the prompt bans.
    static func strippingReferenceMarkers(_ body: String) -> String {
        // Ordered: bracketed/parenthesised ref forms, then bare square-bracket
        // numbers, then a bare "ref 2". Each tolerates lists ("ref 1 and 2").
        let numberList = #"\d+(?:\s*(?:,|and|&)\s*\d+)*"#
        let patterns = [
            #"\s*[\[(]\s*refs?\.?\s*#?"# + numberList + #"\s*[\])]"#,
            #"\s*\[\s*"# + numberList + #"\s*\]"#,
            #"\s*\brefs?\.?\s*#?"# + numberList + #"\b"#
        ]

        var out = body
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }

        // Tidy what removal left behind: a space before punctuation, doubled
        // spaces, and a space before a closing bracket.
        let cleanups: [(String, String)] = [
            (#"\s+([,.;:!?])"#, "$1"),
            (#"[ \t]{2,}"#, " "),
            (#"\(\s*\)"#, "")
        ]
        for (pattern, template) in cleanups {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: template
            )
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Citation reconciliation (the anti-fabrication guard)

    private static let maxCitations = 3

    private static func reconcileCitations(_ refs: [Int], retrieval: RetrievalResult, question: String) -> [AskCitation] {
        // Show "Reviewed your journals" whenever retrieval produced a real,
        // non-ambient match — the exact condition the stance uses to decide
        // `.journalGrounded`. This is known before generation, so the link can be
        // emitted from the first delta (via reviewedCitations) and stays identical
        // through the final reconcile: it appears right away and never vanishes.
        // Ambient/empty retrieval (casual chat, or a "no matches" journal ask)
        // still yields no citations.
        guard !retrieval.isEmpty, !retrieval.isAmbient else { return [] }
        let byRef = Dictionary(uniqueKeysWithValues: retrieval.entries.map { ($0.ref, $0) })
        // Prefer the entries the model actually cited; fall back to the top
        // reviewed entries when it cited nothing (or nothing valid), so the set is
        // always non-empty for a real match and the link stays stable.
        let chosenRefs: [Int]
        if refs.isEmpty {
            chosenRefs = retrieval.entries.prefix(maxCitations).map(\.ref)
        } else {
            var seen = Set<Int>()
            let valid = refs.filter { byRef[$0] != nil && seen.insert($0).inserted }
            chosenRefs = valid.isEmpty ? retrieval.entries.prefix(maxCitations).map(\.ref) : valid
        }
        return chosenRefs.prefix(maxCitations).compactMap { ref in
            guard let entry = byRef[ref] else { return nil }
            return AskCitation(
                entryId: entry.id,
                entryDate: entry.date,
                excerpt: Self.previewExcerpt(entry.text, query: question)
            )
        }
    }

    private static func previewExcerpt(_ text: String, query: String, window: Int = 120) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > window else { return clean }
        // Center on the first query-term hit, else take the start.
        let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 }
        let lower = clean.lowercased()
        var start = clean.startIndex
        for term in terms {
            if let r = lower.range(of: term) {
                start = r.lowerBound
                break
            }
        }
        let from = clean.index(start, offsetBy: -min(30, clean.distance(from: clean.startIndex, to: start)), limitedBy: clean.startIndex) ?? clean.startIndex
        let to = clean.index(from, offsetBy: window, limitedBy: clean.endIndex) ?? clean.endIndex
        var excerpt = String(clean[from..<to])
        if from != clean.startIndex { excerpt = "…" + excerpt }
        if to != clean.endIndex { excerpt += "…" }
        return excerpt
    }

    // MARK: - Errors & identifiers

    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> IntelligenceError {
        // Guardrail refusals are a *designed* empty state, not a failure.
        switch error {
        case .guardrailViolation:
            return .guardrailRefusal
        default:
            return .generationFailed(error.localizedDescription)
        }
    }

    private static func modelIdentifier(for zone: IntelligenceZone) -> String {
        switch zone {
        case .onDevice: return "apple.system.on-device"
        case .privateCloud: return "apple.pcc"
        }
    }
}
