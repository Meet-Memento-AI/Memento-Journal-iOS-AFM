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
enum GenerationIntent: Sendable {
    case ask              // journal chat / Ask surface
    case summary          // turn a conversation into a journal entry
    case profileEstimate  // map LearnAboutYourself text → ThemeCatalog ids + prompt lens
}

/// The trust zone a generation actually ran in (spec 014 R1 / REQ-INT-002).
/// `onDevice` = Z0 (`SystemLanguageModel`, offline); `privateCloud` = Z1 (PCC).
enum IntelligenceZone: Sendable, Equatable {
    case onDevice
    case privateCloud
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

/// The complete result of an Ask turn. One-shot for now; a streaming variant
/// (spec 017 R6) is a follow-up — the current UI already animates the reply in.
struct AskResult: Sendable {
    let heading1: String?
    let heading2: String?
    let body: String
    let citations: [AskCitation]
    let zoneUsed: IntelligenceZone
    let wasDegraded: Bool
    let promptVersion: String
    let modelIdentifier: String
}

/// Onboarding personalization estimate: closed-vocab theme ids + a bounded lens.
struct ProfileEstimateResult: Sendable, Equatable {
    let themeIds: [String]
    let secondaryThemeIds: [String]
    let promptLens: String
    let zoneUsed: IntelligenceZone
    let wasDegraded: Bool
    let promptVersion: String
    let modelIdentifier: String
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
    case available(IntelligenceZone)
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

    /// Turn a conversation into a first-person journal-entry summary.
    func summarizeConversation(_ turns: [ChatTurn]) async throws -> String

    /// Map a user's onboarding reflection onto ThemeCatalog ids and a short
    /// prompt lens. Callers must validate ids through `ThemeCatalog.validate`.
    func estimateProfile(reflection: String) async throws -> ProfileEstimateResult

    /// Whether generation can run right now, and in which zone.
    func availability() async -> IntelligenceAvailability
}
