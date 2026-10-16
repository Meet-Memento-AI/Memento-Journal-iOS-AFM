//
//  StreamingText.swift
//  withMemento
//
//  One `Text` of a streaming assistant reply, revealed glyph by glyph by
//  `StreamRenderer`. Callers apply font, color, line spacing and width
//  outside, as they would to a plain `Text`, so it drops in wherever one was.
//

import SwiftUI

struct StreamingText: View {
    let attributed: AttributedString
    let schedule: StreamSchedule
    /// This text's slice of the schedule's index space (`StreamLayout`).
    let range: Range<Int>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True once every glyph in `range` has settled. Pauses the timeline so a
    /// finished block costs no per-frame redraws.
    @State private var settled = false

    var body: some View {
        TimelineView(.animation(paused: settled)) { context in
            Text(attributed)
                .textRenderer(StreamRenderer(
                    // Settled draws everything whole: a paused timeline's
                    // last frame can land a few ms short of the final fade.
                    elapsed: settled ? .infinity : context.date.timeIntervalSince(schedule.start),
                    schedule: schedule,
                    range: range,
                    reduceMotion: reduceMotion
                ))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(attributed.characters))
        .task(id: settleDate) {
            // Unscheduled characters (the text is still growing) settle at
            // `.distantFuture`: keep the timeline running.
            guard let settleDate else {
                settled = false
                return
            }
            let remaining = settleDate.timeIntervalSinceNow
            if remaining > 0 {
                settled = false
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            settled = true
        }
    }

    /// When the last glyph in `range` finishes, or nil while any character in
    /// it is not yet scheduled. Changes whenever the text, the schedule, or
    /// a rewrite of this slice does, which re-runs the settle check.
    private var settleDate: Date? {
        guard let lastIndex = range.last else { return schedule.start }
        let last = schedule.arrival(at: lastIndex)
        guard last.isFinite else {
            // -infinity: arrived before the stream (settled history).
            return last == -.infinity ? schedule.start : nil
        }
        let fade = reduceMotion ? StreamSchedule.reduceMotionFade : StreamSchedule.fade
        return schedule.start.addingTimeInterval(last + fade)
    }
}
