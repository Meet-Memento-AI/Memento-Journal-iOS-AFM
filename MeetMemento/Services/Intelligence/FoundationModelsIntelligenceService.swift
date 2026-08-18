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
import os

// MARK: - Structured output (guided generation, no JSON parsing) — spec 017 R5

/// The Ask reply, produced by constrained decoding. `citedRefs` are the [ref]
/// numbers from the context block the model actually used — reconciled against
/// the provided set so a citation can never be fabricated.
@Generable
struct AskAnswer {
    // Field order is decode order for guided generation (spec 029 Amendment A):
    // `body` leads so the first visible token never waits on the two optional
    // heading decisions; `citedRefs` trails so a token-cap truncation can only
    // cost citations (which reconcile falls back for), never body text.
    @Guide(description: "The reply, in plain spoken prose — no markdown, no bullet points, no headings, no emoji, and no reference markers such as [ref 2], (ref 2), ref 2, or [2]. Name an entry by its date or subject instead. Second person. Match the user's length: one or two sentences for casual turns, three to five for journal questions. Never pad to ten sentences.")
    let body: String

    @Guide(description: "Optional short heading for analytical, multi-part answers. Empty for casual replies.")
    let heading1: String?

    @Guide(description: "Optional rare subheading. Usually empty.")
    let heading2: String?

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

    /// The speculatively prewarmed next-turn session (spec 029 Amendment A).
    /// Built ahead of time from an `AskTranscriptPlan` — instructions PLUS the
    /// history tail as real transcript turns — so a matching turn pays neither
    /// model load, instruction prefill, nor history prefill; only evidence +
    /// question remain on the live call. Adopted only on exact fingerprint
    /// match and used exactly once; misses (degraded route, personalization
    /// change, history drift) fall back to an inline build. Stateless
    /// architecture unchanged (spec 017 R9): every session is fresh and the
    /// store owns the history both sides derive from.
    private var speculativeSession: LanguageModelSession?
    private var speculativeFingerprint: String?

    /// Consumes the speculative session iff its plan fingerprint matches.
    private func takeSpeculativeSession(matching fingerprint: String) -> LanguageModelSession? {
        stateLock.lock(); defer { stateLock.unlock() }
        guard speculativeFingerprint == fingerprint, let session = speculativeSession else { return nil }
        speculativeSession = nil
        speculativeFingerprint = nil
        return session
    }

