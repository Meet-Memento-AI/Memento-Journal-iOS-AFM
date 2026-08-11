//
//  IntelligenceService.swift
//  MeetMemento
//
//  The app's single intelligence boundary (architecture principle P3 /
//  REQ-INT-001, spec 017). Every AI surface depends on THIS protocol; only the
//  concrete `FoundationModelsIntelligenceService` imports `FoundationModels`.
//  No `import FoundationModels` may appear in this file.
//

import Foundation

// MARK: - Intent & zones

/// What kind of generation is being requested (spec 017 R2 routing).
/// `CaseIterable` so ModelRouterTests can assert the routing table is
/// exhaustive — adding an intent without a row breaks the build's tests.
enum GenerationIntent: Sendable, Equatable, CaseIterable {
    case ask              // journal chat / Ask surface
    case summary          // turn a conversation into a journal entry
    case profileEstimate  // map LearnAboutYourself text → ThemeCatalog ids + prompt lens
}

// The trust-zone contract lives in `TrustZone.swift` (spec 014 R1) — the
// canonical `.z0Device` / `.z1AppleContent(reasoningLevel:)` /
// `.z1AppleContentFree` enum. Routing decisions live in `ModelRouter.swift`
// (spec 017 R2); quota governance in `QuotaGovernor.swift` (spec 017 R3);
// context budgeting in `ContextBudget.swift` (spec 017 R9).

// MARK: - Request / outcome envelopes (spec 017 R1)

/// The declared shape of one generation call. `zone` is set BEFORE the call —
/// by `ModelRouter.resolve`, never inferred after (spec 014 R1 rule; any
/// analogous type lacking `zone` fails review).
struct GenerationRequest: Sendable, Equatable {
    let intent: GenerationIntent
    let zone: TrustZone
    let allowsDegradation: Bool
    let promptVersion: String
    let toolsEnabled: Bool
}

/// What every generation returns alongside its value (REQ-INT-002 /
/// REQ-PRM-004): the zone it ACTUALLY ran in, the model, whether it was a
/// disclosed degradation, and wall-clock latency. There is no API shape in
/// which a caller can be unaware of where generation happened.
struct GenerationOutcome<T: Sendable>: Sendable {
    let value: T
    let zoneUsed: TrustZone
    let modelIdentifier: String
    let wasDegraded: Bool
    let latency: Duration
}

// MARK: - Conversation input

/// One turn of a conversation, in the intelligence layer's own vocabulary
/// (decoupled from the UI's `ChatMessage`).
struct ChatTurn: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let text: String
}

// MARK: - Ask output

/// A journal entry the model actually grounded a claim in. Reconciled against
/// the entries that were placed in context, so a citation can never be
/// fabricated (the on-device equivalent of the server's `filterCitedIdsToAllowed`).
struct AskCitation: Sendable, Equatable {
    let entryId: UUID
    let entryDate: Date
    let excerpt: String
}

/// The complete result of an Ask turn — what `ask` returns and what
/// `askStream` delivers in its final `.completed` event (spec 017 R6).
struct AskResult: Sendable {
    let heading1: String?
    let heading2: String?
    let body: String
    let citations: [AskCitation]
    let zoneUsed: TrustZone
    let wasDegraded: Bool
    let promptVersion: String
    let modelIdentifier: String
    /// Wall-clock generation latency (spec 017 R1; instrumentation for the
    /// spec 022 quality study — never a custom timing subsystem).
    let latency: Duration
}

/// An incremental event from a streaming ask (spec 017 R6). `delta` carries the
/// reply **so far** (cumulative, not just the new chunk) so the UI can render it
/// directly; `final` carries the completed result with reconciled citations.
///
/// `reviewedCitations` are the journals retrieval already surfaced for a grounded
/// turn — known before the first token — so the "Reviewed your journals" link can
/// appear right away instead of waiting for the model's final `citedRefs`. Empty
/// for non-grounded turns. `final`'s reconciled citations supersede them.
enum AskStreamEvent: Sendable {
    case delta(bodySoFar: String, heading1: String?, heading2: String?, reviewedCitations: [AskCitation])
    case final(AskResult)
}

