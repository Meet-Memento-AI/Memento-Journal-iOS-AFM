//
//  AskPipeline.swift
//  withMemento
//
//  The readable map of one Ask turn. Later sessions edit stages here.
//  This file does not import FoundationModels. The service still generates.
//
//  Eight steps, in order:
//  1. safety — SafetyRouter, thrown by the service before `plan`
//  2. response policy — the turn the classifier already picked; S7 names the policy
//  3. evidence ladder — S6 writes one rung; today the plan carries no rung
//  4. retrieval — the service still retrieves after `plan`, then builds the
//     turn's EvidencePack from what the prompt will carry (spec 050)
//  5. prompt — the service still builds the prompt; the pack adds the
//     [Evidence] marker legend
//  6. generate — the service still generates; the model places markers
//  7. render — ReplyRenderer expands markers from the pack and strips what
//     the pack cannot back, on the final body and on every streamed delta
//  8. epistemic guard — output safety and the rung check read the rendered body
//

import Foundation

/// Decisions known before generation. Channel, stance, and schema match
/// what `prepareAskCore` picked before this type existed.
struct AskTurnPlan: Sendable, Equatable {
    var turn: TurnType
    var channel: ReplyChannel
    var evidence: EvidenceState
    /// Pre-retrieval stance from `RetrievalPolicy.stance`. Journal stance
    /// still refines after retrieval inside the service.
    var stance: TurnStance
    var shape: QuestionShape
    var policy: ResponsePolicy
    var usesBodyOnlySchema: Bool
}

enum AskPipeline {

    /// Classify, then resolve the same channel the service used to pick inline.
    static func plan(
        question: String,
        history: [ChatTurn],
        hasImages: Bool,
        spoken: Bool,
        lastAssistantAskedQuestion: Bool = false,
        evidence: EvidenceState = .matched,
        retrieval: RetrievalResult = .empty
    ) -> AskTurnPlan {
        let turn = TurnClassifier.classify(
            question,
            hasHistory: !history.isEmpty,
            lastAssistantAskedQuestion: lastAssistantAskedQuestion
        )
        return plan(
            turn: turn,
            question: question,
            history: history,
            hasImages: hasImages,
            spoken: spoken,
            evidence: evidence,
            retrieval: retrieval
        )
    }

    /// Channel map for a turn the caller already classified. Photo bump and
    /// the spoken follow-up recipe stay inside `ReplyChannel`.
    static func plan(
        turn: TurnType,
        question: String = "",
        history: [ChatTurn] = [],
        hasImages: Bool,
        spoken: Bool = false,
        evidence: EvidenceState = .matched,
        retrieval: RetrievalResult = .empty
    ) -> AskTurnPlan {
        let channel = ReplyChannel.resolve(turn: turn, hasImages: hasImages, evidence: evidence)
            .applyingSpokenFollowUpRecipe(turn: turn, history: history, spoken: spoken)
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        let policy = ResponsePolicyResolver.policy(shape: shape, evidence: evidence)
        return AskTurnPlan(
            turn: turn,
            channel: channel,
            evidence: evidence,
            stance: stance,
            shape: shape,
            policy: policy,
            usesBodyOnlySchema: channel.usesBodyOnlySchema(spoken: spoken, evidence: evidence)
        )
    }
}
