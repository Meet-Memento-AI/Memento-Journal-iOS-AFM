//
//  SpikeC_NamedIndexVisibilityTests.swift
//  MeetMementoTests
//
//  Spec 013 R1 / DEC-002 / V1 — can Spotlight donation be hidden from
//  system-wide search while remaining app-retrievable?
//
//  The iOS 27 SDK sweep (2026-07-26) sharpened this: donation supports
//  CSSearchableIndex(name:protectionClass:), but SpotlightSearchTool's
//  sources have no named-index parameter, and the header calls the name a
//  client-state batching handle — so hiding and retrievability may be
//  coupled. This harness automates the retrievability half of V1's test
//  sequence; the visibility half is a human check on a REAL DEVICE:
//
//    MANUAL STEPS (device, after running this test with SPIKE_C=1):
//    1. Home screen → swipe down → system Spotlight.
//    2. Search "quokka-sentinel" (named-index marker) — if the item
//       appears, named indexes are NOT hidden → DEC-002 negative.
//    3. Search "wombat-sentinel" (default-index control) — should appear;
//       proves donation itself is visible so step 2 is a fair test.
//    4. Record both outcomes in spec 013 R1's verdict.
//
//  Env-gated: TEST_RUNNER_SPIKE_C=1. Safe to run in the simulator for the
//  in-app retrieval answers; only the manual steps need hardware.
//

import XCTest
import CoreSpotlight
import UniformTypeIdentifiers

final class SpikeC_NamedIndexVisibilityTests: XCTestCase {

    private static let namedIndexName = "memento-spike-c"
    private static let domain = "spike-c.memento"

    func test_spikeC_namedIndexDonation_inAppRetrievability() async throws {
        guard ProcessInfo.processInfo.environment["SPIKE_C"] == "1" else {
            throw XCTSkip("Spike C runs only with TEST_RUNNER_SPIKE_C=1 (spec 013 R1)")
        }
        guard CSSearchableIndex.isIndexingAvailable() else {
            throw XCTSkip("Core Spotlight indexing unavailable here — run on device")
        }

        func makeItem(id: String, marker: String) -> CSSearchableItem {
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = "Spike C \(marker)"
            attrs.contentDescription = "Sentinel content \(marker) for DEC-002 visibility testing."
            attrs.textContent = attrs.contentDescription
            let item = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: Self.domain, attributeSet: attrs)
            item.expirationDate = .distantFuture
            return item
        }

        // Clean both indexes, then donate one sentinel to each.
        let namedIndex = CSSearchableIndex(name: Self.namedIndexName)
        let defaultIndex = CSSearchableIndex.default()
        try await namedIndex.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
        try await defaultIndex.deleteSearchableItems(withDomainIdentifiers: [Self.domain])

        try await namedIndex.indexSearchableItems([makeItem(id: "spike-c-named", marker: "quokka-sentinel")])
        try await defaultIndex.indexSearchableItems([makeItem(id: "spike-c-default", marker: "wombat-sentinel")])

        // Give indexing a moment; poll the default-index control first.
        var controlFound = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if try await query("wombat-sentinel").contains("spike-c-default") { controlFound = true; break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        XCTAssertTrue(controlFound, "default-index control never became queryable — environment problem, not a verdict")

        // THE automatable question: does an in-app query (which has no
        // index-selection parameter, mirroring SpotlightSearchTool's
        // sources) return items donated to a NAMED index?
        let namedHits = try await query("quokka-sentinel")
        let namedRetrievable = namedHits.contains("spike-c-named")

        var report = "\n===== SPIKE C (automatable half) =====\n"
        report += "default-index control retrievable in-app: \(controlFound)\n"
        report += "NAMED-index item retrievable in-app:       \(namedRetrievable)\n"
        report += namedRetrievable
            ? "→ in-app retrieval is index-agnostic here; if the device check shows named items hidden from system UI, Branch A is viable.\n"
            : "→ named-index items are NOT reachable by index-blind queries; if SpotlightSearchTool behaves the same on device, hiding and retrieval are coupled → Branch B (REQ-IDX-007 fallback).\n"
        report += "Now do the MANUAL device steps in this file's header and record the verdict in spec 013 R1.\n"
        report += "======================================\n"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "SpikeC-report"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func query(_ text: String, limit: Int = 5) async throws -> [String] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]
        context.maxResultCount = limit
        context.enableRankedResults = true
        let q = CSUserQuery(userQueryString: text, userQueryContext: context)
        var ids: [String] = []
        do {
            for try await response in q.responses {
                if case .item(let item) = response {
                    ids.append(item.item.uniqueIdentifier)
                    if ids.count >= limit { break }
                }
            }
        } catch {
            if ids.isEmpty { throw error }
        }
        return ids
    }
}
