//
//  MementoAppIntents.swift
//  MeetMemento
//
//  Spec 020 R1: four App Intents + AppShortcutsProvider. No SiriKit.
//  Content-returning intents require device authentication (app lock).
//  Find uses on-device entries (DEC-002 Plan B / REQ-IDX-007).
//

import AppIntents
import Foundation

struct NewJournalEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "New journal entry"
    static var description = IntentDescription("Start or save a journal entry.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Spoken content")
    var spokenContent: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let spokenContent {
            let trimmed = spokenContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                JournalService.shared.saveFromIntent(text: trimmed)
                return .result(dialog: "Saved to your journal.")
            }
        }
        return .result(dialog: "Open Memento to write.")
    }
}

struct ReadWeeklyReflectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Read my weekly reflection"
    static var description = IntentDescription("Read the latest weekly reflection if one exists.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let body = WeeklyReflectionStore.latestBody, !body.isEmpty {
            return .result(dialog: IntentDialog(stringLiteral: String(body.prefix(240))))
        }
        return .result(dialog: "No weekly reflection yet.")
    }
}

struct AskMyJournalIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask my journal"
    static var description = IntentDescription("Ask a question about your journal.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = question
        return .result(dialog: "Open Ask in Memento to continue that question.")
    }
}

struct FindEntriesAboutIntent: AppIntent {
    static var title: LocalizedStringResource = "Find entries about"
    static var description = IntentDescription("Find journal entries matching a topic.")
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Topic")
    var topic: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let hits = EntrySearchIntentRunner.search(topic)
        if hits.isEmpty {
            return .result(dialog: "I don't see entries about that.")
        }
        let preview = hits.prefix(3).map(\.displayTitle).joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: preview))
    }
}

struct MementoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewJournalEntryIntent(),
            phrases: [
                "New entry in \(.applicationName)",
                "Start a journal entry in \(.applicationName)"
            ],
            shortTitle: "New entry",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: ReadWeeklyReflectionIntent(),
            phrases: [
                "Read my weekly reflection in \(.applicationName)"
            ],
            shortTitle: "Weekly reflection",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AskMyJournalIntent(),
            phrases: [
                "Ask \(.applicationName) about my journal",
                "Ask my journal in \(.applicationName)"
            ],
            shortTitle: "Ask journal",
            systemImageName: "bubble.left.and.bubble.right"
        )
        AppShortcut(
            intent: FindEntriesAboutIntent(),
            phrases: [
                "Find entries in \(.applicationName)"
            ],
            shortTitle: "Find entries",
            systemImageName: "magnifyingglass"
        )
    }
}

enum EntrySearchIntentRunner {
    static func search(_ topic: String) -> [Entry] {
        let entries = JournalService.shared.loadAllEntriesLocally(legacyPIN: nil)
        let needle = topic.lowercased()
        guard !needle.isEmpty else { return [] }
        return entries.filter {
            $0.title.lowercased().contains(needle) || $0.text.lowercased().contains(needle)
        }
    }
}
