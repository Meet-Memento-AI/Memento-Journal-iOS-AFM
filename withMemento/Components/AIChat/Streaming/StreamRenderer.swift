//
//  StreamRenderer.swift
//  withMemento
//
//  Draws a `Text` with each glyph fading up out of a soft blur and settling
//  a few points, at the time `StreamSchedule` gives it. Pure function of
//  `elapsed`: `StreamingText`'s `TimelineView` advances it.
//

import SwiftUI

struct StreamRenderer: TextRenderer {
    /// Seconds since `schedule.start`.
    var elapsed: Double
    var schedule: StreamSchedule
    /// Schedule index of this `Text`'s first character.
    var range: Range<Int>
    var reduceMotion: Bool

    static let maxBlur: CGFloat = 5
    static let maxRise: CGFloat = 4

    /// Room for the blur and the rise to draw outside the text's bounds.
    var displayPadding: EdgeInsets {
        let pad = Self.maxBlur + Self.maxRise
        return EdgeInsets(top: pad, leading: pad, bottom: pad, trailing: pad)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var index = range.lowerBound
        for line in layout {
            for run in line {
                let first = index
                let last = index + run.count - 1
                index += run.count

                // Not started yet: arrivals never decrease within a slice.
                if elapsed <= start(of: first) { continue }
                // Fully settled: draw the run whole, skip per-glyph work.
                if elapsed >= start(of: last) + fade { ctx.draw(run); continue }

                for (offset, glyph) in run.enumerated() {
                    let p = (elapsed - start(of: first + offset)) / fade
                    if p <= 0 { continue }
                    if p >= 1 { ctx.draw(glyph); continue }

                    var glyphContext = ctx
                    if reduceMotion {
                        glyphContext.opacity = p
                    } else {
                        let e = 1 - pow(1 - p, 3)
                        glyphContext.opacity = e
                        glyphContext.addFilter(.blur(radius: (1 - e) * Self.maxBlur))
                        glyphContext.translateBy(x: 0, y: (1 - e) * Self.maxRise)
                    }
                    glyphContext.draw(glyph)
                }
            }
        }
    }

    private var fade: Double {
        reduceMotion ? StreamSchedule.reduceMotionFade : StreamSchedule.fade
    }

    /// When glyph `index` begins to appear. Glyphs and Characters are not
    /// always 1:1 (ligatures, some emoji), so the index is clamped into this
    /// `Text`'s slice: a mismatch fades a glyph slightly early or late rather
    /// than hiding it or crashing.
    private func start(of index: Int) -> Double {
        guard !range.isEmpty else { return -.infinity }
        let clamped = min(max(index, range.lowerBound), range.upperBound - 1)
        return reduceMotion ? schedule.tokenStart(at: clamped) : schedule.arrival(at: clamped)
    }
}
