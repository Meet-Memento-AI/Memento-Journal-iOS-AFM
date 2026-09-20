//
//  JournalFABTitle.swift
//  MeetMemento
//
//  Journal footer copy. Empty-journal wording is only legal after the first
//  load has finished — otherwise launch flashes "Write your first entry"
//  over a journal that already has rows.
//

enum JournalFABTitle {
    static let emptyJournal = "Write your first entry"
    static let hasEntries = "New entry"

    static func resolved(hasInitiallyLoaded: Bool, isEmpty: Bool) -> String {
        (hasInitiallyLoaded && isEmpty) ? emptyJournal : hasEntries
    }
}
