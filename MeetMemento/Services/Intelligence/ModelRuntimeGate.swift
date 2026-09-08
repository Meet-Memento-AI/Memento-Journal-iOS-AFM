//
//  ModelRuntimeGate.swift
//  MeetMemento
//
//  One-at-a-time gate for `SystemLanguageModel` work, with the person first.
//
//  Concurrent `respond` / `streamResponse` / `prewarm` / `tokenCount` —
//  weekly reflection overlapping a chat send, speculative prewarm overlapping
//  live generation — EXC_BAD_ACCESS inside the AFM runtime, so every model
//  call goes through here. Serializing alone was not enough for chat speed:
//  a FIFO gate made a send wait behind whatever entry-reflection backfill
//  happened to be queued, and skipped the speculative prewarm outright when
//  the gate was busy. This gate orders waiters by who is waiting on them:
//
//  - `.interactive` — a person is watching (Ask, onboarding estimate,
//    save-as-entry summary). Head of the line, and marks the runtime "hot".
//  - `.speculative` — prewarm for the next turn. Behind interactive, ahead
//    of background, never skipped.
//  - `.background` — entry / weekly reflection, profile refresh. Back of
//    the line, and holds off entirely for `interactiveHoldoff` after the
//    last interactive touch so a reflection does not start the moment the
//    person is likely to send.
//
//  Nothing is preempted: a running call always finishes. Cancelling an
//  in-flight AFM call and starting another on the same runtime is exactly
//  the overlap this gate exists to prevent, and cannot be verified off
//  device. Ask therefore waits for at most one background call, never a
//  queue of them.
//
//  Deliberately does NOT import FoundationModels (single-importer gate,
//  scripts/ci/check_single_intelligence_importer.sh); it is a lock.
//

import Foundation

final class ModelRuntimeGate: @unchecked Sendable {
    enum Priority: Sendable {
        case interactive
        case speculative
        case background
    }

    static let shared = ModelRuntimeGate()

    /// Background hold-off after the last interactive touch. Long enough to
    /// cover read-reply-send in chat; short enough that the weekly card
    /// still lands while the person is on Journal.
    static let defaultInteractiveHoldoff: Duration = .seconds(15)

    private let lock = NSLock()
    private let clock = ContinuousClock()
    private let holdoff: Duration
    private var busy = false
    private var interactiveWaiters: [CheckedContinuation<Void, Never>] = []
    private var speculativeWaiters: [CheckedContinuation<Void, Never>] = []
    private var backgroundWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastInteractiveTouch: ContinuousClock.Instant?

    init(interactiveHoldoff: Duration = ModelRuntimeGate.defaultInteractiveHoldoff) {
        holdoff = interactiveHoldoff
    }

    /// The runtime is about to serve a person (chat opened, turn sent).
    /// Background work holds off for `interactiveHoldoff` from here.
    func noteInteractiveActivity() {
        lock.lock()
        lastInteractiveTouch = clock.now
        lock.unlock()
    }

    /// Remaining hold-off for background work; nil when it may start now.
    func backgroundHoldoffRemaining() -> Duration? {
        lock.lock()
        defer { lock.unlock() }
        guard let last = lastInteractiveTouch else { return nil }
        let elapsed = clock.now - last
        return elapsed < holdoff ? holdoff - elapsed : nil
    }

    func withLock<T>(
        _ priority: Priority = .interactive,
        _ body: () async throws -> T
    ) async rethrows -> T {
        await acquire(priority)
        defer { release() }
        return try await body()
    }

    /// Skip if another model call already holds the gate (token count).
    func tryWithLock<T>(_ body: () async throws -> T) async -> T? {
        guard tryAcquire() else { return nil }
        defer { release() }
        return try? await body()
    }

    private func acquire(_ priority: Priority) async {
        switch priority {
        case .interactive:
            noteInteractiveActivity()
        case .speculative:
            break
        case .background:
            await waitOutInteractiveHoldoff()
        }
        await withCheckedContinuation { continuation in
            lock.lock()
            if busy {
                switch priority {
                case .interactive: interactiveWaiters.append(continuation)
                case .speculative: speculativeWaiters.append(continuation)
                case .background: backgroundWaiters.append(continuation)
                }
                lock.unlock()
            } else {
                busy = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    /// A send that lands during the hold-off pushes it out again, so this
    /// loops until a full window has passed quietly. Cancellation falls
    /// through: the caller's own work observes it.
    private func waitOutInteractiveHoldoff() async {
        while let remaining = backgroundHoldoffRemaining() {
            if Task.isCancelled { return }
            do { try await Task.sleep(for: remaining) } catch { return }
        }
    }

    private func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }

    private func release() {
        lock.lock()
        let next: CheckedContinuation<Void, Never>?
        if !interactiveWaiters.isEmpty {
            next = interactiveWaiters.removeFirst()
        } else if !speculativeWaiters.isEmpty {
            next = speculativeWaiters.removeFirst()
        } else if !backgroundWaiters.isEmpty {
            next = backgroundWaiters.removeFirst()
        } else {
            next = nil
            busy = false
        }
        lock.unlock()
        next?.resume()
    }
}
