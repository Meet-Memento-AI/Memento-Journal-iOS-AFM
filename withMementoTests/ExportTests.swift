import XCTest
@testable import MeetMemento

/// Pure-function coverage for the journal export (JournalExporter /
/// EntryExportDTO). No disk, no UI — runs in the online CI suite.
final class ExportTests: XCTestCase {

    private func entry(_ title: String, _ text: String, daysAgo: Double) -> Entry {
        Entry(id: UUID(), title: title, text: text,
              createdAt: Date(timeIntervalSince1970: 1_750_000_000 - daysAgo * 86_400),
              updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
    }

    // MARK: - JSON

    func test_json_roundTripsThroughDTO_withISO8601Dates() throws {
        let entries = [entry("First", "Body one", daysAgo: 2),
                       entry("Second", "Body two", daysAgo: 1)]

        let data = try JournalExporter.makeJSON(entries: entries)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([EntryExportDTO].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.title), ["First", "Second"], "oldest first")
        XCTAssertEqual(decoded[0], EntryExportDTO(entries[0]))

        // ISO 8601 encoding truncates sub-second precision; whole-second
        // fixture dates must round-trip exactly.
        XCTAssertEqual(decoded[0].createdAt, entries[0].createdAt)

        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(raw.contains("\"title\""), "sorted, human-readable keys")
    }

    func test_json_emptyJournal_isEmptyArray() throws {
        let data = try JournalExporter.makeJSON(entries: [])
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(raw.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
    }

    // MARK: - Markdown

    func test_markdown_ordersOldestFirst_withDocumentHeader() throws {
        let older = entry("Older", "old text", daysAgo: 10)
        let newer = entry("Newer", "new text", daysAgo: 1)

        let markdown = JournalExporter.makeMarkdown(entries: [newer, older])

        XCTAssertTrue(markdown.hasPrefix("# Memento Journal\n"))
        let olderIndex = try XCTUnwrap(markdown.range(of: "## Older")).lowerBound
        let newerIndex = try XCTUnwrap(markdown.range(of: "## Newer")).lowerBound
        XCTAssertLessThan(olderIndex, newerIndex)
        XCTAssertTrue(markdown.contains("old text"))
        XCTAssertTrue(markdown.contains("new text"))
    }

    func test_markdown_untitledEntry_fallsBackToDateHeading() {
        let dated = entry("", "no title here", daysAgo: 0)
        let markdown = JournalExporter.makeMarkdown(entries: [dated])

        let expectedHeading = "## \(dated.createdAt.formatted(as: "MMM d, yyyy"))"
        XCTAssertTrue(markdown.contains(expectedHeading),
                      "untitled entries use their date as the heading")
    }

    func test_markdown_entriesSeparatedByRules_noTrailingRule() {
        let markdown = JournalExporter.makeMarkdown(entries: [
            entry("A", "alpha", daysAgo: 3),
            entry("B", "beta", daysAgo: 2),
        ])

        XCTAssertEqual(markdown.components(separatedBy: "\n---\n").count, 2,
                       "exactly one separator between two entries")
        XCTAssertFalse(markdown.hasSuffix("---\n"), "document ends with content, not a rule")
    }

    // MARK: - Sample exclusion seam

    @MainActor
    func test_sampleContentService_isSampleEntry_falseForUnknownId() {
        // Unit-level check of the exclusion seam the Settings export uses.
        // (Seeding real sample content requires the app bundle + storage; the
        // filter behavior itself is exercised here via the negative case.)
        XCTAssertFalse(SampleContentService.shared.isSampleEntry(UUID()))
    }
}
