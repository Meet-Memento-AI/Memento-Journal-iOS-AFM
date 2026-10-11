//
//  MarkdownBodyView.swift
//  withMemento
//
//  Figtree-only renderer for assistant markdown blocks (ask@11). Never uses
//  Typography.h1 / h2 (Lora display). Headings map ###→h3 … ######→h6.
//

import SwiftUI

struct MarkdownBodyView: View {
    let blocks: [MarkdownBlock]
    /// Set while a reply is streaming in (or still settling): each block's
    /// text is revealed glyph by glyph from its slice of the schedule. Nil
    /// renders plain, settled text: history, previews, safety copy.
    var schedule: StreamSchedule?
    /// Index of each block's first character in `schedule`
    /// (`StreamLayout.blockStarts`). Ignored when `schedule` is nil.
    var blockStarts: [Int] = []

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, range: streamRange(at: index))
                    .padding(.top, topPadding(at: index))
                    .accessibilityAddTraits(traits(for: block))
            }
        }
        .limitDynamicTypeSize()
    }

    // MARK: - Layout

    /// Block `index`'s slice of the schedule, or nil to render it settled.
    private func streamRange(at index: Int) -> Range<Int>? {
        guard schedule != nil, blockStarts.indices.contains(index) else { return nil }
        let start = blockStarts[index]
        return start..<(start + blocks[index].displayedText.count)
    }

    private func topPadding(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let prev = blocks[index - 1]
        let current = blocks[index]
        if case .blank = current { return 0 }
        if prev.isListItem && current.isListItem { return Spacing.xxs }
        if case .blank = prev { return Spacing.xs }
        return Spacing.xs
    }

    private func traits(for block: MarkdownBlock) -> AccessibilityTraits {
        switch block {
        case .heading: return .isHeader
        default: return []
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, range: Range<Int>?) -> some View {
        switch block {
        case .blank:
            Color.clear.frame(height: Spacing.xs)
                .accessibilityHidden(true)

        case .heading(let level, let runs):
            styledText(
                runs: runs,
                baseFont: headingFont(level),
                boldFont: headingFont(level),
                lineSpacing: headingLineSpacing(level),
                range: range
            )
            .accessibilityLabel(plain(runs))

        case .paragraph(let runs):
            styledText(
                runs: runs,
                baseFont: type.body1,
                boldFont: type.body1Bold,
                lineSpacing: type.bodyLineSpacing,
                range: range
            )

        case .unorderedItem(let depth, let runs):
            listRow(
                marker: "\u{2022}",
                markerWidth: 14,
                depth: depth,
                runs: runs,
                range: range
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(plain(runs))

        case .orderedItem(let n, let depth, let runs):
            listRow(
                marker: "\(n).",
                markerWidth: 28,
                depth: depth,
                runs: runs,
                range: range
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(n). \(plain(runs))")
        }
    }

    private func listRow(
        marker: String,
        markerWidth: CGFloat,
        depth: Int,
        runs: [MarkdownInline],
        range: Range<Int>?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            markerText(marker, range: range)
                .font(type.body1)
                .foregroundStyle(theme.foreground)
                .frame(width: markerWidth, alignment: .trailing)
                .accessibilityHidden(true)
            styledText(
                runs: runs,
                baseFont: type.body1,
                boldFont: type.body1Bold,
                lineSpacing: type.bodyLineSpacing,
                range: range
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(depth) * Spacing.lg)
    }

    @ViewBuilder
    private func styledText(
        runs: [MarkdownInline],
        baseFont: Font,
        boldFont: Font,
        lineSpacing: CGFloat,
        range: Range<Int>?
    ) -> some View {
        let attr = RichTextParser.attributed(
            runs,
            baseFont: baseFont,
            boldFont: boldFont,
            textColor: theme.foreground
        )
        if let schedule, let range {
            StreamingText(attributed: attr, schedule: schedule, range: range)
                .lineSpacing(lineSpacing)
        } else {
            Text(attr).lineSpacing(lineSpacing)
        }
    }

    /// A list marker fades in with its row's first character.
    @ViewBuilder
    private func markerText(_ marker: String, range: Range<Int>?) -> some View {
        if let schedule, let range {
            let first = range.lowerBound
            StreamingText(
                attributed: AttributedString(marker),
                schedule: schedule,
                range: first..<(first + 1)
            )
        } else {
            Text(marker)
        }
    }

    // MARK: - Figtree heading tokens (never Lora h1/h2)

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 3: return type.h3
        case 4: return type.h4
        case 5: return type.h5
        default: return type.h6
        }
    }

    private func headingLineSpacing(_ level: Int) -> CGFloat {
        switch level {
        case 3: return type.size2XL * 0.2
        case 4: return type.h4LineSpacing
        case 5: return type.h5LineSpacing
        default: return type.h6LineSpacing
        }
    }

    private func plain(_ runs: [MarkdownInline]) -> String {
        runs.map(\.text).joined()
    }
}
