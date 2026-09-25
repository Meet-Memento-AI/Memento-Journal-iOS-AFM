//
//  OnDeviceModelTier.swift
//  withMemento
//
//  Spec 051 R1 / REQ-TIER-001: which on-device model answered. iOS 27 ships
//  two — AFM 3 Core (3B, dense) on every Apple Intelligence device and AFM 3
//  Core Advanced (20B, sparse) on devices with at least 12 GB of unified
//  memory — and `SystemLanguageModel.default` resolves to whichever the
//  device runs. Nothing in the SDK verified so far names the tier, so this
//  file infers it from the OS version and physical memory, and says so
//  (`source == .inferred`). A tier the SDK reports always wins.
//
//  Pure Swift; no `FoundationModels` import (single-importer gate,
//  scripts/ci/check_single_intelligence_importer.sh). The importer supplies
//  the inputs; the rules live here so they are testable off device.
//
//  The tier is provenance and budget input only. On path B (spec 051 R0) the
//  OS still chooses the model, so a mislabelled device never runs the wrong
//  one — it only writes the wrong suffix on a row.
//

import Foundation

enum OnDeviceModelTier: String, Sendable, Equatable, CaseIterable {
    /// iOS < 27: the 2025-generation on-device model.
    case preAFM3
    case afm3Core
    case afm3CoreAdvanced
    /// The model is unavailable, or nothing has been resolved yet.
    case unknown

    /// Suffix on the `.z0Device` model identifier (spec 051 R3). `nil` keeps
    /// the historical bare `apple.system.on-device`, so rows written before
    /// the tier existed and rows whose tier is unknown still join.
    var identifierSuffix: String? {
        switch self {
        case .preAFM3: return "pre-afm3"
        case .afm3Core: return "afm3-core"
        case .afm3CoreAdvanced: return "afm3-core-advanced"
        case .unknown: return nil
        }
    }
}

enum OnDeviceModelTierSource: String, Sendable, Equatable {
    /// Read from the SDK (spec 051 R0 path A).
    case reported
    /// Derived from OS version and physical memory (path B).
    case inferred
}

struct ResolvedOnDeviceModelTier: Sendable, Equatable {
    let tier: OnDeviceModelTier
    let source: OnDeviceModelTierSource

    static let unresolved = ResolvedOnDeviceModelTier(tier: .unknown, source: .inferred)
}

enum OnDeviceModelTierResolver {
    /// First OS major version that ships the AFM 3 models.
    static let firstAFM3OSMajorVersion = 27

    /// Hardware class boundary between Apple's 8 GB and 12 GB devices, in
    /// bytes. Not a context window. A 12 GB device reports somewhat under
    /// 12 GiB of physical memory and an 8 GB device somewhat under 8 GiB, so
    /// the floor sits between the two classes rather than at either.
    static let coreAdvancedMemoryFloorBytes: UInt64 = 10_000_000_000

    /// Spec 051 R1's rules, in order: unavailable → unknown; a reported tier
    /// wins; pre-iOS 27 → preAFM3; then the memory class.
    static func resolve(
        reported: OnDeviceModelTier?,
        modelAvailable: Bool,
        osMajorVersion: Int,
        physicalMemoryBytes: UInt64
    ) -> ResolvedOnDeviceModelTier {
        guard modelAvailable else { return .unresolved }
        if let reported, reported != .unknown {
            return ResolvedOnDeviceModelTier(tier: reported, source: .reported)
        }
        guard osMajorVersion >= firstAFM3OSMajorVersion else {
            return ResolvedOnDeviceModelTier(tier: .preAFM3, source: .inferred)
        }
        let tier: OnDeviceModelTier = physicalMemoryBytes >= coreAdvancedMemoryFloorBytes
            ? .afm3CoreAdvanced
            : .afm3Core
        return ResolvedOnDeviceModelTier(tier: tier, source: .inferred)
    }
}

/// Process-wide resolved tier. Mirrors the importer's availability cache:
/// only a known tier is stored, so a device whose model is still downloading
/// re-resolves later instead of being pinned to `.unknown` for the process.
final class OnDeviceModelTierCache: @unchecked Sendable {
    static let shared = OnDeviceModelTierCache()

    private let lock = NSLock()
    private var resolved: ResolvedOnDeviceModelTier?

    var current: ResolvedOnDeviceModelTier {
        lock.lock(); defer { lock.unlock() }
        return resolved ?? .unresolved
    }

    var hasResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved != nil
    }

    func store(_ value: ResolvedOnDeviceModelTier) {
        guard value.tier != .unknown else { return }
        lock.lock(); defer { lock.unlock() }
        resolved = value
    }

    /// Drops the cached tier so the next availability check re-resolves.
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        resolved = nil
    }
}
