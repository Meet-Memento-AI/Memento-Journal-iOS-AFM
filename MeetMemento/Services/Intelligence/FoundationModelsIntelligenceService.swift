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
//  On-device (`SystemLanguageModel`, Z0) generation for Ask + Chat summary,
//  replacing the former server-side `chat` / `summarize-chat` functions.
//
//  Every generation runs the same per-request pipeline (spec 017):
//    availability → QuotaGovernor.capability → ModelRouter.resolve
//      → GenerationRequest → PromptRegistry.resolve → ContextBudget
//      → generate → outcome + one content-free log line
//
//  The Private Cloud Compute (Z1) leg is NOT wired: `PrivateCloudComputeLanguageModel`
//  is an iOS-27-SDK type absent from the iOS 26 SDK this target builds against.
//  `PCCSessionProviding` is where it plugs in, and because the router already
//  routes on its answer, enabling it is a construction-site change.
//
//  **Session architecture (spec 017 R9, Task 11): stateless per-request session
//  assembly.** Each generation constructs a fresh `LanguageModelSession` from
//  registry instructions plus the assembled prompt. The caller owns the
//  transcript (`LocalChatStore`), retrieval is deterministic, and follow-up
//  grounding is re-derived statelessly via `RetrievalPolicy.followupAnchor`.
//  Chosen over iOS 27 Dynamic Profiles and over a transcript-preserving rebuild
//  because it is the only option available on this SDK, it survives relaunch
//  with zero session state to restore, and it keeps the boundary testable
//  without a live session. Revisit only if per-turn instruction re-tokenization
//  shows up in spec 022's latency numbers.
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

    private let quotaGovernor: QuotaGovernor
    private let pccProvider: PCCSessionProviding
    /// Reads the user's Z0 pin. Injected so routing tests don't depend on
    /// whatever the simulator's UserDefaults happen to hold.
    private let isPinnedToDevice: @Sendable () -> Bool

    init(
        quotaGovernor: QuotaGovernor = .shared,
        pccProvider: PCCSessionProviding = UnavailablePCCProvider(),
        isPinnedToDevice: @escaping @Sendable () -> Bool = { PreferencesService.shared.processOnDeviceOnly }
    ) {
        self.quotaGovernor = quotaGovernor
        self.pccProvider = pccProvider
        self.isPinnedToDevice = isPinnedToDevice
    }

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
            resolved = .available(.z0Device)
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

    // MARK: Routing, budget, logging

    /// Resolve where this intent runs. The Z0 pin is consulted first and
    /// short-circuits before the PCC seam is touched, so no surface can escape
    /// it (REQ-INT-004).
    private func resolveRoute(for intent: GenerationIntent) async -> ResolvedRoute {
        let pinned = isPinnedToDevice()
        if pinned {
            return ModelRouter.resolve(intent: intent, pinnedToDevice: true, pccCapability: .sdkUnsupported)
        }
        guard pccProvider.isSupported else {
            return ModelRouter.resolve(intent: intent, pinnedToDevice: false, pccCapability: .sdkUnsupported)
        }
        let priority = ModelRouter.row(for: intent)?.priority ?? .interactive
        let capability = await quotaGovernor.capability(for: priority)
        return ModelRouter.resolve(intent: intent, pinnedToDevice: false, pccCapability: capability)
    }

    /// The model's usable context window (CONSTITUTION §4 rule 5's corollary).
    ///
    /// `SystemLanguageModel.contextSize` is declared in the iOS 27 SDK and
    /// back-deployed to iOS 26.4 at runtime, but the iOS 26 SDK does not declare
    /// the member at all — so this is an availability question about the *SDK*,
    /// which `#available` cannot answer. Keyed on the compiler version instead:
    /// Xcode 26.0.1 ships Swift 6.2, Xcode 27 ships Swift 6.4.
    ///
    /// When the window can't be read we say so rather than assuming 4096; see
    /// `ContextBudget`'s header for why substituting a literal would be the
    /// exact thing this rule forbids.
    private static func currentWindow() -> ContextWindow {
        #if compiler(>=6.3)
        return .reported(tokens: SystemLanguageModel.default.contextSize)
        #else
        return .unavailable
        #endif
    }

    /// One line per generation (CONSTITUTION §4 rule 3). Carries the routing
    /// decision, provenance, latency, and how much evidence was used — and
    /// deliberately no journal content, no question text, and no reply text.
    private static func logOutcome(
        intent: GenerationIntent,
        route: ResolvedRoute,
        promptVersion: String,
        latency: Duration,
        window: ContextWindow,
        entryCount: Int
    ) {
        let ms = latency.components.seconds * 1000 + latency.components.attoseconds / 1_000_000_000_000_000
        let windowDescription: String
        switch window {
        case .reported(let tokens): windowDescription = "\(tokens)"
        case .unavailable: windowDescription = "unreported"
        }
        AppLogger.log(
            "[Intelligence] intent=\(intent) requested=\(route.requestedZone.identifier) "
            + "ran=\(route.executionZone.identifier) reason=\(route.reason.rawValue) "
            + "degraded=\(route.wasDegraded) prompt=\(promptVersion) "
            + "latency=\(ms)ms window=\(windowDescription) entries=\(entryCount)"
        )
    }

    // MARK: Ask

    /// Everything the model call needs, computed once and shared by the
    /// one-shot `ask` and the streaming `askStream`.
    private struct AskPreparation {
        /// The zone, prompt version, and degradation allowance fixed **before**
        /// the model call (spec 014 R1: never inferred after). Everything
        /// downstream reads provenance from here rather than re-deriving it, so
        /// there is one place a misroute could come from.
        let request: GenerationRequest
        let route: ResolvedRoute
        let retrieval: RetrievalResult
        let stance: TurnStance
        let prompt: String
        let resolved: ResolvedPrompt
        let budget: ContextBudget

        var zone: TrustZone { request.zone }
    }

    /// Availability → turn classification → retrieval → stance → prompt +
    /// instructions. Pure aside from the availability await.
    private func prepareAsk(question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskPreparation {
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let route = await resolveRoute(for: .ask)
        let budget = ContextBudget(window: Self.currentWindow())
        // A degraded route narrows the evidence: the smaller model grounds a
        // reply better from less context than from more (technology/02 §8).
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
                retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: anchor),
                                                    entries: entries, limits: limits)
            } else {
                retrieval = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question,
                                   historyContext: Self.historyContext(history, budget: budget)),
                    entries: entries, limits: limits
                )
            }
        case .currentOnly(let highBar):
            retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: question, highBar: highBar),
                                                entries: entries, limits: limits)
        case .currentWeighted:
            retrieval = EntryRetriever.retrieve(
                RetrievalQuery(currentMessage: question,
                               historyContext: Self.historyContext(history, budget: budget)),
                entries: entries, limits: limits
            )
        }
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let prompt = Self.buildAskPrompt(question: question, history: history,
                                         retrieval: retrieval, stance: stance, budget: budget)
        // The degraded variant is a registry entry, never the heavy prompt
        // behind a lighter model (REQ-INT-010).
        let resolved = PromptRegistry.resolve(
            intent: .ask,
            zone: route.executionZone,
            degraded: route.useDegradedPrompt,
            personalization: PromptPersonalization.fromLocalProfile()
        )
        let request = GenerationRequest(
            intent: .ask,
            zone: route.executionZone,
            allowsDegradation: ModelRouter.row(for: .ask)?.degradedZone != nil,
            promptVersion: resolved.version,
            toolsEnabled: false
        )
        return AskPreparation(request: request, route: route, retrieval: retrieval, stance: stance,
                              prompt: prompt, resolved: resolved, budget: budget)
    }

    /// Builds the final `AskResult` (citations reconciled, reference markers
    /// stripped) from either the whole-answer `respond` or the last streamed
    /// snapshot. Reference stripping happens here so the live reply and the
    /// JSON ChatService persists both carry the cleaned body.
    private func makeResult(heading1: String?, heading2: String?, body: String, citedRefs: [Int],
                            prep: AskPreparation, question: String, latency: Duration) -> AskResult {
        let citations = Self.reconcileCitations(
            citedRefs, retrieval: prep.retrieval, question: question
        )
        Self.logOutcome(intent: prep.request.intent, route: prep.route,
                        promptVersion: prep.request.promptVersion,
                        latency: latency, window: prep.budget.window,
                        entryCount: prep.retrieval.entries.count)
        return AskResult(
            heading1: heading1?.isEmpty == true ? nil : heading1,
            heading2: heading2?.isEmpty == true ? nil : heading2,
            body: Self.strippingReferenceMarkers(body),
            citations: citations,
            zoneUsed: prep.zone,
            wasDegraded: prep.route.wasDegraded,
            promptVersion: prep.request.promptVersion,
            modelIdentifier: Self.modelIdentifier(for: prep.zone),
            latency: latency
        )
    }

    func ask(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskResult {
        let clock = ContinuousClock()
        let started = clock.now
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
                              prep: prep, question: question, latency: clock.now - started)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    func askStream(_ question: String, history: [ChatTurn], entries: [Entry]) -> AsyncThrowingStream<AskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let started = clock.now
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
                                            prep: prep, question: question,
                                            latency: clock.now - started)
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
        let clock = ContinuousClock()
        let started = clock.now
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
        let zone = route.executionZone
        let budget = ContextBudget(window: Self.currentWindow())
        let resolved = PromptRegistry.resolve(intent: .profileEstimate, zone: zone,
                                              degraded: route.useDegradedPrompt)
        let session = LanguageModelSession(instructions: resolved.text)
        let prompt = Self.buildProfileEstimatePrompt(reflection: trimmed, budget: budget)

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
            let latency = clock.now - started
            Self.logOutcome(intent: .profileEstimate, route: route, promptVersion: resolved.version,
                            latency: latency, window: budget.window, entryCount: 0)
            return ProfileEstimateResult(
                themeIds: themes,
                secondaryThemeIds: secondary,
                promptLens: lens,
                zoneUsed: zone,
                wasDegraded: route.wasDegraded,
                promptVersion: resolved.version,
                modelIdentifier: Self.modelIdentifier(for: zone),
                latency: latency
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    private static func buildProfileEstimatePrompt(reflection: String, budget: ContextBudget) -> String {
        // Compact catalog projection — id + display name only — to protect context.
        let catalogLines = ThemeCatalog.all
            .map { "\($0.id): \($0.displayName)" }
            .joined(separator: "\n")
        // The reflection is the one variable-length input here, so it gets the
        // evidence allocation the retrieved entries would otherwise use.
        let reflectionCap = budget.maxRetrievedEntries * budget.maxEntryChars / 4
        let cappedReflection = reflection.count > reflectionCap
            ? String(reflection.prefix(reflectionCap)) + "…"
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
        let clock = ContinuousClock()
        let started = clock.now
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let route = await resolveRoute(for: .summary)
        let budget = ContextBudget(window: Self.currentWindow())
        let resolved = PromptRegistry.resolve(intent: .summary, zone: route.executionZone,
                                              degraded: route.useDegradedPrompt)
        let session = LanguageModelSession(instructions: resolved.text)
        // The conversation is bounded by the same history allocation the ask
        // prompt uses, so a long chat can't crowd out the summary itself.
        let conversation = turns.suffix(budget.maxHistoryTurns).map { turn in
            (turn.role == .user ? "User: " : "Assistant: ")
                + String(turn.text.prefix(budget.maxHistoryCharsPerTurn))
        }.joined(separator: "\n")
        let prompt = "Here is the conversation to summarize:\n\n\(conversation)"

        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.7))
            let latency = clock.now - started
            Self.logOutcome(intent: .summary, route: route, promptVersion: resolved.version,
                            latency: latency, window: budget.window, entryCount: 0)
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
    ///
    /// Deliberately shallower than the prompt's own history window: this is a
    /// similarity query, and too much of it drowns the current message's signal.
    private static func historyContext(_ history: [ChatTurn], budget: ContextBudget) -> String? {
        guard !history.isEmpty else { return nil }
        let turns = max(2, budget.maxHistoryTurns / 2)
        let condensed = history.suffix(turns)
            .map { String($0.text.prefix(budget.maxHistoryCharsPerTurn)) }
            .joined(separator: " ")
        return condensed.isEmpty ? nil : condensed
    }

    private static func buildAskPrompt(question: String, history: [ChatTurn], retrieval: RetrievalResult,
                                       stance: TurnStance, budget: ContextBudget) -> String {
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
        // History depth comes from the runtime window rather than a fixed count,
        // so a larger-window device carries more thread context without anyone
        // retuning a constant (CONSTITUTION §4 rule 5's corollary).
        let recent = history.suffix(budget.maxHistoryTurns)
        if !recent.isEmpty {
            let convo = recent
                .map { ($0.role == .user ? "You: " : "Memento: ")
                    + String($0.text.prefix(budget.maxHistoryCharsPerTurn)) }
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

    /// Persisted provenance (`REQ-PRM-004`). Stable strings — the quality study
    /// joins on them, so treat these as a wire format rather than log prose.
    private static func modelIdentifier(for zone: TrustZone) -> String {
        switch zone {
        case .z0Device: return "apple.system.on-device"
        case .z1AppleContent(let level): return "apple.pcc.\(level.rawValue)"
        case .z1AppleContentFree: return "apple.cloud.content-free"
        }
    }
}
