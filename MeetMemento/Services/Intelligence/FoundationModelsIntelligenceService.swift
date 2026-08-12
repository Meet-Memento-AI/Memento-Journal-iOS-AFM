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
//  Per-request orchestration pipeline (spec 017 R2/R3/R9):
//    availability → QuotaGovernor.capability → ModelRouter.resolve →
//    GenerationRequest (zone set BEFORE the call) → PromptRegistry.resolve →
//    ContextBudget(runtime contextSize) → generate → GenerationOutcome
//    (zoneUsed / modelIdentifier / wasDegraded / latency).
//
//  Session architecture (spec 017 R9 Task 11 — DECIDED): stateless
//  per-request session assembly. Each generation constructs a fresh
//  `LanguageModelSession` from registry instructions + assembled prompt; the
//  caller owns the transcript (LocalChatStore), retrieval is deterministic,
//  and followup grounding is re-derived (RetrievalPolicy.followupAnchor).
//  iOS 27 Dynamic Profiles are a possible future optimization, not a
//  dependency.
//
//  The Private Cloud Compute (Z1) path: `PrivateCloudComputeLanguageModel`
//  does not exist in the iOS 26 SDK, so the PCC seam (`PCCSessionProviding`)
//  has exactly one implementation — `UnavailablePCCProvider`. The router
//  therefore resolves Z1 rows to the Z0 baseline (honestly undegrated; see
//  ModelRouter). The iOS 27 SDK pass fills the seam and Z1 activates with no
//  call-site changes.
//

import Foundation
import FoundationModels
import Synchronization

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

// MARK: - PCC seam (spec 017 R2/R7)

/// The slot the iOS 27 SDK pass fills with a PCC-backed session factory.
/// Pure protocol — conforming to it requires no FoundationModels import.
protocol PCCSessionProviding: Sendable {
    /// Whether a Z1 session can be constructed at all on this build.
    var isSupported: Bool { get }
}

/// The only implementation that can exist on the iOS 26 SDK.
struct UnavailablePCCProvider: PCCSessionProviding {
    var isSupported: Bool { false }
}

// MARK: - Service

final class FoundationModelsIntelligenceService: IntelligenceService, @unchecked Sendable {
    static let shared = FoundationModelsIntelligenceService()

    private let quotaGovernor: QuotaGovernor
    private let pccProvider: PCCSessionProviding

    init(
        quotaGovernor: QuotaGovernor = .shared,
        pccProvider: PCCSessionProviding = UnavailablePCCProvider()
    ) {
        self.quotaGovernor = quotaGovernor
        self.pccProvider = pccProvider
    }

    /// Warm-path state, guarded by a `Synchronization.Mutex` — async-safe scoped
    /// locking (`NSLock.lock()` is unavailable from async contexts and an error
    /// in Swift 6 mode). All access is synchronous `withLock`, so the lock can
    /// never be held across a suspension point.
    private struct WarmState {
        /// Cached availability. Once the model reports `.available` it stays
        /// available for the process, so we resolve it once instead of querying
        /// `SystemLanguageModel.default.availability` on every ask/summary/estimate.
        var cachedAvailability: IntelligenceAvailability?

        /// A prewarmed session held so the first send doesn't pay the cold model
        /// load. Prewarming any session loads the shared on-device model weights,
        /// which benefits the next `respond` regardless of which session runs it.
        var warmSession: LanguageModelSession?
        var warmInstructions: String?
    }

    private let state = Mutex(WarmState())

    // MARK: Availability

