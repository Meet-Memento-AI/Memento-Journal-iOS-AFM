import XCTest
@testable import MeetMemento

/// Chat-speed: the one-at-a-time model gate serves the person first.
/// Ask waits for at most the call in flight, never a queue of reflections;
/// prewarm queues instead of being skipped; reflections hold off while
/// chat is hot. No FoundationModels — this is the scheduling policy.
final class ModelRuntimeGateTests: XCTestCase {

    /// Open/close latch so a test can hold the gate for as long as it needs.
    private actor Latch {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func append(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }

    func test_release_servesInteractiveThenSpeculativeThenBackground() async {
        let gate = ModelRuntimeGate(interactiveHoldoff: .zero)
        let holding = Latch()
        let entered = Latch()
        let order = Recorder()

        let holder = Task {
            await gate.withLock(.background) {
                order.append("holder")
                await entered.open()
                await holding.wait()
            }
        }
        await entered.wait()

        // Queue in the *wrong* order: background first, then speculative,
        // then the person. Each is given a moment to reach the gate.
        let background = Task {
            await gate.withLock(.background) { order.append("background") }
        }
        await settle()
        let speculative = Task {
            await gate.withLock(.speculative) { order.append("speculative") }
        }
        await settle()
        let interactive = Task {
            await gate.withLock(.interactive) { order.append("interactive") }
        }
        await settle()

        await holding.open()
        _ = await (holder.value, background.value, speculative.value, interactive.value)

        XCTAssertEqual(order.all, ["holder", "interactive", "speculative", "background"])
    }

    func test_background_holdsOffAfterInteractiveTouch() async {
        let gate = ModelRuntimeGate(interactiveHoldoff: .milliseconds(250))
        XCTAssertNil(gate.backgroundHoldoffRemaining(), "nothing interactive yet")

        gate.noteInteractiveActivity()
        XCTAssertNotNil(gate.backgroundHoldoffRemaining())

        let clock = ContinuousClock()
        let start = clock.now
        await gate.withLock(.background) {}
        let waited = clock.now - start
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(200), "background started inside the hold-off")
        XCTAssertNil(gate.backgroundHoldoffRemaining())
    }

    func test_speculativeAndInteractive_ignoreHoldoff() async {
        let gate = ModelRuntimeGate(interactiveHoldoff: .seconds(30))
        gate.noteInteractiveActivity()

        let clock = ContinuousClock()
        let start = clock.now
        await gate.withLock(.speculative) {}
        await gate.withLock(.interactive) {}
        XCTAssertLessThan(clock.now - start, .seconds(1))
    }

    func test_interactiveAcquire_marksRuntimeHot() async {
        let gate = ModelRuntimeGate(interactiveHoldoff: .seconds(30))
        XCTAssertNil(gate.backgroundHoldoffRemaining())
        await gate.withLock(.interactive) {}
        XCTAssertNotNil(gate.backgroundHoldoffRemaining(), "an Ask should push reflections out")
    }

    func test_tryWithLock_skipsWhileBusy_andRunsWhenIdle() async {
        let gate = ModelRuntimeGate(interactiveHoldoff: .zero)
        let holding = Latch()
        let entered = Latch()

        let holder = Task {
            await gate.withLock {
                await entered.open()
                await holding.wait()
            }
        }
        await entered.wait()

        let skipped: Int? = await gate.tryWithLock { 1 }
        XCTAssertNil(skipped)

        await holding.open()
        await holder.value

        let ran: Int? = await gate.tryWithLock { 2 }
        XCTAssertEqual(ran, 2)
    }

    func test_withLock_rethrows_andReleases() async {
        struct Boom: Error {}
        let gate = ModelRuntimeGate(interactiveHoldoff: .zero)
        do {
            try await gate.withLock { throw Boom() }
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        let ran: Int? = await gate.tryWithLock { 3 }
        XCTAssertEqual(ran, 3, "gate must be released after a throwing body")
    }

    func test_defaultHoldoff_isShortEnoughForJournalCards() {
        // The weekly "writing now…" card is foreground (045 R4); a hold-off
        // longer than this would leave it visibly stalled after a chat.
        XCTAssertLessThanOrEqual(ModelRuntimeGate.defaultInteractiveHoldoff, .seconds(20))
        XCTAssertGreaterThanOrEqual(ModelRuntimeGate.defaultInteractiveHoldoff, .seconds(5))
    }
}
