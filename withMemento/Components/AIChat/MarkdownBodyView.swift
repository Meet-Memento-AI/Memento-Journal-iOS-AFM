//
//  MarkdownBodyView.swift
//  MeetMemento
//
//  Figtree-only renderer for assistant markdown blocks (ask@11). Never uses
//  Typography.h1 / h2 (Lora display). Headings map ###→h3 … ######→h6.
//

import SwiftUI

struct MarkdownBodyView: View {
    let blocks: [MarkdownBlock]
    /// When > 0, fade the newest characters of the last renderable block.
    var dissolveCount: Int = 0
    var dissolveMinOpacity: Double = 0.1
    var showCaret: Bool = false

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isLastRenderable: index == lastRenderableIndex)
                    .padding(.top, topPadding(at: index))
                    .accessibilityAddTraits(traits(for: block))
            }
            if blocks.isEmpty, showCaret {
                caretText
            }
        }
        .limitDynamicTypeSize()
    }

    // MARK: - Layout

    private var lastRenderableIndex: Int {
        blocks.indices.reversed().first { idx in
            if case .blank = blocks[idx] { return false }
            return true
        } ?? -1
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
    private func blockView(_ block: MarkdownBlock, isLastRenderable: Bool) -> some View {
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
                dissolve: isLastRenderable,
                caret: isLastRenderable && showCaret
            )
            .accessibilityLabel(plain(runs))

        case .paragraph(let runs):
            styledText(
                runs: runs,
                baseFont: type.body1,
                boldFont: type.body1Bold,
                lineSpacing: type.bodyLineSpacing,
                dissolve: isLastRenderable,
                caret: isLastRenderable && showCaret
            )

        case .unorderedItem(let depth, let runs):
            listRow(
                marker: "\u{2022}",
                markerWidth: 14,
                depth: depth,
                runs: runs,
                dissolve: isLastRenderable,
                caret: isLastRenderable && showCaret
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(plain(runs))

        case .orderedItem(let n, let depth, let runs):
            listRow(
                marker: "\(n).",
                markerWidth: 28,
                depth: depth,
                runs: runs,
                dissolve: isLastRenderable,
                caret: isLastRenderable && showCaret
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
        dissolve: Bool,
        caret: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text(marker)
                .font(type.body1)
                .foregroundStyle(theme.foreground)
                .frame(width: markerWidth, alignment: .trailing)
                .accessibilityHidden(true)
            styledText(
                runs: runs,
                baseFont: type.body1,
                boldFont: type.body1Bold,
                lineSpacing: type.bodyLineSpacing,
                dissolve: dissolve,
                caret: caret
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(depth) * Spacing.lg)
    }

    private func styledText(
        runs: [MarkdownInline],
        baseFont: Font,
        boldFont: Font,
        lineSpacing: CGFloat,
        dissolve: Bool,
        caret: Bool
    ) -> some View {
        var attr = RichTextParser.attributed(
            runs,
            baseFont: baseFont,
            boldFont: boldFont,
            textColor: theme.foreground
        )
        if dissolve, dissolveCount > 0 {
            applyDissolve(&attr)
        }
        if caret {
            var caretAttr = AttributedString("\u{258F}")
            caretAttr.foregroundColor = theme.mutedForeground
            attr.append(caretAttr)
        }
        return Text(attr).lineSpacing(lineSpacing)
    }

    private var caretText: some View {
        Text("\u{258F}")
            .foregroundStyle(theme.mutedForeground)
    }

    private func applyDissolve(_ attr: inout AttributedString) {
        let ramp = min(dissolveCount, attr.characters.count)
        guard ramp > 0 else { return }
        var upper = attr.characters.endIndex
        for k in 0..<ramp {
            let lower = attr.characters.index(before: upper)
            let t = Double(k + 1) / Double(ramp)
            let alpha = dissolveMinOpacity + (1 - dissolveMinOpacity) * t
            attr[lower..<upper].foregroundColor = theme.foreground.opacity(alpha)
            upper = lower
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