    func availability() async -> IntelligenceAvailability {
        if let cached = state.withLock({ $0.cachedAvailability }), case .available = cached {
            return cached
        }

        // Availability is device-model availability (Z0). Which zone a given
        // request actually runs in is the router's decision (`resolveRoute`).
        let resolved: IntelligenceAvailability
        switch SystemLanguageModel.default.availability {
        case .available:
            resolved = .available(.z0Device)
        case .unavailable(let reason):
            resolved = .unavailable(Self.map(reason))
        @unknown default:
            resolved = .unavailable(.other("Intelligence is unavailable on this device."))
        }
        // Only cache the positive result — an "unavailable" (still downloading)
        // can flip to available later, so keep re-checking that case.
        if case .available = resolved {
            state.withLock { $0.cachedAvailability = resolved }
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
        // Reuse the warm session while instructions are unchanged; build (and
        // cache) a fresh one when personalization shifts. `prewarm()` runs
        // outside the lock — it's the slow part.
        let session: LanguageModelSession = state.withLock { warm in
            if let existing = warm.warmSession, warm.warmInstructions == instructions {
                return existing
            }
            let created = LanguageModelSession(instructions: instructions)
            warm.warmSession = created
            warm.warmInstructions = instructions
            return created
        }
        session.prewarm()
    }

    private static func map(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> IntelligenceUnavailableReason {
        switch reason {
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .modelNotReady
        case .modelNotReady: return .modelNotReady
        @unknown default: return .other("On-device intelligence is unavailable right now.")
        }
    }

    // MARK: Routing

    /// Resolve the route for one request: pin → quota capability → table.
    /// The pin is read at the router boundary (REQ-INT-004: router-level
    /// override, no surface can bypass it).
    private func resolveRoute(for intent: GenerationIntent) async -> ResolvedRoute {
        let capability: PCCCapability
        if pccProvider.isSupported {
            capability = await quotaGovernor.capability(for: intent)
        } else {
            capability = .sdkUnsupported
        }
        return ModelRouter.resolve(
            intent: intent,
            pinnedToDevice: PreferencesService.shared.processOnDeviceOnly,
            pccCapability: capability
        )
    }

    /// The runtime context budget (spec 017 R9 / CONSTITUTION §4 rule 5:
    /// never hardcode the window — it differs by device, OS, and zone).
    /// `SystemLanguageModel.contextSize` is an iOS-27-SDK API; until the
    /// Xcode 27 pass, the single documented fallback in ContextBudget stands in.
    private static func currentBudget() -> ContextBudget {
        ContextBudget(contextTokens: ContextBudget.fallbackOnDeviceWindowTokens)
    }

    /// One content-free log line per generation (CONSTITUTION §4 rule 3;
    /// instrumentation for spec 022 — never journal content).
    private static func logOutcome(
        intent: GenerationIntent,
        route: ResolvedRoute,
        promptVersion: String,
        latency: Duration,
        budget: ContextBudget,
        entriesInContext: Int
    ) {
        let ms = latency.components.seconds * 1000 + latency.components.attoseconds / 1_000_000_000_000_000
        AppLogger.log(
            "🧠 [Intelligence] \(intent) zone=\(route.executionZone.identifier)"
            + " (requested=\(route.requestedZone.identifier), \(route.reason.rawValue))"
            + " degraded=\(route.wasDegraded) prompt=\(promptVersion)"
            + " latency=\(ms)ms window=\(budget.contextTokens)tok entries=\(entriesInContext)"
        )
    }

    // MARK: Ask — shared preparation

    /// Everything decided before the model runs. Deterministic given
    /// (question, history, entries, preferences) — logic decides the stance,
    /// the prompt obeys it.
    private struct AskPreparation {
        let route: ResolvedRoute
        let request: GenerationRequest
        let instructions: ResolvedPrompt
        let prompt: String
        let retrieval: RetrievalResult
        let stance: TurnStance
        let budget: ContextBudget
    }

    private func prepareAsk(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskPreparation {
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let route = await resolveRoute(for: .ask)
        let budget = Self.currentBudget()
        // Degraded routes narrow retrieval (spec 017 R2's degradation column).
        let limits = route.useDegradedPrompt
            ? RetrievalLimits(budget: budget).narrowed()
            : RetrievalLimits(budget: budget)

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
                retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: anchor), entries: entries, limits: limits)
            } else {
                retrieval = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question, historyContext: Self.historyContext(history, budget: budget)),
                    entries: entries,
                    limits: limits
                )
            }
        case .currentOnly(let highBar):
            retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: question, highBar: highBar), entries: entries, limits: limits)
        case .currentWeighted:
            retrieval = EntryRetriever.retrieve(
                RetrievalQuery(currentMessage: question, historyContext: Self.historyContext(history, budget: budget)),
                entries: entries,
                limits: limits
            )
        }
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let prompt = Self.buildAskPrompt(question: question, history: history, retrieval: retrieval, stance: stance, budget: budget)

        let instructions = PromptRegistry.resolve(
            intent: .ask,
            zone: route.executionZone,
            degraded: route.useDegradedPrompt,
            personalization: PromptPersonalization.fromLocalProfile()
        )
        // Zone set BEFORE the call (spec 014 R1) — the request records what
        // the router decided, and the outcome records what actually ran.
        let request = GenerationRequest(
            intent: .ask,
            zone: route.executionZone,
            allowsDegradation: ModelRouter.row(for: .ask).degradedZone != nil,
            promptVersion: instructions.version,
            toolsEnabled: false
        )
        return AskPreparation(
            route: route,
            request: request,
            instructions: instructions,
            prompt: prompt,
            retrieval: retrieval,
            stance: stance,
            budget: budget
        )
    }

    /// Builds the final `AskResult` from either the whole-answer `respond` or
    /// the last streamed snapshot: citations reconciled against retrieval,
    /// reference markers stripped (so the live reply and the JSON ChatService
    /// persists both carry the cleaned body), outcome logged with latency.
    private func finishAsk(
        heading1: String?, heading2: String?, body: String, citedRefs: [Int],
        preparation: AskPreparation,
        question: String,
        latency: Duration
    ) -> AskResult {
        let citations = Self.reconcileCitations(
            citedRefs, retrieval: preparation.retrieval, question: question
        )
        Self.logOutcome(
            intent: .ask,
            route: preparation.route,
            promptVersion: preparation.instructions.version,
            latency: latency,
            budget: preparation.budget,
            entriesInContext: preparation.retrieval.entries.count
        )
        return AskResult(
            heading1: heading1?.isEmpty == true ? nil : heading1,
            heading2: heading2?.isEmpty == true ? nil : heading2,
            body: Self.strippingReferenceMarkers(body),
            citations: citations,
            zoneUsed: preparation.route.executionZone,
            wasDegraded: preparation.route.wasDegraded,
            promptVersion: preparation.instructions.version,
            modelIdentifier: Self.modelIdentifier(for: preparation.route.executionZone),
            latency: latency
        )
    }

    // MARK: Ask — one-shot

    func ask(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskResult {
        let preparation = try await prepareAsk(question, history: history, entries: entries)
        let session = LanguageModelSession(instructions: preparation.instructions.text)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await session.respond(
                to: preparation.prompt,
                generating: AskAnswer.self,
                options: GenerationOptions(temperature: 0.7)
            )
            let answer = response.content
            return finishAsk(heading1: answer.heading1, heading2: answer.heading2,
                             body: answer.body, citedRefs: answer.citedRefs,
                             preparation: preparation, question: question,
                             latency: clock.now - start)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: Ask — streaming (spec 017 R6: chat streams; reflections don't)

    func askStream(_ question: String, history: [ChatTurn], entries: [Entry]) -> AsyncThrowingStream<AskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let preparation = try await self.prepareAsk(question, history: history, entries: entries)
                    let session = LanguageModelSession(instructions: preparation.instructions.text)
                    let clock = ContinuousClock()
                    let start = clock.now

                    let stream = session.streamResponse(
                        to: preparation.prompt,
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
                        [], retrieval: preparation.retrieval, question: question
                    )
                    var lastHeading1: String?
                    var lastHeading2: String?
                    var lastBody = ""
                    var lastCitedRefs: [Int] = []
                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        let content = snapshot.content
                        lastBody = content.body ?? ""
                        // `?? nil` flattens the double-optional the PartiallyGenerated
                        // macro produces for `String?` properties.
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
                    try Task.checkCancellation()
                    let result = self.finishAsk(heading1: lastHeading1, heading2: lastHeading2,
                                                body: lastBody, citedRefs: lastCitedRefs,
                                                preparation: preparation, question: question,
                                                latency: clock.now - start)
                    continuation.yield(.final(result))
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.mapGenerationError(error))
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as IntelligenceError {
                    continuation.finish(throwing: error)
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
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntelligenceError.generationFailed("Reflection text is empty.")
        }

        let route = await resolveRoute(for: .profileEstimate)
        let budget = Self.currentBudget()
        let resolved = PromptRegistry.resolve(
            intent: .profileEstimate,
            zone: route.executionZone,
            degraded: route.useDegradedPrompt
        )
        let session = LanguageModelSession(instructions: resolved.text)
        let prompt = Self.buildProfileEstimatePrompt(reflection: trimmed)
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let response = try await session.respond(
                to: prompt,
                generating: ProfileEstimateAnswer.self,
                options: GenerationOptions(temperature: 0.4)
            )
            let latency = clock.now - start
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
            Self.logOutcome(
                intent: .profileEstimate,
                route: route,
                promptVersion: resolved.version,
                latency: latency,
                budget: budget,
                entriesInContext: 0
            )
            return ProfileEstimateResult(
                themeIds: themes,
                secondaryThemeIds: secondary,
                promptLens: lens,
                zoneUsed: route.executionZone,
                wasDegraded: route.wasDegraded,
                promptVersion: resolved.version,
                modelIdentifier: Self.modelIdentifier(for: route.executionZone),
                latency: latency
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

    func summarizeConversation(_ turns: [ChatTurn]) async throws -> GenerationOutcome<String> {
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let route = await resolveRoute(for: .summary)
        let budget = Self.currentBudget()
        let resolved = PromptRegistry.resolve(
            intent: .summary,
            zone: route.executionZone,
            degraded: route.useDegradedPrompt
        )
        let session = LanguageModelSession(instructions: resolved.text)
        let conversation = turns.map { turn in
            (turn.role == .user ? "User: " : "Assistant: ") + turn.text
        }.joined(separator: "\n")
        let prompt = "Here is the conversation to summarize:\n\n\(conversation)"
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.7))
            let latency = clock.now - start
            Self.logOutcome(
                intent: .summary,
                route: route,
                promptVersion: resolved.version,
                latency: latency,
                budget: budget,
                entriesInContext: 0
            )
            return GenerationOutcome(
                value: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
                zoneUsed: route.executionZone,
                modelIdentifier: Self.modelIdentifier(for: route.executionZone),
                wasDegraded: route.wasDegraded,
                latency: latency
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt assembly

    /// Recent history condensed for the retrieval assist vector (not the prompt).
    private static func historyContext(_ history: [ChatTurn], budget: ContextBudget) -> String? {
        guard !history.isEmpty else { return nil }
        let turns = max(2, budget.maxHistoryTurns / 2)
        let condensed = history.suffix(turns)
            .map { String($0.text.prefix(budget.maxHistoryCharsPerTurn)) }
            .joined(separator: " ")
        return condensed.isEmpty ? nil : condensed
    }

    private static func buildAskPrompt(
        question: String,
        history: [ChatTurn],
        retrieval: RetrievalResult,
        stance: TurnStance,
        budget: ContextBudget
    ) -> String {
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
        // Budget-driven trim (spec 017 R9): keeps thread context while bounding
        // the prompt the small on-device model ingests (time-to-first-token).
        let recent = history.suffix(budget.maxHistoryTurns)
        if !recent.isEmpty {
            let convo = recent
                .map { ($0.role == .user ? "You: " : "Memento: ") + String($0.text.prefix(budget.maxHistoryCharsPerTurn)) }
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

    private static func modelIdentifier(for zone: TrustZone) -> String {
        switch zone {
        case .z0Device: return "apple.system.on-device"
        case .z1AppleContent: return "apple.pcc"
        case .z1AppleContentFree: return "apple.cloud.content-free"
        }
    }
}
