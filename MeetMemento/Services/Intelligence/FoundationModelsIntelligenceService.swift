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
import UIKit

// MARK: - Structured output (guided generation, no JSON parsing) — spec 017 R5

/// The Ask reply, produced by constrained decoding. `citedRefs` are the [ref]
/// numbers from the context block the model actually used — reconciled against
/// the provided set so a citation can never be fabricated.
@Generable
struct AskAnswer {
    // Field order is decode order for guided generation (spec 029 Amendment A):
    // `body` leads so the first visible token never waits on the two optional
    // heading decisions; `citedRefs` trails so losing it costs only citations
    // (which reconcile falls back for), never body text.
    //
    // `citedRefs` is OPTIONAL, and that is load-bearing rather than cosmetic.
    // Measured 2026-08-23 over the follow-up turn, 5 reps per cell: with the
    // field required this decoded 3/5 at a 128-token cap and 4/5 at 512; with
    // it optional, 5/5 at both. The cap is not the variable — the field is.
    //
    // The model routinely writes `citedRefs` as *prose inside `body`* and then
    // never emits the real property, e.g.
    //     {"body": "…now?\n\ncitedRefs:[1]}}  ```json\n{\n  "}
    // which fails as `GeneratedContent does not contain a property 'citedRefs'`.
    // Required, that killed the whole turn and the user saw "I couldn't put a
    // reflection together just now." Optional, the turn survives and only the
    // citations are lost — which `reconcileCitations` already backfills from
    // the reviewed set. The prose leak itself is scrubbed by
    // `strippingReferenceMarkers`.
    //
    // So: do NOT make this non-optional again without re-running that grid.
    @Guide(description: "The complete spoken reply in second person. Sound like a person talking. End with one specific question; skip the question only on goodbye. Notebook, ###, and italic quotes only if this turn uses the journal; otherwise leave citedRefs empty. Markdown subset allowed when the journal is in play: one ### heading, paragraphs, - lists, 1. lists, bold on a short span of their wording, italics for an exact journal quote. No emoji, no reference markers such as [ref 2], (ref 2), ref 2, or [2]. Name an entry by its date or subject instead. Do not name their emotions, give advice, or state a count of entries.")
    let body: String

    @Guide(description: "Always empty on conversational Ask. Titles steal decode and delay the visible body.")
    let heading1: String?

    @Guide(description: "Always empty on conversational Ask.")
    let heading2: String?

    @Guide(description: "The [ref] numbers of the journal entries from the context block that were actually referenced. Empty if none. These belong here only — never in the body.")
    let citedRefs: [Int]?
}

/// Testable twin of `AskAnswer`'s `@Guide` copy (spec 037 R8). Keep in sync
/// with the descriptions above — the macro takes string literals.
enum AskAnswerGuides {
    static let body = "The complete spoken reply in second person. Sound like a person talking. End with one specific question; skip the question only on goodbye. Notebook, ###, and italic quotes only if this turn uses the journal; otherwise leave citedRefs empty. Markdown subset allowed when the journal is in play: one ### heading, paragraphs, - lists, 1. lists, bold on a short span of their wording, italics for an exact journal quote. No emoji, no reference markers such as [ref 2], (ref 2), ref 2, or [2]. Name an entry by its date or subject instead. Do not name their emotions, give advice, or state a count of entries."
    static let heading1 = "Always empty on conversational Ask. Titles steal decode and delay the visible body."
    static let heading2 = "Always empty on conversational Ask."
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
    private let cadenceLock = NSLock()
    /// Spec 037 R3: last journal shape for this process's live Ask thread.
    /// Reset when history is empty (new chat).
    private var turnShapeCadence = TurnShapeCadence()
    private let poolLock = NSLock()
    /// Spec 037 follow-on: wide candidate pool, narrow prompt slice.
    private var candidatePool = SessionCandidatePool()
    /// Identifies the conversation the pool and cadence belong to.
    ///
    /// Both used to reset only on `history.isEmpty`, i.e. a brand-new chat.
    /// Opening a *different existing* conversation has non-empty history, so
    /// neither reset — and the previous thread's surfaced-ID denylist went on
    /// suppressing this one's best evidence for the life of the process.
    /// `ask`/`askStream` carry no conversation id, so identity is derived from
    /// the history itself.
    private var conversationAnchor: ConversationAnchor?

    /// A cheap, order-sensitive fingerprint of a conversation.
    ///
    /// A continuing thread keeps its opening turn and only grows; a switch
    /// changes the opener, and a truncation shrinks the count. Either is a
    /// different conversation as far as the pool is concerned.
    struct ConversationAnchor: Equatable {
        let opening: String
        let turnCount: Int

        init?(history: [ChatTurn]) {
            guard let first = history.first else { return nil }
            opening = first.text
            turnCount = history.count
        }

        /// True when `other` is this same thread, one or more turns later.
        func continues(into other: ConversationAnchor) -> Bool {
            opening == other.opening && other.turnCount >= turnCount
        }
    }

    /// Whether this turn belongs to a different conversation than the last one,
    /// and therefore must start from a clean pool and cadence.
    private func startsNewConversation(history: [ChatTurn]) -> Bool {
        poolLock.lock()
        defer { poolLock.unlock() }

        guard let incoming = ConversationAnchor(history: history) else {
            // No history at all: a brand-new chat.
            conversationAnchor = nil
            return true
        }
        let isNew = conversationAnchor.map { !$0.continues(into: incoming) } ?? true
        conversationAnchor = incoming
        return isNew
    }

