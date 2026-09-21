//
//  RetractedClaims.swift
//  MeetMemento
//
//  A correction or an interpretation-cut stores the claim the assistant just
//  made. Later turns must not repeat it. Derived from history so nothing
//  persists off the conversation.
//

import Foundation

enum RetractedClaims {

    static func claims(in history: [ChatTurn]) -> [String] {
        var found: [String] = []
        for (index, turn) in history.enumerated() where turn.role == .user {
            let shape = QuestionShapeResolver.shape(of: turn.text, turn: .share)
            guard shape == .correction || shape == .interpretationCut else { continue }
            guard let prior = history[..<index].last(where: { $0.role == .assistant }) else { continue }
            // budget-exempt: retracted-claim clip, not a model window
            let clip = String(prior.text.prefix(180))
            if !clip.isEmpty, !found.contains(clip) { found.append(clip) }
        }
        return found
    }

    static func interpretationCutActive(in history: [ChatTurn]) -> Bool {
        history.contains { turn in
            turn.role == .user
                && QuestionShapeResolver.shape(of: turn.text, turn: .share) == .interpretationCut
        }
    }

    static func promptLine(claims: [String], interpretationCut: Bool) -> String? {
        var lines: [String] = []
        if interpretationCut {
            lines.append("Stay on their words. Do not add a metaphor they did not use.")
        }
        if !claims.isEmpty {
            lines.append("Do not repeat this retracted claim: \(claims.joined(separator: " | "))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
