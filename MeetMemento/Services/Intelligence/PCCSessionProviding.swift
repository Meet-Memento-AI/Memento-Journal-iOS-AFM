//
//  PCCSessionProviding.swift
//  MeetMemento
//
//  The seam where the Private Cloud Compute (Z1) leg plugs in — spec 017 R2/R7.
//
//  Deliberately its own file, and deliberately free of `FoundationModels`:
//  `PrivateCloudComputeLanguageModel` is an iOS-27-SDK type that does not exist
//  in the iOS 26 SDK CI builds with, so the *protocol* must be expressible
//  without it. Only the eventual conforming type needs SDK gating, and it will
//  live inside the single importer — which keeps
//  `check_single_intelligence_importer.sh` green and means adding the real
//  provider changes a construction site, not a call site.
//

import Foundation

/// Whether this build can reach Apple's Private Cloud Compute at all.
///
/// This is a question about the *SDK*, not about the network or the user's
/// eligibility — quota and reachability are `QuotaGovernor`'s business. Keeping
/// them separate is what lets the router distinguish "there is no Z1 here, so
/// on-device is the baseline" from "Z1 exists and could not take this request,
/// so the user is genuinely getting less" — the difference between an honest
/// silence and an honest degradation label.
protocol PCCSessionProviding: Sendable {
    var isSupported: Bool { get }
}

/// The only conformance that exists on the iOS 26 SDK. Reports unsupported, so
/// `ModelRouter` resolves Z1 rows to Z0 as the baseline and never labels the
/// result degraded.
struct UnavailablePCCProvider: PCCSessionProviding {
    var isSupported: Bool { false }
}