    /// Cached availability. Once the model reports `.available` it stays
    /// available for the process, so we resolve it once instead of querying
    /// `SystemLanguageModel.default.availability` on every ask/summary/estimate.
    private var cachedAvailability: IntelligenceAvailability?

    /// Consecutive refusals with no success between (see `RefusalOutageTracker`).
    ///
    /// `isInfrastructureFailure` catches the one shape of a broken model asset
    /// we can recognise from the reflected error string. This generalises it:
    /// whatever the cause, N refusals in a row with nothing succeeding is an
    /// outage, not a content decision. Guarded by `stateLock`.
    private var refusalOutage = RefusalOutageTracker()

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

    private func hasSpeculativeSession(matching fingerprint: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return speculativeFingerprint == fingerprint && speculativeSession != nil
    }

    private func storeSpeculativeSession(_ session: LanguageModelSession, fingerprint: String) {
        stateLock.lock(); defer { stateLock.unlock() }
        speculativeSession = session
        speculativeFingerprint = fingerprint
    }

    private func cachedPositiveAvailability() -> IntelligenceAvailability? {
        stateLock.lock(); defer { stateLock.unlock() }
        if case .available = cachedAvailability { return cachedAvailability }
        return nil
    }

    private func cachePositiveAvailability(_ value: IntelligenceAvailability) {
        stateLock.lock(); defer { stateLock.unlock() }
        cachedAvailability = value
    }

    /// Clears the run of refusals. Called whenever the model actually produced
    /// output, so an occasional genuine refusal never accumulates toward the
    /// outage threshold across an otherwise healthy session.
    private func noteGenerationSucceeded() {
        stateLock.lock(); defer { stateLock.unlock() }
        refusalOutage.recordSuccess()
    }

    /// `mapGenerationError`, plus the outage tracking that needs instance state.
    ///
    /// Escalating to `.unavailable` is what makes the outage visible: it is the
    /// one branch `ChatViewModel.isDesignedEmptyState` returns `false` for, so
    /// the reply falls through to the real error path — a failed send, an alert,
    /// and a retry affordance — instead of another silent authored bubble.
    /// The single funnel every model call's `catch` goes through.
    ///
    /// iOS 27 **retired** `LanguageModelSession.GenerationError` and split it
    /// across four unrelated types. Every deprecated case carries the successor
    /// in its own message — `guardrailViolation` → `LanguageModelError`,
    /// `decodingFailure` → `GeneratedContent.ParsingError`, `assetsUnavailable`
    /// → `SystemLanguageModel.Error`, `concurrentRequests` →
    /// `LanguageModelSession.Error`.
    ///
    /// Until now every `catch` here bound only the old type, so on iOS 27 the
    /// typed arm never matched and *everything* fell to the untyped `catch` and
    /// became `generationFailed(localizedDescription)`. Measured 2026-08-23: the
    /// eval gate reported `generationFailed("The model refused to answer.")` for
    /// a refusal even though `mapGenerationError` has a `case .refusal` arm that
    /// maps refusals to the designed empty state. That arm could not run.
    ///
    /// Everything downstream that keys off a *classified* error was therefore
    /// dead on iOS 27: the infrastructure-vs-content guardrail split, the
    /// designed `.emptyObservation` bubble, the persisted refusal turn, the
    /// context-window split, and `RefusalOutageTracker`'s consecutive-refusal
    /// counter — which was counting a case that could no longer occur.
    ///
    /// Order matters: `IntelligenceError` first (already classified, e.g. a
    /// Safety route thrown by `prepareAsk`), then the iOS 27 families, then the
    /// legacy type so iOS 26 keeps working, then an honest fallback.
    func mapAnyGenerationError(_ error: Error) -> IntelligenceError {
        if let alreadyClassified = error as? IntelligenceError { return alreadyClassified }

        if #available(iOS 27.0, *) {
            if let modern = error as? LanguageModelError {
                return mapModernErrorTrackingOutage(modern)
            }
            // Guided decoding failed to parse the model's object. This is the
            // `citedRefs` failure mode — the model writes the field name into
            // its prose and never emits the property — which is why the field
            // is optional. Still a real failure when it reaches here.
            if let parsing = error as? GeneratedContent.ParsingError {
                noteGenerationSucceeded()
                return .generationFailed("Failed to parse generated content: \(parsing.localizedDescription)")
            }
            if let assets = error as? SystemLanguageModel.Error {
                return .unavailable(.other(assets.errorDescription ?? "Model assets are unavailable."))
            }
        }

