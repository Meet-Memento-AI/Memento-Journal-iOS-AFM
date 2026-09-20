//
//  RichTextParserTests.swift
//  MeetMementoTests
//
//  Block AST + streaming splice for ask@11 markdown.
//

import XCTest
import SwiftUI
@testable import MeetMemento

final class RichTextParserTests: XCTestCase {

    private func blocks(_ text: String, closed: Bool = true) -> [MarkdownBlock] {
        RichTextParser.parseBlocks(text, lastLineClosed: closed)
    }

    // MARK: - Headings

    func test_atxH3_stripsHashes() {
        let parsed = blocks("### 12 March")
        XCTAssertEqual(parsed, [.heading(level: 3, runs: [.plain("12 March")])])
    }

    func test_hashAndDoubleHash_demoteToH3() {
        XCTAssertEqual(blocks("# Title"), [.heading(level: 3, runs: [.plain("Title")])])
        XCTAssertEqual(blocks("## Title"), [.heading(level: 3, runs: [.plain("Title")])])
    }

    func test_h4ThroughH6() {
        XCTAssertEqual(blocks("#### Sub"), [.heading(level: 4, runs: [.plain("Sub")])])
        XCTAssertEqual(blocks("##### Minor"), [.heading(level: 5, runs: [.plain("Minor")])])
        XCTAssertEqual(blocks("###### Micro"), [.heading(level: 6, runs: [.plain("Micro")])])
    }

    func test_incompleteHeading_staysParagraph() {
        let parsed = blocks("### 12 Marc", closed: false)
        XCTAssertEqual(parsed, [.paragraph(runs: [.plain("### 12 Marc")])])
    }

    // MARK: - Lists

    func test_unorderedDashStarPlus() {
        XCTAssertEqual(
            blocks("- First\n* Second\n+ Third"),
            [
                .unorderedItem(depth: 0, runs: [.plain("First")]),
                .unorderedItem(depth: 0, runs: [.plain("Second")]),
                .unorderedItem(depth: 0, runs: [.plain("Third")])
            ]
        )
    }

    func test_orderedList_preservesNumbers() {
        XCTAssertEqual(
            blocks("1. Sleep\n2. Walks"),
            [
                .orderedItem(index: 1, depth: 0, runs: [.plain("Sleep")]),
                .orderedItem(index: 2, depth: 0, runs: [.plain("Walks")])
            ]
        )
    }

    func test_oneIndentLevel_isDepthOne() {
        XCTAssertEqual(
            blocks("- Outer\n  - Inner"),
            [
                .unorderedItem(depth: 0, runs: [.plain("Outer")]),
                .unorderedItem(depth: 1, runs: [.plain("Inner")])
            ]
        )
    }

    func test_deeperNesting_staysParagraph() {
        let parsed = blocks("    - too deep")
        guard case .paragraph = parsed.first else {
            return XCTFail("expected paragraph, got \(parsed)")
        }
    }

    func test_incompleteOrdered_staysParagraph() {
        XCTAssertEqual(
            blocks("1. Sleep", closed: false),
            [.paragraph(runs: [.plain("1. Sleep")])]
        )
    }

    // MARK: - Inlines

    func test_boldItalicCodeAndUnderscore() {
        XCTAssertEqual(
            RichTextParser.parseInlines("**bold** and *italic* and `code` and _soft_"),
            [.bold("bold"), .plain(" and "), .italic("italic"), .plain(" and "),
             .code("code"), .plain(" and "), .italic("soft")]
        )
    }

    func test_refMarker_isPlainTextNotALink() {
        let parsed = blocks("See [ref 2] later.")
        XCTAssertEqual(parsed, [.paragraph(runs: [.plain("See [ref 2] later.")])])
    }

    func test_citationNumber_isPlainText() {
        let parsed = blocks("It resurfaced [1].")
        XCTAssertEqual(parsed, [.paragraph(runs: [.plain("It resurfaced [1].")])])
    }

    // MARK: - Mixed + blanks

    func test_journalShape_headingQuoteSit() {
        let text = "You asked how work has been landing.\n\n### 12 March\n*I left with my jaw still tight.*\nThat walk is the part you stayed with."
        let parsed = blocks(text)
        XCTAssertEqual(parsed.count, 5)
        XCTAssertEqual(parsed[0], .paragraph(runs: [.plain("You asked how work has been landing.")]))
        XCTAssertEqual(parsed[1], .blank)
        XCTAssertEqual(parsed[2], .heading(level: 3, runs: [.plain("12 March")]))
        XCTAssertEqual(parsed[3], .paragraph(runs: [.italic("I left with my jaw still tight.")]))
        XCTAssertEqual(parsed[4], .paragraph(runs: [.plain("That walk is the part you stayed with.")]))
    }

    func test_tablesAndFences_stayParagraphs() {
        XCTAssertEqual(
            blocks("| a | b |"),
            [.paragraph(runs: [.plain("| a | b |")])]
        )
        XCTAssertEqual(
            blocks("```swift"),
            [.paragraph(runs: [.plain("```swift")])]
        )
    }

    // MARK: - Streaming splice

    func test_splicedBlocks_equalFullParse_whenLastLineOpen() {
        let samples = [
            "plain single line",
            "line one\nline two",
            "trailing newline\n",
            "\nleading newline",
            "blank\n\nline between",
            "- first bullet\n- second **bold** bullet\n- third *soft* point",
            "**bold** intro\nthen *italic* tail",
            "finished line with **bold**\nan unclosed **marker",
            "finished line\n- a bullet still typi",
            "*italic\nsplit across lines*",
            "Meet them here.\n### 12 Marc",
            "Meet them here.\n### 12 March\n1. The lon"
        ]
        for text in samples {
            let split = AIOutputComponent.lastLineStart(of: text)
            let prefix = String(text[..<split])
            let trailing = String(text[split...])
            let spliced = RichTextParser.parseBlocks(prefix, lastLineClosed: true)
                + RichTextParser.parseBlocks(trailing, lastLineClosed: false)
            let full = RichTextParser.parseBlocks(text, lastLineClosed: false)
            XCTAssertEqual(spliced, full, "splice diverged for: \(text.debugDescription)")
        }
    }

    func test_settledLastHeading_withoutTrailingNewline() {
        let parsed = blocks("You asked about work.\n### 12 March", closed: true)
        XCTAssertEqual(
            parsed.last,
            .heading(level: 3, runs: [.plain("12 March")])
        )
    }

    func test_attributedFlatten_bulletsAndBold() {
        let attr = RichTextParser.parse(
            "- First **bold** item",
            baseFont: .body,
            boldFont: .body.bold(),
            textColor: .primary
        )
        XCTAssertTrue(String(attr.characters).contains("First bold item"))
        XCTAssertTrue(String(attr.characters).hasPrefix("\u{2022} "))
    }
}
