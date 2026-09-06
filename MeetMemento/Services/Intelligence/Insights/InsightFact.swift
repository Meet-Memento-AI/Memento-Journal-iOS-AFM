//
//  InsightFact.swift
//  MeetMemento
//
//  Spec 045 R1: a Swift-computed fact with a mandatory n. No FoundationModels.
//

import Foundation

/// One computed observation about the journal. `n` is the sample size and
/// drives the low-confidence state (`n < 4`). The model never invents this.
public struct InsightFact: Sendable, Equatable, Codable, Hashable {
    public enum Kind: String, Sendable, Codable, Hashable {
        case count, cadence, cluster, person, place, lastMention
    }

    public var kind: Kind
    public var label: String
    public var value: String
    public var n: Int
    public var window: DateInterval
    public var supportingEntryIDs: [UUID]

    public init(
        kind: Kind,
        label: String,
        value: String,
        n: Int,
        window: DateInterval,
        supportingEntryIDs: [UUID]
    ) {
        self.kind = kind
        self.label = label
        self.value = value
        self.n = n
        self.window = window
        self.supportingEntryIDs = supportingEntryIDs
    }

    public var isLowConfidence: Bool { n < InsightEngine.lowConfidenceThreshold }

    public static let lowConfidenceCopyPrefix = "Based on "
    public static func lowConfidenceCopy(n: Int) -> String {
        "Based on \(n) entries — too few to call a pattern."
    }
}
