//
//  HistoryWindow.swift
//  MeetMemento
//
//  A short rolling summary plus the last four turns. Notebook prompts also
//  receive evidence passages from retrieval, not two dozen raw messages.
//

import Foundation

enum HistoryWindow {
    static let recentLimit = 4

    /// Summary line, then the last four turns. Short histories pass through.
    static func promptHistory(_ history: [ChatTurn]) -> [ChatTurn] {
        guard history.count > recentLimit else { return history }
        let recent = Array(history.suffix(recentLimit))
        // budget-exempt: summary sample, not a model window
        let olderUsers = history.dropLast(recentLimit).filter { $0.role == .user }.suffix(3)
        // budget-exempt: summary clip, not a model window
        let bits = olderUsers.map { String($0.text.prefix(60)) }.filter { !$0.isEmpty }
        guard !bits.isEmpty else { return recent }
        let summary = ChatTurn(
            role: .user,
            text: "Earlier in this conversation: " + bits.joined(separator: "; ")
        )
        return [summary] + recent
    }
}