    /// Maps the pure plan 1:1 onto a FoundationModels transcript session.
    private static func makeSession(from plan: AskTranscriptPlan) -> LanguageModelSession {
        var entries: [Transcript.Entry] = []
        entries.reserveCapacity(plan.entries.count)
        for entry in plan.entries {
            switch entry {
            case .instructions(let text):
                entries.append(.instructions(Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: text))],
                    toolDefinitions: []
                )))
            case .userPrompt(let text):
                entries.append(.prompt(Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: text))]
                )))
            case .assistantResponse(let text):
                entries.append(.response(Transcript.Response(
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(content: text))]
                )))
            }
        }
        return LanguageModelSession(transcript: Transcript(entries: entries))
    }

    /// Speculatively builds and prefills the session for the NEXT turn of a
    /// conversation with this history. Callers time it for idle windows —
    /// after `.final` in typed chat, after TTS drains in narration (while the
    /// user is speaking), and on conversation open. Deduped by fingerprint so
    /// overlapping triggers are harmless.
    func prewarmConversation(history: [ChatTurn]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let instructions = PromptRegistry.instructions(
                for: .ask,
                personalization: PromptPersonalization.fromLocalProfile()
            ).text
            let budget = ContextBudget(window: Self.currentWindow())
            let plan = AskTranscriptPlan.build(
                instructions: instructions, history: history, budget: budget
            )
            self.stateLock.lock()
            let alreadyWarm = self.speculativeFingerprint == plan.fingerprint
                && self.speculativeSession != nil
            self.stateLock.unlock()
            guard !alreadyWarm else { return }

            let session = Self.makeSession(from: plan)
            self.stateLock.lock()
            self.speculativeSession = session
            self.speculativeFingerprint = plan.fingerprint
            self.stateLock.unlock()
            session.prewarm()
        }
    }

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
    /// Now a speculative empty-history warm — the first turn of a fresh
    /// conversation adopts it by fingerprint (spec 029 Amendment A).
    func prewarm() {
        prewarmConversation(history: [])
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
        // os.Logger, not the DEBUG-only print: this is the one per-turn
        // latency record (spec 029 R1) and it is content-free by construction,
        // so it is safe as public metadata and useful in release traces.
        PerfSignposts.perfLog.info(
            "intent=\(String(describing: intent), privacy: .public) requested=\(route.requestedZone.identifier, privacy: .public) ran=\(route.executionZone.identifier, privacy: .public) reason=\(route.reason.rawValue, privacy: .public) degraded=\(route.wasDegraded) prompt=\(promptVersion, privacy: .public) latency=\(ms)ms window=\(windowDescription, privacy: .public) entries=\(entryCount)"
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
        /// The session transcript (instructions + history tail) this turn
        /// runs against — and the adoption key for speculative sessions.
        let plan: AskTranscriptPlan

        var zone: TrustZone { request.zone }
    }

    /// Availability → safety gate → turn classification → retrieval → stance → prompt.
    /// Pure aside from the availability await.
    private func prepareAsk(question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskPreparation {
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let signposter = PerfSignposts.chatTurn
        let spid = signposter.makeSignpostID()

        // Route is an await (quota / PCC). Overlap it with the sync safety
        // and classify work so a pinned-to-device ask doesn't pay the hop
        // after those have already finished (spec 029 P5).
        async let routeTask = resolveRoute(for: .ask)

        // Spec 026: deterministic Safety layer BEFORE retrieval so crisis /
        // violence / CSAM turns never pull journal evidence into the model.
        LiveTurnClock.shared.start(.prepSafety)
        let safetyState = signposter.beginInterval("prep.safety", id: spid)
        let safety = SafetyRouter.decide(question)
        signposter.endInterval("prep.safety", safetyState)
        LiveTurnClock.shared.end(.prepSafety)
        SafetyMetrics.record(safety)
        switch safety.action {
        case .showCrisisCard:
            throw IntelligenceError.crisisResource
        case .hardRefuse:
            throw IntelligenceError.safetyRefusal(safety.category)
        case .continueConstrained, .continue:
            break
        }

        let budget = ContextBudget(window: Self.currentWindow())

        // Conversational turn architecture: classify the current message,
        // decide retrieval by policy, then hand the model an explicit stance —
        // logic decides the stance, the prompt obeys it.
        LiveTurnClock.shared.start(.prepClassify)
        let classifyState = signposter.beginInterval("prep.classify", id: spid)
        let turn = TurnClassifier.classify(question, hasHistory: !history.isEmpty)
        signposter.endInterval("prep.classify", classifyState)
        LiveTurnClock.shared.end(.prepClassify)

        let route = await routeTask
        // A degraded route narrows the evidence: the smaller model grounds a
        // reply better from less context than from more (technology/02 §8).
        let limits = route.useDegradedPrompt
            ? RetrievalLimits(budget: budget).narrowed()
            : RetrievalLimits(budget: budget)

        LiveTurnClock.shared.start(.prepRetrieve)
        let retrieveState = signposter.beginInterval("prep.retrieve", id: spid)
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
        signposter.endInterval("prep.retrieve", retrieveState)
        LiveTurnClock.shared.end(.prepRetrieve)
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let prompt = Self.buildAskPrompt(
            question: question,
            history: history,
            retrieval: retrieval,
            stance: stance,
            budget: budget,
            safetyConstrained: safety.action == .continueConstrained
        )
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
        let plan = AskTranscriptPlan.build(
            instructions: resolved.text, history: history, budget: budget
        )
        return AskPreparation(request: request, route: route, retrieval: retrieval, stance: stance,
                              prompt: prompt, resolved: resolved, budget: budget, plan: plan)
    }

    /// Builds the final `AskResult` (citations reconciled, reference markers
    /// stripped, output safety scanned) from either the whole-answer `respond`
    /// or the last streamed snapshot.
    private func makeResult(heading1: String?, heading2: String?, body: String, citedRefs: [Int],
                            prep: AskPreparation, question: String, latency: Duration) throws -> AskResult {
        let cleanedBody = Self.strippingReferenceMarkers(body)
        if let hit = OutputSafetyScanner.scan(cleanedBody) {
            SafetyMetrics.record(SafetyDecision(category: hit.category, action: hit.action, confidence: 1))
            switch hit.action {
            case .showCrisisCard:
                throw IntelligenceError.crisisResource
            case .hardRefuse, .continueConstrained, .continue:
                throw IntelligenceError.safetyRefusal(hit.category)
            }
        }
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
            body: cleanedBody,
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
        let session = takeSpeculativeSession(matching: prep.plan.fingerprint)
            ?? Self.makeSession(from: prep.plan)
        do {
            let response = try await session.respond(
                to: prep.prompt,
                generating: AskAnswer.self,
                options: Self.askOptions
            )
            let answer = response.content
            let result = try makeResult(heading1: answer.heading1, heading2: answer.heading2,
                              body: answer.body, citedRefs: answer.citedRefs,
                              prep: prep, question: question, latency: clock.now - started)
            return result
        } catch let error as IntelligenceError {
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    /// Ask generation options (spec 029 Amendment A). Temperature stays 0.7 —
    /// per-token sampling cost is negligible against prefill/decode, and
    /// greedy would flatten the companion's voice for determinism nobody
    /// asked for. `maximumResponseTokens` is a pure runaway guard: ten
    /// sentences ≈ 250 output tokens; 512 is ~2× headroom including headings,
    /// citedRefs, and structure tokens. Truncation can only clip trailing
    /// fields (see AskAnswer's field-order comment).
    private static let askOptions = GenerationOptions(temperature: 0.7, maximumResponseTokens: 512)

    /// A stream with no new snapshot for this long is stalled (spec 029 R7).
    static let generationWatchdogTimeout: Duration = .seconds(30)
    /// How far the incremental output-safety scan re-reads behind its
    /// watermark. An unsafe phrase either lies in already-scanned text, in the
    /// new suffix, or spans the boundary — and no scanner pattern matches more
    /// than this many characters, so re-reading the overlap makes the
    /// suffix-only scan exactly equivalent to a full scan (spec 029 R3).
    static let outputScanOverlapChars = 128

    /// The last streamed snapshot's tail, carried out of the task group.
    private struct StreamTail: Sendable {
        var heading1: String?
        var heading2: String?
        var body = ""
        var citedRefs: [Int] = []
    }

    func askStream(_ question: String, history: [ChatTurn], entries: [Entry]) -> AsyncThrowingStream<AskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let started = clock.now
                let signposter = PerfSignposts.chatTurn
                let spid = signposter.makeSignpostID()
                do {
                    let prepState = signposter.beginInterval("prep", id: spid)
                    let prep = try await prepareAsk(question: question, history: history, entries: entries)
                    signposter.endInterval("prep", prepState)

                    // Spec 029 Amendment A: adopt the speculative session when
                    // its transcript fingerprint matches — weights, instruction
                    // prefill, AND history prefill are then already paid;
                    // only evidence + question remain on this call.
                    LiveTurnClock.shared.start(.sessionCreate)
                    let sessionState = signposter.beginInterval("session.create", id: spid)
                    let adopted = takeSpeculativeSession(matching: prep.plan.fingerprint)
                    signposter.emitEvent(adopted != nil ? "speculative.hit" : "speculative.miss", id: spid)
                    let session = adopted ?? Self.makeSession(from: prep.plan)
                    signposter.endInterval("session.create", sessionState)
                    LiveTurnClock.shared.end(.sessionCreate)

                    LiveTurnClock.shared.start(.modelFirstToken)
                    let ttftState = signposter.beginInterval("model.ttft", id: spid)

                    let stream = session.streamResponse(
                        to: prep.prompt,
                        generating: AskAnswer.self,
                        options: Self.askOptions
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

                    // Watchdog clock, shared with the watchdog child task.
                    let lastProgress = OSAllocatedUnfairLock(initialState: clock.now)

                    let tail: StreamTail = try await withThrowingTaskGroup(of: StreamTail?.self) { group in
                        group.addTask {
                            var tail = StreamTail()
                            // Strip memo: snapshots frequently repeat the body while
                            // headings/citedRefs settle — skip the (linear, cached-
                            // regex) re-strip when the raw body is unchanged.
                            var lastRawBody = ""
                            var lastCleaned = ""
                            // Character count cached alongside — `String.count`
                            // is an O(n) walk and ran twice per snapshot.
                            var lastCleanedCount = 0
                            // Incremental scan watermark: characters of the cleaned
                            // body already proven safe.
                            var scannedCount = 0
                            var sawFirstSnapshot = false
                            var streamState: OSSignpostIntervalState?
                            defer {
                                if let streamState {
                                    signposter.endInterval("model.stream", streamState)
                                    LiveTurnClock.shared.end(.modelStream)
                                } else {
                                    signposter.endInterval("model.ttft", ttftState)
                                    LiveTurnClock.shared.end(.modelFirstToken)
                                }
                            }
                            for try await snapshot in stream {
                                lastProgress.withLock { $0 = clock.now }
                                if !sawFirstSnapshot {
                                    sawFirstSnapshot = true
                                    signposter.endInterval("model.ttft", ttftState)
                                    LiveTurnClock.shared.end(.modelFirstToken)
                                    LiveTurnClock.shared.mark(.modelFirstToken)
                                    signposter.emitEvent("model.firstSnapshot", id: spid)
                                    LiveTurnClock.shared.start(.modelStream)
                                    streamState = signposter.beginInterval("model.stream", id: spid)
                                }
                                let content = snapshot.content
                                tail.body = content.body ?? ""
                                tail.heading1 = content.heading1 ?? nil
                                tail.heading2 = content.heading2 ?? nil
                                if let refs = content.citedRefs { tail.citedRefs = refs }

                                // Emit the cleaned body-so-far so the live reply
                                // matches exactly what gets persisted at the end.
                                let cleaned: String
                                if tail.body == lastRawBody {
                                    cleaned = lastCleaned
                                } else {
                                    cleaned = Self.strippingReferenceMarkers(tail.body)
                                    lastRawBody = tail.body
                                    lastCleaned = cleaned
                                }

                                // Spec 026 R7: scan the partial body BEFORE showing
                                // it — offending text must never reach the bubble.
                                // Incremental and exact: only the new suffix plus the
                                // overlap window needs scanning (see
                                // outputScanOverlapChars). Stripping can shrink the
                                // cleaned body; a shrink resets the watermark.
                                if cleaned.count < scannedCount { scannedCount = 0 }
                                let scanStart = max(0, scannedCount - Self.outputScanOverlapChars)
                                if let hit = OutputSafetyScanner.scan(String(cleaned.dropFirst(scanStart))) {
                                    SafetyMetrics.record(
                                        SafetyDecision(category: hit.category, action: hit.action, confidence: 1)
                                    )
                                    switch hit.action {
                                    case .showCrisisCard:
                                        throw IntelligenceError.crisisResource
                                    case .hardRefuse, .continueConstrained, .continue:
                                        throw IntelligenceError.safetyRefusal(hit.category)
                                    }
                                }
                                scannedCount = cleaned.count

                                continuation.yield(.delta(
                                    bodySoFar: cleaned,
                                    heading1: tail.heading1?.isEmpty == true ? nil : tail.heading1,
                                    heading2: tail.heading2?.isEmpty == true ? nil : tail.heading2,
                                    reviewedCitations: reviewed
                                ))
                            }
                            return tail
                        }
                        // Watchdog (spec 029 R7): a stream that stops producing
                        // snapshots for the timeout window is stalled — fail the
                        // turn with a designed error instead of hanging forever.
                        group.addTask {
                            while !Task.isCancelled {
                                do { try await Task.sleep(for: .seconds(5)) } catch { return nil }
                                let idle = lastProgress.withLock { clock.now - $0 }
                                if idle >= Self.generationWatchdogTimeout {
                                    throw IntelligenceError.generationTimedOut
                                }
                            }
                            return nil
                        }
                        while let next = try await group.next() {
                            if let tail = next {
                                group.cancelAll()
                                return tail
                            }
                        }
                        throw IntelligenceError.generationFailed("Stream ended without a result.")
                    }

                    let result = try makeResult(heading1: tail.heading1, heading2: tail.heading2,
                                            body: tail.body, citedRefs: tail.citedRefs,
                                            prep: prep, question: question,
                                            latency: clock.now - started)
                    continuation.yield(.final(result))
                    continuation.finish()
                    // Next-turn warming is caller-driven now (spec 029 Am. A):
                    // ChatViewModel/.final, narration's post-drain listen, and
                    // conversation open all call prewarmNextTurn with the
                    // just-updated history.
                } catch let error as IntelligenceError {
                    continuation.finish(throwing: error)
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

        let safety = SafetyRouter.decide(trimmed)
        SafetyMetrics.record(safety)
        switch safety.action {
        case .showCrisisCard:
            throw IntelligenceError.crisisResource
        case .hardRefuse:
            throw IntelligenceError.safetyRefusal(safety.category)
        case .continueConstrained, .continue:
            break
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

        // Spec 026: refuse summarizing conversations that are crisis/violence/
        // CSAM assistance (e.g. "write my goodbye note" → journal entry).
        let userBlob = turns.filter { $0.role == .user }.map(\.text).joined(separator: "\n")
        let safety = SafetyRouter.decide(userBlob)
        SafetyMetrics.record(safety)
        switch safety.action {
        case .showCrisisCard:
            throw IntelligenceError.crisisResource
        case .hardRefuse:
            throw IntelligenceError.safetyRefusal(safety.category)
        case .continueConstrained, .continue:
            break
        }

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
            let trimmedOut = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let hit = OutputSafetyScanner.scan(trimmedOut) {
                SafetyMetrics.record(SafetyDecision(category: hit.category, action: hit.action, confidence: 1))
                switch hit.action {
                case .showCrisisCard: throw IntelligenceError.crisisResource
                default: throw IntelligenceError.safetyRefusal(hit.category)
                }
            }
            let latency = clock.now - started
            Self.logOutcome(intent: .summary, route: route, promptVersion: resolved.version,
                            latency: latency, window: budget.window, entryCount: 0)
            return GenerationOutcome(
                value: trimmedOut,
                zoneUsed: route.executionZone,
                modelIdentifier: Self.modelIdentifier(for: route.executionZone),
                wasDegraded: route.wasDegraded,
                latency: latency
            )
        } catch let error as IntelligenceError {
            throw error
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
                                       stance: TurnStance, budget: ContextBudget,
                                       safetyConstrained: Bool = false) -> String {
        // The stance line is the first thing the model reads for this turn —
        // the deterministic instruction that stops it from grounding casual
        // conversation in journal entries.
        var parts: [String] = [stance.promptLine]
        if safetyConstrained {
            parts.insert(SafetyRouter.constrainedStanceLine, at: 0)
        }
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
        // History no longer renders here (spec 029 Amendment A): it rides the
        // session transcript as real turns (AskTranscriptPlan), where its
        // prefill can be paid speculatively. Only the anti-repeat rule stays
        // per-turn — it must not fire on turn one.
        if !history.isEmpty {
            parts.append(
                "Do not reuse openings, questions, or entry summaries you already used earlier in this conversation."
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
    /// Compiled once (spec 029 R3): these ran fresh on every streamed snapshot,
    /// which multiplied ~6 regex compiles by the snapshot count of every reply.
    /// Ordered: bracketed/parenthesised ref forms, then bare square-bracket
    /// numbers, then a bare "ref 2". Each tolerates lists ("ref 1 and 2").
    private static let markerRegexes: [NSRegularExpression] = {
        let numberList = #"\d+(?:\s*(?:,|and|&)\s*\d+)*"#
        let patterns = [
            #"\s*[\[(]\s*refs?\.?\s*#?"# + numberList + #"\s*[\])]"#,
            #"\s*\[\s*"# + numberList + #"\s*\]"#,
            #"\s*\brefs?\.?\s*#?"# + numberList + #"\b"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// Tidy what removal left behind: a space before punctuation, doubled
    /// spaces, and an emptied parenthesis pair.
    private static let cleanupRegexes: [(regex: NSRegularExpression, template: String)] = {
        let cleanups: [(String, String)] = [
            (#"\s+([,.;:!?])"#, "$1"),
            (#"[ \t]{2,}"#, " "),
            (#"\(\s*\)"#, "")
        ]
        return cleanups.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    static func strippingReferenceMarkers(_ body: String) -> String {
        var out = body
        for regex in markerRegexes {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }
        for (regex, template) in cleanupRegexes {
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
            SafetyMetrics.recordAFMGuardrailRefusal()
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
