//
//  EpistemicGuard.swift
//  MeetMemento
//
//  Checks a finished reply against the rung the code already chose.
//  It does not rewrite the voice. No Foundation Models import.
//

import Foundation

enum EpistemicGuard {

    struct Finding: Equatable, Sendable {
        var code: String
    }

    /// Content-free codes. Callers may log `code` and must not log the body.
    static func findings(body: String, rung: EvidenceRung) -> [Finding] {
        var found: [Finding] = []
        if rung == .none, body.contains("###") || body.contains("*") {
            found.append(Finding(code: "epistemic.formOnNone"))
        }
        let lower = body.lowercased()
        if rung == .none, lower.contains("closest") {
            found.append(Finding(code: "epistemic.nearestQuote"))
        }
        return found
    }
}
