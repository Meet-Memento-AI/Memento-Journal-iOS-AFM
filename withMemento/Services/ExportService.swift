//
//  ExportService.swift
//  MeetMemento
//
//  Exports the user's journal as Markdown and JSON. The store description
//  calls export "the point" of owning your words, so this is a core surface,
//  not a convenience: everything the user wrote, in two portable formats, at
//  no cost.
//
//  Design notes:
//  - Pure functions (`JournalExporter`) do the formatting so tests can cover
//    them without touching disk. File writing is a thin layer on top.
//  - Files are written to a dedicated temp subdirectory with
//    `.completeFileProtection` (matching LocalJournalStorage's convention),
//    recreated on each export and deleted when the share sheet closes — the
//    plaintext export must not linger at rest.
//  - Sample entries (SampleContentService) are excluded by the caller: the
//    export is the user's archive, not the bundled fiction.
//

import Foundation

/// Codable snapshot of an entry for the JSON export. `Entry` itself is a UI
/// model and deliberately not Codable; this DTO fixes the exported schema so
/// UI-model changes can't silently change the export format.
struct EntryExportDTO: Codable, Equatable {
    let id: UUID
    let title: String
    let text: String
    let createdAt: Date
    let updatedAt: Date

    init(_ entry: Entry) {
        self.id = entry.id
        self.title = entry.title
        self.text = entry.text
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
    }
}

/// Stateless formatting + file-writing for journal export.
enum JournalExporter {
    /// The whole journal as one Markdown document, oldest entry first — an
    /// archive reads front to back.
    static func makeMarkdown(entries: [Entry]) -> String {
        let ordered = entries.sorted { $0.createdAt < $1.createdAt }
        var lines: [String] = ["# Memento Journal", ""]
        for entry in ordered {
            let heading = entry.title.isEmpty ? entry.createdAt.formatted(as: "MMM d, yyyy") : entry.title
            lines.append("## \(heading)")
            lines.append("_\(entry.createdAt.formatted(as: "MMMM d, yyyy"))_")
            lines.append("")
            lines.append(entry.text)
            lines.append("")
            lines.append("---")
            lines.append("")
        }
        // Drop the trailing separator block for a clean document end.
        if lines.suffix(3) == ["", "---", ""] {
            lines.removeLast(3)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The whole journal as pretty-printed JSON with ISO 8601 dates, oldest
    /// entry first (same order as the Markdown).
    static func makeJSON(entries: [Entry]) throws -> Data {
        let ordered = entries.sorted { $0.createdAt < $1.createdAt }
        // JSONEncoder + .prettyPrinted emits "[\n\n]\n" for an empty array on
        // current Foundation; the export contract (and ExportTests) wants [].
        if ordered.isEmpty {
            return Data("[]".utf8)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ordered.map(EntryExportDTO.init))
    }

    /// Directory the export files are written to. Recreated on every export,
    /// deleted by `cleanUp()` when the share sheet closes.
    static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
    }

    /// Writes `Memento-Journal-<date>.md` and `.json` and returns their URLs.
    /// Any previous export is removed first so stale files are never shared.
    static func writeExportFiles(entries: [Entry], now: Date = Date()) throws -> [URL] {
        let directory = exportDirectory
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = now.formatted(as: "yyyy-MM-dd")
        let markdownURL = directory.appendingPathComponent("Memento-Journal-\(stamp).md")
        let jsonURL = directory.appendingPathComponent("Memento-Journal-\(stamp).json")

        // Same file protection as the encrypted store: the plaintext export
        // exists only for the handoff, but while it exists it stays protected.
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        try Data(makeMarkdown(entries: entries).utf8).write(to: markdownURL, options: options)
        try makeJSON(entries: entries).write(to: jsonURL, options: options)

        return [markdownURL, jsonURL]
    }

    /// Deletes the export directory (called when the share sheet closes).
    static func cleanUp() {
        try? FileManager.default.removeItem(at: exportDirectory)
    }
}