        if let legacy = error as? LanguageModelSession.GenerationError {
            return mapGenerationErrorTrackingOutage(legacy)
        }
        return .generationFailed(error.localizedDescription)
    }

    /// iOS 27's `LanguageModelError`, mapped to the same `IntelligenceError`
    /// vocabulary the legacy path produces, then run through the identical
    /// outage bookkeeping so the two paths cannot drift.
    @available(iOS 27.0, *)
    private func mapModernErrorTrackingOutage(_ error: LanguageModelError) -> IntelligenceError {
        let mapped: IntelligenceError
        switch error {
        case .guardrailViolation(let violation):
            // Same distinction the legacy path draws: a guardrail that could not
            // *run* is infrastructure, not a judgement about what the person
            // wrote, and must stay retryable rather than becoming a permanent
            // "I don't have an observation for this one."
            mapped = Self.isInfrastructureFailure(String(reflecting: violation))
                ? .generationFailed(error.localizedDescription)
                : .guardrailRefusal
        case .refusal:
            mapped = .guardrailRefusal
        case .contextSizeExceeded:
            mapped = .generationFailed("Context window exceeded: \(error.localizedDescription)")
        case .rateLimited:
            mapped = .generationFailed("Rate limited: \(error.localizedDescription)")
        case .timeout:
            mapped = .generationTimedOut
        default:
            mapped = .generationFailed(error.localizedDescription)
        }
        return recordOutcome(mapped)
    }

    private func mapGenerationErrorTrackingOutage(
        _ error: LanguageModelSession.GenerationError
    ) -> IntelligenceError {
        return recordOutcome(Self.mapGenerationError(error))
    }

    /// The outage bookkeeping, shared by the legacy and iOS 27 mappers so the
    /// two cannot drift. Takes an already-classified error and returns it,
    /// escalating to `.unavailable` once refusals have run long enough to mean
    /// the pipeline is down rather than this turn being declined.
    private func recordOutcome(_ mapped: IntelligenceError) -> IntelligenceError {
        guard case .guardrailRefusal = mapped else {
            // Anything that is not a refusal means the pipeline is alive, even
            // if this turn failed. Do not let unrelated failures accumulate.
            if case .generationFailed = mapped { noteGenerationSucceeded() }
            return mapped
        }

        stateLock.lock()
        let tripped = refusalOutage.recordRefusal()
        let run = refusalOutage.consecutiveRefusals
        if tripped {
            // Drop the cached positive so the next `availability()` re-queries
            // instead of serving a `.available` that this run just disproved.
            cachedAvailability = nil
        }
        stateLock.unlock()

        guard tripped else { return mapped }

        SafetyMetrics.recordAFMRefusalOutage()
        AppLogger.log(
            "[Intelligence] \(run) consecutive refusals — treating as an outage, not an empty state",
            type: .error
        )
        return .unavailable(.other("Chat isn't available on this device right now."))
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
            guard !self.hasSpeculativeSession(matching: plan.fingerprint) else { return }

            let session = Self.makeSession(from: plan)
            self.storeSpeculativeSession(session, fingerprint: plan.fingerprint)
            session.prewarm()
        }
    }

    // MARK: Availability

    func availability() async -> IntelligenceAvailability {
        if let cached = cachedPositiveAvailability() {
            return cached
        }

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
            cachePositiveAvailability(resolved)
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
        let channel: ReplyChannel
        let prompt: String
        let resolved: ResolvedPrompt
        let budget: ContextBudget
        /// The session transcript (instructions + history tail) this turn
        /// runs against — and the adoption key for speculative sessions.
        let plan: AskTranscriptPlan
        let generationOptions: GenerationOptions

        var zone: TrustZone { request.zone }
    }

    /// Availability → safety gate → classify → channel → retrieval → stance → prompt.
    /// Pure aside from the availability await.
    private func prepareAsk(question: String, history: [ChatTurn], entries: [Entry], images: [Data]) async throws -> AskPreparation {
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

        let hasImages = !images.isEmpty || history.contains { !$0.imageJPEGs.isEmpty }
        // Photos bump off phatic; visionBlockIfNeeded is a no-op without images.
        async let visionTask: String? = Self.visionBlockIfNeeded(current: images, history: history)

        let budget = ContextBudget(window: Self.currentWindow())

        // Conversational turn architecture: classify the current message,
        // resolve the reply channel (spec 039), decide retrieval by policy,
        // then hand the model an explicit stance — logic decides the stance,
        // the prompt obeys it.
        LiveTurnClock.shared.start(.prepClassify)
        let classifyState = signposter.beginInterval("prep.classify", id: spid)
        let turn = TurnClassifier.classify(question, hasHistory: !history.isEmpty)
        signposter.endInterval("prep.classify", classifyState)
        LiveTurnClock.shared.end(.prepClassify)

        let channel = ReplyChannel.resolve(turn: turn, hasImages: hasImages)

        let route = await routeTask
        // A degraded route narrows the evidence: the smaller model grounds a
        // reply better from less context than from more (technology/02 §8).
        let limits = route.useDegradedPrompt
            ? RetrievalLimits(budget: budget).narrowed()
            : RetrievalLimits(budget: budget)

        let promptCap = limits.maxEntries
        let poolLimits = RetrievalLimits(
            maxEntries: SessionCandidatePool.capacity,
            maxContentChars: limits.maxContentChars
        )

        LiveTurnClock.shared.start(.prepRetrieve)
        let retrieveState = signposter.beginInterval("prep.retrieve", id: spid)
        let retrievalMode = RetrievalPolicy.mode(for: turn, history: history)
        let wideRetrieval: RetrievalResult
        if !channel.allowsRetrieval || retrievalMode == .none {
            wideRetrieval = .empty
        } else {
            switch retrievalMode {
            case .none:
                wideRetrieval = .empty
            case .reusePrevious:
                if let anchor = RetrievalPolicy.followupAnchor(history: history) {
                    wideRetrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: anchor),
                                                        entries: entries, limits: poolLimits)
                } else {
                    wideRetrieval = EntryRetriever.retrieve(
                        RetrievalQuery(currentMessage: question,
                                       historyContext: Self.historyContext(history, budget: budget)),
                        entries: entries, limits: poolLimits
                    )
                }
            case .currentOnly(let highBar):
                wideRetrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: question, highBar: highBar),
                                                    entries: entries, limits: poolLimits)
            case .currentWeighted:
                wideRetrieval = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question,
                                   historyContext: Self.historyContext(history, budget: budget)),
                    entries: entries, limits: poolLimits
                )
            }
        }
        signposter.endInterval("prep.retrieve", retrieveState)
        LiveTurnClock.shared.end(.prepRetrieve)
        // Computed once: it mutates the anchor, so calling it twice would report
        // "same conversation" the second time and skip the cadence reset.
        let isNewConversation = startsNewConversation(history: history)
        let retrieval = sliceRetrieval(wideRetrieval, promptCap: promptCap, resetPool: isNewConversation)
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let hasEvidence = !retrieval.isEmpty && !retrieval.isAmbient
        let move = ConversationalMove.resolve(
            turn: turn, message: question, history: history, hasEvidence: hasEvidence
        )
        let shape = resolveTurnShape(for: stance, isNewConversation: isNewConversation)
        let visionBlock = await visionTask
        // Load once: light/redirect still get names on the user prompt, but
        // PromptRegistry must not append L1 when the channel omits the lens.
        let storedPersonalization = PromptPersonalization.fromLocalProfile()
        let prompt = Self.buildAskPrompt(
            question: question,
            history: history,
            retrieval: retrieval,
            stance: stance,
            shape: shape,
            archiveEmpty: entries.isEmpty,
            budget: budget,
            safetyConstrained: safety.action == .continueConstrained,
            imageCount: images.count,
            historyImageCount: history.reduce(0) { $0 + $1.imageJPEGs.count },
            canSeeImages: Self.canAttachImagesToModel,
            visionBlock: visionBlock,
            channel: channel,
            move: move,
            personalization: storedPersonalization
        )
        // The degraded variant is a registry entry, never the heavy prompt
        // behind a lighter model (REQ-INT-010). Phatic/continuer/redirect omit
        // L1; names still ride the user prompt as a [Name:] cue.
        let resolved = PromptRegistry.resolve(
            intent: .ask,
            zone: route.executionZone,
            degraded: route.useDegradedPrompt,
            personalization: channel.omitsLens ? .none : storedPersonalization,
            channel: channel
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
        let retrievalRan = !retrieval.isEmpty && !retrieval.isAmbient
        let generationOptions = Self.askOptions(for: channel, retrievalRan: retrievalRan)
        return AskPreparation(request: request, route: route, retrieval: retrieval, stance: stance,
                              channel: channel, prompt: prompt, resolved: resolved, budget: budget,
                              plan: plan, generationOptions: generationOptions)
    }

    private func resolveTurnShape(for stance: TurnStance, isNewConversation: Bool) -> RecallTurnShape {
        cadenceLock.lock()
        defer { cadenceLock.unlock() }
        if isNewConversation { turnShapeCadence.reset() }
        return turnShapeCadence.resolve(for: stance)
    }

    /// Spec 037 follow-on: retrieve up to 20, reveal 3–5. Session-scoped denylist
    /// of already-surfaced IDs so follow-ups can rotate evidence.
    private func sliceRetrieval(_ retrieval: RetrievalResult, promptCap: Int, resetPool: Bool) -> RetrievalResult {
        poolLock.lock()
        defer { poolLock.unlock() }
        if resetPool { candidatePool.reset() }
        guard !retrieval.isEmpty else { return retrieval }
        candidatePool.ingest(retrieval.entries)
        let sliced = candidatePool.sliceForPrompt(retrieval.entries, cap: promptCap)
        candidatePool.markSurfaced(sliced.map(\.id))
        return RetrievalResult(
            entries: sliced,
            contextBlock: EntryRetriever.contextBlock(for: sliced, ambient: retrieval.isAmbient),
            isAmbient: retrieval.isAmbient
        )
    }

    /// Builds the final `AskResult` (citations reconciled, reference markers
    /// stripped, output safety scanned) from either the whole-answer `respond`
    /// or the last streamed snapshot.
    private func makeResult(heading1: String?, heading2: String?, body: String, citedRefs: [Int],
                            prep: AskPreparation, question: String, latency: Duration) throws -> AskResult {
        // The model produced output, so whatever else this turn does — including
        // an output-safety throw below — the pipeline is not in an outage.
        noteGenerationSucceeded()
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
        // `cleanedBody`, not `body`: markers are already stripped, and the quote
        // match should see exactly the text the reader sees.
        let citations = Self.reconcileCitations(
            citedRefs, retrieval: prep.retrieval, question: question, body: cleanedBody
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

    func ask(_ question: String, history: [ChatTurn], entries: [Entry], images: [Data]) async throws -> AskResult {
        let clock = ContinuousClock()
        let started = clock.now
        let prep = try await prepareAsk(question: question, history: history, entries: entries, images: images)
        let session = takeSpeculativeSession(matching: prep.plan.fingerprint)
            ?? Self.makeSession(from: prep.plan)
        do {
            let answer = try await Self.respondToAsk(session: session, prompt: prep.prompt,
                                                     images: images, history: history,
                                                     options: prep.generationOptions)
            let result = try makeResult(heading1: answer.heading1, heading2: answer.heading2,
                              body: answer.body, citedRefs: answer.citedRefs ?? [],
                              prep: prep, question: question, latency: clock.now - started)
            return result
        } catch let error as IntelligenceError {
            throw error
        } catch {
            throw mapAnyGenerationError(error)
        }
    }

    /// Ask generation options (spec 029 Amendment A / 039 R1). Temperature
    /// and token cap come from ReplyChannel — 0.9 / 64–128 on light and
    /// companion, 0.7 / 512 on notebook and RAG thread.
    private static func askOptions(for channel: ReplyChannel, retrievalRan: Bool) -> GenerationOptions {
        GenerationOptions(
            temperature: channel.temperature(retrievalRan: retrievalRan),
            maximumResponseTokens: channel.maximumResponseTokens(retrievalRan: retrievalRan)
        )
    }

    /// Image attachments landed in the iOS 27 SDK (Xcode 27 / Swift 6.3+).
    /// Same compiler-version gate as `contextSize` — `#available` cannot see
    /// a member the iOS 26 SDK does not declare.
    private static var canAttachImagesToModel: Bool {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) { return true }
        #endif
        return false
    }

    /// When the SDK cannot attach pixels, produce a Vision reading so the
    /// model still has something to ground "what's in the photo" on.
    private static func visionBlockIfNeeded(current: [Data], history: [ChatTurn]) async -> String? {
        let hasImages = !current.isEmpty || history.contains { !$0.imageJPEGs.isEmpty }
        guard hasImages, !canAttachImagesToModel else { return nil }
        let block = await ChatImageUnderstanding.promptBlock(current: current, history: history)
        return block.isEmpty ? nil : block
    }

    /// Decodes in-session JPEGs into labeled UIImages for the prompt builder.
    private static func decodedAttachments(current: [Data], history: [ChatTurn]) -> [(label: String, image: UIImage)] {
        var result: [(label: String, image: UIImage)] = []
        for (turnIndex, turn) in history.enumerated() {
            for (photoIndex, jpeg) in turn.imageJPEGs.enumerated() {
                if let image = UIImage(data: jpeg) {
                    result.append((
                        "earlier-turn-\(turnIndex + 1)-photo-\(photoIndex + 1)",
                        image
                    ))
                }
            }
        }
        for (photoIndex, jpeg) in current.enumerated() {
            if let image = UIImage(data: jpeg) {
                result.append(("this-message-photo-\(photoIndex + 1)", image))
            }
        }
        return result
    }

    /// One-shot Ask. Uses the prompt-builder + `Attachment` path when the
    /// SDK can see images; otherwise the text-only `respond(to:)`.
    private static func respondToAsk(
        session: LanguageModelSession,
        prompt: String,
        images: [Data],
        history: [ChatTurn],
        options: GenerationOptions
    ) async throws -> AskAnswer {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) {
            let attachments = decodedAttachments(current: images, history: history)
            if !attachments.isEmpty {
                let response = try await session.respond(
                    generating: AskAnswer.self,
                    options: options
                ) {
                    prompt
                    for item in attachments {
                        Attachment(item.image).label(item.label)
                    }
                }
                return response.content
            }
        }
        #endif
        let response = try await session.respond(
            to: prompt,
            generating: AskAnswer.self,
            options: options
        )
        return response.content
    }

    /// Streaming Ask. Same vision gate as `respondToAsk`.
    private static func streamAskResponse(
        session: LanguageModelSession,
        prompt: String,
        images: [Data],
        history: [ChatTurn],
        options: GenerationOptions
    ) -> LanguageModelSession.ResponseStream<AskAnswer> {
        #if compiler(>=6.3)
        if #available(iOS 27.0, *) {
            let attachments = decodedAttachments(current: images, history: history)
            if !attachments.isEmpty {
                return session.streamResponse(
                    generating: AskAnswer.self,
                    options: options
                ) {
                    prompt
                    for item in attachments {
                        Attachment(item.image).label(item.label)
                    }
                }
            }
        }
        #endif
        return session.streamResponse(
            to: prompt,
            generating: AskAnswer.self,
            options: options
        )
    }

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

    func askStream(_ question: String, history: [ChatTurn], entries: [Entry], images: [Data]) -> AsyncThrowingStream<AskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let started = clock.now
                let signposter = PerfSignposts.chatTurn
                let spid = signposter.makeSignpostID()
                do {
                    let prepState = signposter.beginInterval("prep", id: spid)
                    let prep = try await prepareAsk(question: question, history: history, entries: entries, images: images)
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

                    let stream = Self.streamAskResponse(session: session, prompt: prep.prompt,
                                                        images: images, history: history,
                                                        options: prep.generationOptions)
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
                                // Doubly optional now that the field itself is
                                // `[Int]?`: the outer layer is "not yet decoded",
                                // the inner is "decoded as absent".
                                if let refs = content.citedRefs ?? nil { tail.citedRefs = refs }

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
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: self.mapAnyGenerationError(error))
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
            if lens.count > PromptRegistry.maxGeneratedPromptLensChars {
                lens = String(lens.prefix(PromptRegistry.maxGeneratedPromptLensChars))
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
        } catch {
            throw mapAnyGenerationError(error)
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
        } catch {
            throw mapAnyGenerationError(error)
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

    static func buildAskPrompt(question: String, history: [ChatTurn], retrieval: RetrievalResult,
                                       stance: TurnStance, shape: RecallTurnShape,
                                       archiveEmpty: Bool, budget _: ContextBudget,
                                       safetyConstrained: Bool = false,
                                       imageCount: Int = 0,
                                       historyImageCount: Int = 0,
                                       canSeeImages: Bool = false,
                                       visionBlock: String? = nil,
                                       channel: ReplyChannel = .companion,
                                       move: ConversationalMove? = nil,
                                       personalization: PromptPersonalization = .none) -> String {
        // Spec 039 ranks 0–1: Move cue + latest message + optional don't-repeat.
        // No [Turn:] / [Shape:] stack, no evidence, no L1. Names ride [Name:].
        if channel.usesLightPrompt {
            let cue = move?.cueLine ?? ConversationalMove.greetAndAsk.cueLine
            var light: [String] = [cue]
            if safetyConstrained {
                light.insert(SafetyRouter.constrainedStanceLine, at: 0)
            }
            let usedNameLastTurn = personalization.lastAssistantTurnContainsName(history)
            let skipName = move?.avoidsName == true || usedNameLastTurn
            if !skipName, let name = personalization.nameCueLine {
                light.append(name)
            }
            if let anti = ConversationalMove.antiRepeatLine(from: history) {
                light.append(anti)
            }
            if skipName, personalization.spokenName != nil {
                light.append(PromptPersonalization.nameSkipLine)
            }
            light.append("The person's latest message: \(question)")
            return light.joined(separator: "\n\n")
        }

        // The stance line is the first thing the model reads for this turn —
        // the deterministic instruction that stops it from grounding casual
        // conversation in journal entries. Spec 037 / 039: [Shape:] says how
        // to Open; Open is required. Light channels skip this stack.
        var parts: [String] = [stance.promptLine]
        let grounded = stance.isGrounded(retrieval: retrieval)
        if let overlay = TurnShapeCadence.overlayLine(shape: shape, stance: stance,
                                                      isGrounded: grounded) {
            parts.append(overlay)
        }
        if safetyConstrained {
            parts.insert(SafetyRouter.constrainedStanceLine, at: 0)
        }
        let usedNameLastTurn = personalization.lastAssistantTurnContainsName(history)
        let skipName = move?.avoidsName == true || usedNameLastTurn
        // Redirect still gets [Name:] (no L1). Companion/notebook keep names
        // in L1 only — never stack a second cue. Skip the cue when this
        // beat avoids names or the last reply already used one.
        if channel.omitsLens, !skipName, let name = personalization.nameCueLine {
            parts.append(name)
        }
        if !retrieval.contextBlock.isEmpty {
            // Frame as optional evidence so the model does not treat the block
            // as a script to paraphrase ("you wrote this, this, and this").
            //
            // The `.noMatch` case needs the extra line. Ambient retrieval still
            // ships the full text of recent entries, so on a journal question
            // with no topical hit the model was told "say you don't see
            // anything from that stretch" and handed five quotable entries in
            // the same prompt. It resolved that contradiction the obvious way:
            // "What color is my bicycle?" came back with fog on Mount
            // Tamalpais and a friend's remark about feeling calm, never once
            // saying it had nothing. Name the entries as unrelated instead of
            // hoping the stance line outweighs the evidence.
            //
            // NOTE (2026-08-23): withholding the text entirely was tried here
            // and reverted. It fixed the bait cases outright — 8/8 no-match
            // turns stopped quoting and stopped citing — but broke ordinary
            // recall in the same run: "How have I been sleeping?", "What did I
            // write about the hike?" and "What happened with Priya?" all came
            // back "I don't see anything from that stretch" against a journal
            // that answers all three. Those turns are `.noMatch` only because
            // retrieval under-scores them, and the ambient text was the one
            // thing making them answerable. Fix the scoring first; see the
            // retrieval-recall issue.
            let framing = stance == .noMatch
                ? "Journal evidence — NOTHING HERE MATCHES WHAT THEY ASKED ABOUT. "
                + "These are recent entries for background only. Say plainly you don't see "
                + "anything on that topic; do not offer these as an answer to it:\n"
                : "Journal evidence (use only if this turn's stance needs it; do not summarize all of it):\n"
            parts.append(framing + retrieval.contextBlock)
        } else if stance == .noMatch || grounded {
            if archiveEmpty {
                parts.append("[No journal entries in the archive]")
            } else {
                parts.append("[No journal entries matched this topic]")
            }
        }
        // Casual / about-app / outside-scope / sharing-without-context turns get
        // no journal block at all — the stance line already says how to reply.
        // History no longer renders here (spec 029 Amendment A): it rides the
        // session transcript as real turns (AskTranscriptPlan), where its
        // prefill can be paid speculatively. Only the anti-repeat rule stays
        // per-turn — it must not fire on turn one.
        if !history.isEmpty {
            parts.append(
                "Do not reuse openings, questions, or entry summaries you already used "
                    + "earlier in this conversation. Do not reopen an entry you already used "
                    + "in this thread."
            )
        }
        if skipName, personalization.spokenName != nil {
            parts.append(PromptPersonalization.nameSkipLine)
        }
        if imageCount > 0 || historyImageCount > 0 {
            if canSeeImages {
                var vision: [String] = []
                if historyImageCount > 0 {
                    vision.append(
                        "Earlier messages in this conversation included photos, labeled earlier-turn-N-photo-M. If they ask about those photos, look at them."
                    )
                }
                if imageCount > 0 {
                    vision.append(
                        "The person attached \(imageCount) photo\(imageCount == 1 ? "" : "s") to this message, labeled this-message-photo-1… in order. Look at each image. Ground what you say in what is visibly there. Refer to them as \"this photo\" or \"the first photo\" when it helps. Do not invent details that are not visible."
                    )
                }
                parts.append(vision.joined(separator: " "))
            } else if let visionBlock, !visionBlock.isEmpty {
                parts.append(
                    "The person attached photo\(imageCount + historyImageCount == 1 ? "" : "s"). A visual reading of each follows. Treat it as what is in the images. Refer to them as \"this photo\" or \"the first photo\" when it helps. Do not invent details beyond this reading and what they wrote.\n\n"
                    + visionBlock
                )
            } else {
                parts.append(
                    "The person attached photo\(imageCount + historyImageCount == 1 ? "" : "s"). Image understanding is not available on this device, so you cannot see them. Acknowledge the attachment without describing what you cannot see."
                )
            }
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
    /// downstream strips markers — `RichTextParser` does not treat `[n]` as a link,
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
            // Schema field names written as prose. FIRST, because the model
            // emits `citedRefs:[1]` / `citedRefs: 1.` as a trailing line of the
            // body far more often than it emits a bare `[ref 1]` — measured
            // 2026-08-23, and the same behaviour that used to kill the turn
            // outright before `AskAnswer.citedRefs` became optional. The
            // `\brefs?` pattern below can never match inside `citedRefs`
            // (`d` and `R` are both word characters), so this is not redundant.
            #"\s*\bcitedRefs\b\s*:?\s*(?:\[[^\]]*\]|"# + numberList + #")?\.?"#,
            #"\s*\bheading[12]\b\s*:?\s*"#,
            #"\s*[\[(]\s*refs?\.?\s*#?"# + numberList + #"\s*[\])]"#,
            #"\s*\[\s*"# + numberList + #"\s*\]"#,
            #"\s*\brefs?\.?\s*#?"# + numberList + #"\b"#,
            // Bracket pairs the number-bearing patterns above cannot see:
            // `[,]`, `[]`, `[ref]`, `[-]`. Observed live as a trailing `[,]`.
            // Bounded to 6 inner characters and no digits so a real aside in
            // square brackets is left alone.
            #"\s*\[\s*[^\]\d]{0,6}\s*\]"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// Tidy what removal left behind: a space before punctuation, doubled
    /// spaces, and an emptied parenthesis pair.
    private static let cleanupRegexes: [(regex: NSRegularExpression, template: String)] = {
        let cleanups: [(String, String)] = [
            (#"\s+([,.;:!?])"#, "$1"),
            (#"[ \t]{2,}"#, " "),
            (#"\(\s*\)"#, ""),
            // The square-bracket twin of the rule above — a removal can leave
            // `[]` behind the same way it leaves `()`.
            (#"\[\s*\]"#, ""),
            // Removing a trailing field name leaves the blank line it sat on.
            (#"\n{3,}"#, "\n\n")
        ]
        return cleanups.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    /// Artefacts of a generation that ran off the end of its reply, rather than
    /// anything the model meant to say. All observed in the chat eval gate on
    /// 2026-08-23 and all unambiguous, which is why removing them is safe:
    ///
    /// - a `<ctrl46>` control token and everything after it — one reply spilled
    ///   2,122 characters this way, continuing past its closing question into
    ///   `**} <ctrl46>Memento leans into the quiet…`;
    /// - a trailing `}` / `**}` where the structured object leaked into prose;
    /// - a dangling heading the reply never filled in (`### July 19, 2026 *`
    ///   as the final line, the italic quote never arriving) — five replies
    ///   ended mid-notebook-moment like this;
    /// - a lone trailing `###` on a turn that should carry no heading at all.
    ///
    /// Deliberately conservative: it removes only trailing wreckage and never
    /// rewrites the reply. Nothing here can add a closing question the model
    /// failed to write — a reply that stops early is reported by the gate as
    /// `rule.noOpen`, not quietly patched.
    private static let truncationArtifactRegexes: [NSRegularExpression] = {
        let patterns = [
            #"<ctrl[\s\S]*$"#,                 // control token → end
            #"\*{0,2}\}\s*$"#,                 // leaked closing brace at the end
            // A heading the reply never filled in. The character class excludes
            // sentence punctuation and caps the run at 40, which is what keeps
            // this off a heading used *inline* mid-reply: replies are often a
            // single line ("…quiet shifts. ### August 2, 2026 *“…”* … What is
            // it you're holding onto right now?"), and an earlier version of
            // this pattern matched from `###` to end of string and deleted the
            // quote, the reflection and the closing question with it. Five
            // otherwise-clean replies lost their question that way before the
            // eval gate caught it.
            #"\n?#{3}[^\n?.!]{0,40}\*?[ \t]*$"#,
            #"\n?#{3}\s*$"#                    // bare trailing ###
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func strippingReferenceMarkers(_ body: String) -> String {
        var out = body
        for regex in truncationArtifactRegexes {
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: ""
            )
        }
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

    /// Which journal entries this reply may be attributed to.
    ///
    /// Three sources, in priority order:
    ///
    /// 1. **What the model said it used** (`refs`), filtered to refs that were
    ///    actually in the prompt — a hallucinated ref number cites nothing.
    /// 2. **What the reply demonstrably quotes** (`quotedRefs(in:)`). Derived in
    ///    Swift from the body, so it cannot be fabricated and does not depend on
    ///    the model filling `citedRefs` — which it frequently does not, writing
    ///    the field into its prose instead (see `AskAnswer`). This is what makes
    ///    "the reply quoted an entry" and "the UI shows that entry" the same
    ///    statement rather than two independent guesses.
    /// 3. **The top reviewed entries**, only for a real topical match, so
    ///    "Reviewed your journals" appears from the first delta and stays put.
    ///
    /// Ambient retrieval (recent life handed over as background, no topical
    /// match) used to return `[]` unconditionally. That was the bug behind
    /// replies that quoted an entry verbatim while the citation UI showed
    /// nothing: the entries were in the prompt and quotable, but uncitable.
    /// Ambient results are now citable — but they get no top-N fallback, so an
    /// ambient turn cites exactly what it used and nothing more.
    ///
    /// `body` is nil on the pre-generation call that seeds the "Reviewed your
    /// journals" link, where there is no reply text to check yet.
    ///
    /// Gating citations on a `.noMatch` stance was tried on 2026-08-23 and
    /// reverted with the context-block change above: too many turns that the
    /// journal genuinely answers are labelled `.noMatch` by retrieval, so the
    /// gate silently stripped citations from correct, grounded replies.
    private static func reconcileCitations(_ refs: [Int], retrieval: RetrievalResult,
                                           question: String, body: String? = nil) -> [AskCitation] {
        guard !retrieval.isEmpty else { return [] }
        let byRef = Dictionary(uniqueKeysWithValues: retrieval.entries.map { ($0.ref, $0) })

        var seen = Set<Int>()
        var chosenRefs = refs.filter { byRef[$0] != nil && seen.insert($0).inserted }

        if let body {
            for ref in quotedRefs(in: body, retrieval: retrieval) where seen.insert(ref).inserted {
                chosenRefs.append(ref)
            }
        }

        if chosenRefs.isEmpty, !retrieval.isAmbient {
            chosenRefs = retrieval.entries.prefix(maxCitations).map(\.ref)
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

    /// Refs whose entry text the reply reproduces verbatim.
    ///
    /// Matching is on a normalised form — case, curly quotes, dashes and
    /// whitespace all vary between what the model emits and what is stored, and
    /// a quote that survives the model's typography is still a quote. The
    /// 30-character window is long enough that ordinary shared phrasing ("I have
    /// not felt") does not trip it, short enough to catch a clipped quote.
    private static func quotedRefs(in body: String, retrieval: RetrievalResult) -> [Int] {
        let needle = citationFold(body)
        guard needle.count >= quoteWindow else { return [] }
        let windows = Array(needle)
        return retrieval.entries.compactMap { entry -> Int? in
            let hay = citationFold(entry.text)
            guard hay.count >= quoteWindow else { return nil }
            for i in 0...(windows.count - quoteWindow) {
                if hay.contains(String(windows[i..<(i + quoteWindow)])) { return entry.ref }
            }
            return nil
        }
    }

    private static let quoteWindow = 30

    private static func citationFold(_ s: String) -> String {
        var t = s.lowercased()
        for (from, to) in [("\u{2019}", "'"), ("\u{2018}", "'"),
                           ("\u{201C}", "\""), ("\u{201D}", "\""),
                           ("\u{2014}", "-"), ("\u{2013}", "-")] {
            t = t.replacingOccurrences(of: from, with: to)
        }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
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
        // Guardrail refusals are a *designed* empty state, not a failure — but
        // only when the guardrail actually judged the content.
        switch error {
        case .guardrailViolation:
            guard !isInfrastructureFailure(String(describing: error)) else {
                // The safety classifier could not run at all. Reported by the
                // SDK as a guardrail violation, it is really a broken model
                // asset, and treating it as a content decision is the worst
                // possible read: the person is told "I don't have an
                // observation for this one." about every message they send,
                // forever, with no error and no retry, while
                // `recordAFMGuardrailRefusal` quietly poisons the safety
                // metric with failures that have nothing to do with safety.
                //
                // Seen on this machine's iOS 26.0 simulator runtime, where
                // `com.apple.fm.language.instruct_300m.safety` fails to load
                // (`promptTemplateNotFound`) and *every* generation refuses —
                // including a bare `LanguageModelSession()` with no app
                // instructions at all.
                return .generationFailed(error.localizedDescription)
            }
            SafetyMetrics.recordAFMGuardrailRefusal()
            return .guardrailRefusal
        case .refusal:
            // The model declined the content itself. Same designed empty state
            // as a guardrail refusal from the user's side — authored copy, a
            // Try again, and a persisted turn — rather than "I couldn't put a
            // reflection together just now", which invites a retry that will
            // deterministically fail the same way.
            //
            // Worth knowing what actually lands here. In the chat eval gate on
            // 2026-08-23 the refusals were, verbatim: "What did I write the day
            // my grandmother died?", "What has grief looked like for me this
            // year?", and "What happened with my knee in March?" — bereavement
            // and a knee injury, i.e. the substance of an ordinary journal. We
            // cannot argue the on-device model out of that, but the reply the
            // person sees should at least not pretend it was a glitch.
            SafetyMetrics.recordAFMGuardrailRefusal()
            return .guardrailRefusal
        case .exceededContextWindowSize:
            // Split out of `default` so it is distinguishable in logs from a
            // decode failure — the two want opposite fixes (shrink the input
            // vs. loosen the schema) and used to be one indistinguishable
            // `generationFailed` string.
            return .generationFailed("Context window exceeded: \(error.localizedDescription)")
        default:
            return .generationFailed(error.localizedDescription)
        }
    }

    /// Does this guardrail describe the safety classifier failing to *run*,
    /// rather than declining the content?
    ///
    /// Matched against the error's reflected description. `Context` publishes
    /// only `debugDescription` in the SDK interface — and that reads "May
    /// contain sensitive or unsafe content" either way, which is exactly the
    /// misleading part. The underlying chain does appear in the reflected form:
    ///
    ///     guardrailViolation(Context(debugDescription: "May contain sensitive
    ///     or unsafe content", underlyingErrors: [Error Domain=
    ///     com.apple.SensitiveContentAnalysisML Code=15 "Failed model manager
    ///     query for model com.apple.fm.language.instruct_300m.safety:
    ///     InferenceError::hostFailed::…::promptTemplateNotFound"]))
    ///
    /// so that is what we read. String matching is not ideal; it is what the
    /// SDK surface allows. The markers chosen are all structural
    /// (`ModelManager`, `InferenceError`, `hostFailed`) rather than prose, so
    /// they should not drift with wording changes — and the failure mode of a
    /// miss is simply the old behaviour.
    static func isInfrastructureFailure(_ reflected: String) -> Bool {
        ["ModelManager", "InferenceError", "hostFailed",
         "promptTemplateNotFound", "Failed model manager query"]
            .contains { reflected.contains($0) }
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
