import XCTest
@testable import MeetMemento

/// A single refusal must stay a designed empty state; a run of them must not.
/// Covers MEM-209, where every generation refused on an iOS 26.0 simulator and
/// the chat rendered each one as ordinary authored copy — no alert, no retry,
/// no way for anyone to tell the model was simply broken.
final class RefusalOutageTrackerTests: XCTestCase {

    func test_singleRefusal_isNotAnOutage() {
        var tracker = RefusalOutageTracker()
        XCTAssertFalse(tracker.recordRefusal(),
                       "one refusal is a content decision, not an outage")
        XCTAssertEqual(tracker.consecutiveRefusals, 1)
    }

    func test_refusalsBelowThreshold_areNotAnOutage() {
        var tracker = RefusalOutageTracker(threshold: 3)
        XCTAssertFalse(tracker.recordRefusal())
        XCTAssertFalse(tracker.recordRefusal())
        XCTAssertEqual(tracker.consecutiveRefusals, 2)
    }

    func test_thirdConsecutiveRefusal_trips() {
        var tracker = RefusalOutageTracker(threshold: 3)
        _ = tracker.recordRefusal()
        _ = tracker.recordRefusal()
        XCTAssertTrue(tracker.recordRefusal(),
                      "three in a row with nothing succeeding is an outage")
    }

    /// The point of the counter: one success anywhere in the run clears it, so
    /// an occasional genuine refusal never accumulates across a healthy session
    /// into a false outage.
    func test_successResetsTheRun() {
        var tracker = RefusalOutageTracker(threshold: 3)
        _ = tracker.recordRefusal()
        _ = tracker.recordRefusal()
        tracker.recordSuccess()
        XCTAssertEqual(tracker.consecutiveRefusals, 0)
        XCTAssertFalse(tracker.recordRefusal(),
                       "the run restarts after a success — this is refusal 1, not 3")
        XCTAssertFalse(tracker.recordRefusal())
    }

    /// Interleaving is the realistic healthy case: refusals happen, they just
    /// never happen three deep without a reply landing in between.
    func test_alternatingRefusalAndSuccess_neverTrips() {
        var tracker = RefusalOutageTracker(threshold: 3)
        for _ in 0..<20 {
            XCTAssertFalse(tracker.recordRefusal())
            tracker.recordSuccess()
        }
    }

    /// Every refusal in an ongoing outage keeps reporting `true`, not just the
    /// one that crossed the line — otherwise turn 4 would silently fall back to
    /// the empty state the escalation exists to replace.
    func test_staysTrippedWhileTheOutageContinues() {
        var tracker = RefusalOutageTracker(threshold: 3)
        _ = tracker.recordRefusal()
        _ = tracker.recordRefusal()
        XCTAssertTrue(tracker.recordRefusal())
        XCTAssertTrue(tracker.recordRefusal())
        XCTAssertTrue(tracker.recordRefusal())
        XCTAssertEqual(tracker.consecutiveRefusals, 5)
    }

    func test_defaultThresholdIsThree() {
        XCTAssertEqual(RefusalOutageTracker.defaultThreshold, 3)
        var tracker = RefusalOutageTracker()
        _ = tracker.recordRefusal()
        _ = tracker.recordRefusal()
        XCTAssertTrue(tracker.recordRefusal())
    }
}