/// Onboarding personalization estimate: closed-vocab theme ids + a bounded lens.
struct ProfileEstimateResult: Sendable, Equatable {
    let themeIds: [String]
    let secondaryThemeIds: [String]
    let promptLens: String
    let zoneUsed: TrustZone
    let wasDegraded: Bool
    let promptVersion: String
    let modelIdentifier: String
    /// Wall-clock generation latency (spec 017 R1).
    let latency: Duration
}

// MARK: - Availability

/// Why the intelligence layer can't run, if it can't. Surfaces to the UI as a
/// designed state, never a crash (technology/02 §4).
enum IntelligenceUnavailableReason: Sendable, Equatable {
    case deviceNotEligible      // no Apple Intelligence on this device
    case modelNotReady          // still downloading / setting up
    case osTooOld               // shouldn't happen at iOS 26 min, defensive
    case other(String)

    var userMessage: String {
        switch self {
        case .deviceNotEligible:
            return "On-device intelligence isn't available on this device, so reflections and chat are turned off here."
        case .modelNotReady:
            return "Apple Intelligence is still getting ready. Try again in a little while."
        case .osTooOld:
            return "This feature needs a newer version of iOS."
        case .other(let message):
            return message
        }
    }
}

enum IntelligenceAvailability: Sendable, Equatable {
    case available(TrustZone)
    case unavailable(IntelligenceUnavailableReason)
}

// MARK: - Errors

/// Errors the intelligence layer surfaces. `guardrailRefusal` is a *designed*
/// empty state (technology/01 §11), not a failure — journaling content trips
/// safety guardrails disproportionately and must never read as judgment.
enum IntelligenceError: Error, LocalizedError {
    case unavailable(IntelligenceUnavailableReason)
    case guardrailRefusal
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason.userMessage
        case .guardrailRefusal: return "I don't have an observation for this one."
        case .generationFailed: return "I couldn't put a reflection together just now. Please try again."
        }
    }
}

// MARK: - The boundary

/// The single seam between the app and Apple Foundation Models. Concrete
/// implementation: `FoundationModelsIntelligenceService`.
protocol IntelligenceService: Sendable {
    /// Answer a question about the user's journal. `entries` are the decrypted
    /// on-device entries the retriever selects from; `history` is the prior
    /// conversation (oldest first) so follow-ups have context. Stateless — the
    /// caller owns the transcript.
    func ask(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskResult

    /// Streaming variant of `ask` (spec 017 R6: chat streams; reflections and
    /// summaries never do). Yields cumulative `.delta` events as the reply grows
    /// and exactly one `.final` before finishing. Defaulted to a one-shot wrap
    /// of `ask` so conforming fakes stay small.
    func askStream(_ question: String, history: [ChatTurn], entries: [Entry]) -> AsyncThrowingStream<AskStreamEvent, Error>

    /// Turn a conversation into a first-person journal-entry summary. Returns
    /// a full outcome envelope (spec 017 R1) — zoneUsed/modelIdentifier/
    /// wasDegraded/latency are always populated.
    func summarizeConversation(_ turns: [ChatTurn]) async throws -> GenerationOutcome<String>

    /// Map a user's onboarding reflection onto ThemeCatalog ids and a short
    /// prompt lens. Callers must validate ids through `ThemeCatalog.validate`.
    func estimateProfile(reflection: String) async throws -> ProfileEstimateResult

    /// Whether generation can run right now, and in which zone.
    func availability() async -> IntelligenceAvailability

    /// Warm the model ahead of the first request (e.g. when the chat view
    /// appears). Fire-and-forget; no-op where unsupported.
    func prewarm()
}

extension IntelligenceService {
    // Default no-op so non-model implementations (mocks/tests) opt in only if
    // they want to.
    func prewarm() {}

    /// Default streaming implementation: run the one-shot `ask` and emit a
    /// single delta + final. Mocks and any non-streaming implementation get
    /// correct (if non-incremental) behavior for free; the real Foundation
    /// Models service overrides this with true snapshot streaming.
    func askStream(_ question: String, history: [ChatTurn], entries: [Entry]) -> AsyncThrowingStream<AskStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await ask(question, history: history, entries: entries)
                    continuation.yield(.delta(bodySoFar: result.body, heading1: result.heading1,
                                              heading2: result.heading2, reviewedCitations: result.citations))
                    continuation.yield(.final(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
