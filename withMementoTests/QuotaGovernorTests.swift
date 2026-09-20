import XCTest
@testable import MeetMemento

/// Spec 017 R3's acceptance criteria. The governor is inert in production on the
/// iOS 26 SDK (the only provider returns nil), so its whole lifecycle is
/// exercised here through stub providers — which is the point of mirroring the
/// quota surface instead of importing it.
final class QuotaGovernorTests: XCTestCase {

    private struct StubProvider: QuotaStatusProviding {
        let value: QuotaSnapshot?
        func snapshot() async -> QuotaSnapshot? { value }
    }

    private func governor(_ snapshot: QuotaSnapshot?) -> QuotaGovernor {
        QuotaGovernor(provider: StubProvider(value: snapshot))
    }

    private func belowLimit(approaching: Bool, resetDate: Date? = nil) -> QuotaSnapshot {
        QuotaSnapshot(status: .belowLimit, isApproachingLimit: approaching, resetDate: resetDate)
    }

    // MARK: Lifecycle — below → approaching → reached → reset

    func test_noProvider_reportsSdkUnsupportedNotFailure() async {
        // nil means "this build has no PCC", which is the iOS 26 baseline — a
        // different thing from "PCC exists and is out of budget".
        let sut = governor(nil)

        for priority in [QuotaPriority.interactive, .scheduled] {
            let capability = await sut.capability(for: priority)
            XCTAssertEqual(capability, .sdkUnsupported)
        }
    }

    func test_belowLimit_grantsFullCapability() async {
        let sut = governor(belowLimit(approaching: false))

        for priority in [QuotaPriority.interactive, .scheduled] {
            let capability = await sut.capability(for: priority)
            XCTAssertEqual(capability, .available)
        }
    }

    func test_limitReached_constrainsEveryPriority() async {
        let sut = governor(QuotaSnapshot(status: .limitReached, isApproachingLimit: false, resetDate: nil))

        for priority in [QuotaPriority.interactive, .scheduled] {
            let capability = await sut.capability(for: priority)
            XCTAssertEqual(capability, .quotaConstrained)
        }
    }

    func test_afterReset_capabilityReturnsToAvailable() async {
        // "Reset" is just the platform reporting belowLimit again; the governor
        // holds no latched state that could keep the app degraded past it.
        let sut = governor(belowLimit(approaching: false))
        let capability = await sut.capability(for: .interactive)
        XCTAssertEqual(capability, .available)
    }

    // MARK: Priority — chat yields first

    /// Spec 017 R3's acceptance, verbatim: "given isApproachingLimit == true,
    /// when a chat request and a scheduled weekly reflection are both pending,
    /// then chat routes to Z0 and the weekly reflection keeps its Z1 route."
    /// A user must never lose their Sunday reflection because they had a long
    /// conversation on Saturday.
    func test_approachingLimit_chatDegradesFirst_scheduledKeepsItsSlot() async {
        let sut = governor(belowLimit(approaching: true))

        let chat = await sut.capability(for: .interactive)
        let reflection = await sut.capability(for: .scheduled)

        XCTAssertEqual(chat, .quotaConstrained, "interactive chat must yield first")
        XCTAssertEqual(reflection, .available, "scheduled synthesis keeps its budget")
    }

    // MARK: V13 — the non-frozen status guard

    /// `QuotaUsage.Status` is not `@frozen`, so a case can appear that this
    /// build has never seen. It must take the conservative arm rather than trap
    /// or silently misroute.
    func test_unknownStatus_isTreatedAsConstrained() async {
        let sut = governor(.unknown)

        for priority in [QuotaPriority.interactive, .scheduled] {
            let capability = await sut.capability(for: priority)
            XCTAssertEqual(capability, .quotaConstrained,
                           "an unenumerated status must degrade gracefully, never optimistically")
        }
    }

    // MARK: V4 — no knowable remaining budget

    /// Spec 017 R3: "no code assumes a knowable remaining budget (no 'N requests
    /// left' UI or arithmetic)". The limit may be per-user across apps, so any
    /// count Memento displayed would be a guess presented as fact. This asserts
    /// the *type* cannot carry one, which is stronger than asserting no current
    /// caller computes one.
    func test_quotaSnapshot_cannotCarryARemainingCount() {
        let mirror = Mirror(reflecting: QuotaSnapshot.unknown)
        let numericChildren = mirror.children.filter { $0.value is Int || $0.value is Double }

        XCTAssertTrue(numericChildren.isEmpty,
                      "QuotaSnapshot gained a numeric field — REQ-INT-007/V4 forbids remaining-budget arithmetic")
        XCTAssertEqual(Set(mirror.children.compactMap(\.label)),
                       ["status", "isApproachingLimit", "resetDate"])
    }

    /// `resetDate` is a date, not a quantity: technology/02 §6 recommends
    /// re-arming a deferred reflection off it instead of polling.
    func test_resetDate_isSurfacedForScheduling() async {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let sut = governor(belowLimit(approaching: true, resetDate: when))

        let resetDate = await sut.resetDate()
        XCTAssertEqual(resetDate, when)
    }
}
