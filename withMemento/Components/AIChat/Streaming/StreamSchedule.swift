//
//  StreamSchedule.swift
//  withMemento
//
//  When each character of a streaming assistant reply appears on screen.
//  Lives on the message (`ChatMessage.schedule`), not in the view, so a
//  recycled or re-rendered row resumes mid-stream and a finished reply never
//  replays. `StreamRenderer` reads it; only the view model writes it.
//

import Foundation

/// Deterministic per-message randomness for the reveal rhythm. Seeded from
/// the message ID, never the text (which changes while it streams) and never
/// `hashValue` (randomized per launch).
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// FNV-1a over the UUID's 16 bytes.
    init(messageID: UUID) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: messageID.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
        }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
        return mixed ^ (mixed >> 31)
    }
}

/// Incremental, append-only arrival times for a reply's displayed characters,
/// in seconds since `start`.
///
/// Text is revealed in "tokens" of 2–5 characters that never cross a word
/// boundary, on a token-like rhythm. Arrivals already scheduled never move
/// unless the characters themselves change (`reconcile(to:receivedAt:)`).
struct StreamSchedule: Sendable {
    /// How long one glyph takes to fade up and settle.
    static let fade = 0.55
    /// Reduce Motion: a plain opacity fade per token.
    static let reduceMotionFade = 0.15

    static let intraTokenSpacing = 0.012
    static let gapRange = 0.028...0.070
    static let burstGap = 0.006
    static let burstProbability = 0.14
    static let commaPause = 0.050
    static let stopPause = 0.110
    /// Backlog (seconds the reveal trails what has been received) above
    /// which spacing starts to compress so the reveal catches up.
    static let backlogThreshold = 1.5
    /// Backlog at which compression reaches `minBacklogFactor`. A 300-
    /// character burst reveals in ~3.4s with these values; the floor factor,
    /// not the ramp, bounds it (~6ms a character at full compression).
    static let backlogFloorLag = 2.0
    static let minBacklogFactor = 0.25

    let start: Date
    private(set) var arrivals: [Double] = []
    /// Arrival of the first character of each character's token. Drives the
    /// Reduce Motion fade, which shows whole tokens at once.
    private(set) var tokenStarts: [Double] = []
    private(set) var isComplete = false
    /// The displayed text the arrivals describe, kept so `reconcile` can find
    /// what changed.
    private(set) var text: [Character] = []

    private var rng: SplitMix64
    /// Cursor: when the next character would arrive.
    private var cursor: Double = 0
    /// Characters left in the token being scheduled. A delta that ends
    /// mid-token carries the rest of the token into the next append.
    private var tokenRemaining = 0
    private var currentTokenStart: Double = 0
    private var tokenLastNonSpace: Character?

    init(messageID: UUID, start: Date = .now) {
        self.start = start
        self.rng = SplitMix64(messageID: messageID)
    }

    /// A reply that is already fully on screen: loaded from history or
    /// persistence. Every character has arrived; nothing ever animates.
    static func settled(text: String, messageID: UUID = UUID()) -> StreamSchedule {
        var schedule = StreamSchedule(messageID: messageID, start: .distantPast)
        schedule.text = Array(text)
        schedule.arrivals = Array(repeating: -.infinity, count: schedule.text.count)
        schedule.tokenStarts = schedule.arrivals
        schedule.isComplete = true
        return schedule
    }

    // MARK: - Writing

    /// Schedules only the characters of `delta`. Never changes arrivals that
    /// are already scheduled.
    mutating func append(_ delta: String, receivedAt: Date = .now) {
        guard !delta.isEmpty else { return }
        let received = receivedAt.timeIntervalSince(start)
        arrivals.reserveCapacity(arrivals.count + delta.count)
        tokenStarts.reserveCapacity(tokenStarts.count + delta.count)

        for character in delta {
            // Network floor: nothing appears before it was received.
            cursor = max(cursor, received)
            if tokenRemaining == 0 {
                tokenRemaining = Int.random(in: 2...5, using: &rng)
                currentTokenStart = cursor
                tokenLastNonSpace = nil
            }

            arrivals.append(cursor)
            tokenStarts.append(currentTokenStart)
            text.append(character)
            if !character.isWhitespace { tokenLastNonSpace = character }
            tokenRemaining -= 1

            let factor = backlogFactor(received: received)
            if character.isWhitespace || tokenRemaining == 0 {
                // Token ends right after a space, or at its length.
                tokenRemaining = 0
                cursor += tokenGap(after: tokenLastNonSpace) * factor
            } else {
                cursor += Self.intraTokenSpacing * factor
            }
        }
    }

