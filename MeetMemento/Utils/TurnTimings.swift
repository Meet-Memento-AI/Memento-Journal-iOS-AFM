//
//  TurnTimings.swift
//  MeetMemento
//
//  Pure per-turn stage-duration bookkeeping (spec 029 R1). Callers pass
//  ContinuousClock instants; this type never reads a clock itself, so tests
//  drive it with fabricated instants. Feeds the DEBUG one-line turn summary
//  and nothing else — signposts carry the same stages to Instruments.
//

import Foundation

struct TurnTimings: Sendable {
    enum Stage: String, CaseIterable, Sendable {
        case micStop = "stop"
        case prepSafety = "safety"
        case prepClassify = "classify"
        case prepRetrieve = "retrieve"
        case sessionCreate = "session"
        case modelFirstToken = "ttft"
        case modelStream = "stream"
        case firstSentence = "1st-sentence"
        case ttsActivate = "tts-activate"
        case ttsFirstAudio = "1st-audio"
        case listenRearm = "rearm"
        case persist = "persist"
    }

    private(set) var stages: [Stage: Duration] = [:]
    /// Marks (single instants relative to the turn start), e.g. when first
    /// audio actually began relative to send.
    private(set) var marks: [Stage: Duration] = [:]

    private var openStarts: [Stage: ContinuousClock.Instant] = [:]
    /// The turn's origin, for marks.
    private var origin: ContinuousClock.Instant?

    mutating func begin(turnAt instant: ContinuousClock.Instant) {
        origin = instant
    }

    mutating func start(_ stage: Stage, at instant: ContinuousClock.Instant) {
        openStarts[stage] = instant
    }

    mutating func end(_ stage: Stage, at instant: ContinuousClock.Instant) {
        guard let start = openStarts.removeValue(forKey: stage) else { return }
        stages[stage] = instant - start
    }

    /// Records a single instant as an offset from the turn origin.
    mutating func mark(_ stage: Stage, at instant: ContinuousClock.Instant) {
        guard let origin else { return }
        marks[stage] = instant - origin
    }

    func duration(of stage: Stage) -> Duration? { stages[stage] }

    /// Sum of a set of recorded stage durations (unrecorded stages count 0).
    func total(of included: [Stage]) -> Duration {
        included.compactMap { stages[$0] }.reduce(.zero, +)
    }

    /// `stop 180ms | safety 12ms | ttft 640ms | 1st-audio 1.9s`
    /// Stages appear in canonical order; only recorded values print.
    func summaryLine() -> String {
        var parts: [String] = []
        for stage in Stage.allCases {
            if let d = stages[stage] {
                parts.append("\(stage.rawValue) \(Self.format(d))")
            } else if let m = marks[stage] {
                parts.append("\(stage.rawValue)@\(Self.format(m))")
            }
        }
        return parts.joined(separator: " | ")
    }

    /// 950ms below 1s; 1.9s at or above (one decimal).
    static func format(_ duration: Duration) -> String {
        let ms = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        if ms < 1000 { return "\(Int(ms.rounded()))ms" }
        return String(format: "%.1fs", ms / 1000)
    }
}

/// Process-wide current-turn bookkeeping. Signposts still go to Instruments;
/// this is the DEBUG one-line summary (spec 029 R1) filled from prep, stream,
/// persist, and the speech loop. Lock-protected so the intelligence path
/// (off the main actor) and the UI path can both record.
final class LiveTurnClock: @unchecked Sendable {
    static let shared = LiveTurnClock()

    private let lock = NSLock()
    private let clock = ContinuousClock()
    private var timings = TurnTimings()
    private var turnOpen = false
    /// Narration keeps the turn open past generation so first-audio / re-arm
    /// still land on the same summary line.
    private var heldOpen = false

    private init() {}

    /// Starts a turn. Idempotent while a turn is open so narration can
    /// begin at mic-stop and the send path's later call is a no-op.
    /// `heldOpen` is for the speech loop: generation-end must not close it.
    func beginTurn(heldOpen: Bool = false) {
        lock.lock()
        guard !turnOpen else { lock.unlock(); return }
        turnOpen = true
        self.heldOpen = heldOpen
        timings = TurnTimings()
        timings.begin(turnAt: clock.now)
        lock.unlock()
    }

    func start(_ stage: TurnTimings.Stage) {
        lock.lock()
        timings.start(stage, at: clock.now)
        lock.unlock()
    }

    func end(_ stage: TurnTimings.Stage) {
        lock.lock()
        timings.end(stage, at: clock.now)
        lock.unlock()
    }

    func mark(_ stage: TurnTimings.Stage) {
        lock.lock()
        timings.mark(stage, at: clock.now)
        lock.unlock()
    }

    /// Emits the content-free one-line summary. Call from the send-path defer
    /// so a cancelled or failed turn still logs whatever stages landed.
    func finishAndLog() {
        lock.lock()
        let line = timings.summaryLine()
        if heldOpen {
            lock.unlock()
            if !line.isEmpty {
                PerfSignposts.perfLog.info("turn \(line, privacy: .public)")
            }
            return
        }
        turnOpen = false
        lock.unlock()
        guard !line.isEmpty else { return }
        PerfSignposts.perfLog.info("turn \(line, privacy: .public)")
    }

    /// Closes a held narration turn after re-arm (or a failed send that
    /// skipped speech).
    /// Test seam — never call from production.
    func resetForTesting() {
        lock.lock()
        timings = TurnTimings()
        turnOpen = false
        heldOpen = false
        lock.unlock()
    }

    func releaseAndLog() {
        lock.lock()
        heldOpen = false
        let line = timings.summaryLine()
        turnOpen = false
        lock.unlock()
        guard !line.isEmpty else { return }
        PerfSignposts.perfLog.info("turn \(line, privacy: .public)")
    }
}
