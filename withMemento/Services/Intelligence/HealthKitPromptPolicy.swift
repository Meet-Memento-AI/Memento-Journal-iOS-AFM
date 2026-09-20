//
//  HealthKitPromptPolicy.swift
//  MeetMemento
//
//  Spec 015 R4 / DEC-006: HealthKit may be read as coarse Z0 metadata on the
//  entry, but it never enters a Z1 prompt. The model does not see sleep,
//  workout, or state-of-mind buckets.
//

import Foundation

enum HealthKitPromptPolicy {
    /// Written DEC-006: HealthKit context never enters Z1 prompts.
    static let allowsZ1Prompts = false

    static func mayIncludeHealth(in zone: TrustZone) -> Bool {
        switch zone {
        case .z0Device:
            return true
        case .z1AppleContent, .z1AppleContentFree:
            return allowsZ1Prompts
        }
    }

    static func promptFragment(snapshot: HealthSnapshot?, zone: TrustZone) -> String? {
        guard mayIncludeHealth(in: zone), let snapshot, snapshot.hasAnyValue else {
            return nil
        }
        return snapshot.z0SummaryLine
    }
}