    /// Brings the schedule in line with the full displayed text as it now
    /// stands. A pure extension takes the `append` path. When earlier text
    /// changed (reference markers stripped, the final re-render), arrivals
    /// for the unchanged prefix are kept and only the changed tail is
    /// rescheduled from the receive time.
    mutating func reconcile(to newText: String, receivedAt: Date = .now) {
        let new = Array(newText)
        var common = 0
        let limit = min(text.count, new.count)
        while common < limit, text[common] == new[common] { common += 1 }

        if common < text.count {
            let drop = text.count - common
            text.removeLast(drop)
            arrivals.removeLast(drop)
            tokenStarts.removeLast(drop)
            cursor = arrivals.last.map { $0 + Self.intraTokenSpacing } ?? 0
            tokenRemaining = 0
        }
        if common < new.count {
            append(String(new[common...]), receivedAt: receivedAt)
        }
    }

    /// The stream ended (success, error, or cancel). Whatever was received
    /// settles normally.
    mutating func finish() {
        isComplete = true
    }

    // MARK: - Reading

    /// When character `index` appears, or `.infinity` if it is not yet
    /// scheduled (so it isn't drawn).
    func arrival(at index: Int) -> Double {
        arrivals.indices.contains(index) ? arrivals[index] : .infinity
    }

    func tokenStart(at index: Int) -> Double {
        tokenStarts.indices.contains(index) ? tokenStarts[index] : .infinity
    }

    var count: Int { arrivals.count }

    /// When the last glyph finishes settling, in seconds since `start`.
    var duration: Double {
        guard let last = arrivals.last else { return 0 }
        return last + Self.fade
    }

    /// The moment the reveal is fully settled.
    var settleDate: Date {
        duration.isFinite ? start.addingTimeInterval(duration) : start
    }

    func isSettled(at date: Date) -> Bool {
        isComplete && date.timeIntervalSince(start) >= duration
    }

    // MARK: - Rhythm

    private mutating func tokenGap(after last: Character?) -> Double {
        var gap = Double.random(in: 0...1, using: &rng) < Self.burstProbability
            ? Self.burstGap
            : Double.random(in: Self.gapRange, using: &rng)
        switch last {
        case ",": gap += Self.commaPause
        case ".", ":", ";", "?", "!": gap += Self.stopPause
        default: break
        }
        return gap
    }

    /// 1 while the reveal keeps up; ramps toward `minBacklogFactor` as it
    /// trails what has been received, so it speeds up instead of jumping.
    private func backlogFactor(received: Double) -> Double {
        let lag = cursor - received
        guard lag > Self.backlogThreshold else { return 1 }
        let progress = min(1, (lag - Self.backlogThreshold) / (Self.backlogFloorLag - Self.backlogThreshold))
        return 1 - (1 - Self.minBacklogFactor) * progress
    }
}

extension StreamSchedule: Hashable {
    /// Cheap on purpose: `ChatMessage` is `Hashable` and diffed on every
    /// publish, and arrivals only ever grow or are rewritten together with
    /// the text. Count, last arrival, completion and start identify a state.
    static func == (lhs: StreamSchedule, rhs: StreamSchedule) -> Bool {
        lhs.start == rhs.start
            && lhs.arrivals.count == rhs.arrivals.count
            && lhs.arrivals.last == rhs.arrivals.last
            && lhs.isComplete == rhs.isComplete
            && lhs.text.last == rhs.text.last
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(arrivals.count)
        hasher.combine(isComplete)
    }
}
