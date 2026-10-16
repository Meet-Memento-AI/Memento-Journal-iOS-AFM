//
//  StreamLayout.swift
//  withMemento
//
//  The character index space a `StreamSchedule` covers for one assistant
//  reply, shared by the view model (which schedules it) and the view (which
//  hands each `Text` its slice). Both must count the same characters, or the
//  reveal drifts off the glyphs.
//

import Foundation

/// Displayed characters of a reply, in schedule order:
///
///     body blocks (joined by "\n") | "\n" heading1 | "\n" heading2
///
/// Body comes first because `AskAnswer.body` leads guided-generation decode
/// order: headings that arrive later then extend the schedule instead of
/// rewriting the body's indices. Markdown syntax (`### `, `- `, `**`) is not
/// displayed and so not counted; list markers take their row's first index.
/// Separators take an index each but are never drawn, which gives paragraph
/// breaks a natural beat.
struct StreamLayout: Equatable {
    let blocks: [MarkdownBlock]
    /// Index of each block's first character.
    let blockStarts: [Int]
    let heading1Start: Int
    let heading2Start: Int
    let text: String

    init(body: String, heading1: String?, heading2: String?) {
        self.init(blocks: RichTextParser.parseBlocks(body), heading1: heading1, heading2: heading2)
    }

    init(blocks: [MarkdownBlock], heading1: String?, heading2: String?) {
        self.blocks = blocks
        var text = ""
        var starts: [Int] = []
        starts.reserveCapacity(blocks.count)
        var offset = 0
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                text.append("\n")
                offset += 1
            }
            starts.append(offset)
            let shown = block.displayedText
            text.append(shown)
            offset += shown.count
        }
        blockStarts = starts

        func appendHeading(_ heading: String?) -> Int {
            guard let heading, !heading.isEmpty else { return offset }
            if offset > 0 {
                text.append("\n")
                offset += 1
            }
            let start = offset
            text.append(heading)
            offset += heading.count
            return start
        }
        heading1Start = appendHeading(heading1)
        heading2Start = appendHeading(heading2)
        self.text = text
    }

    /// The `[start, end)` slice of block `index`.
    func range(ofBlock index: Int) -> Range<Int> {
        let start = blockStarts[index]
        return start..<(start + blocks[index].displayedText.count)
    }
}

extension MarkdownBlock {
    /// The characters this block draws, excluding list markers, which sit in
    /// their own `Text` and share the row's first index.
    var displayedText: String {
        switch self {
        case .heading(_, let runs), .paragraph(let runs),
             .unorderedItem(_, let runs), .orderedItem(_, _, let runs):
            return runs.map(\.text).joined()
        case .blank:
            return ""
        }
    }
}
