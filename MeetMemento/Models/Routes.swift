//
//  Routes.swift
//  MeetMemento
//
//  Navigation routes for the app
//

import Foundation

// MARK: - Navigation route for journal entry editor
public enum EntryRoute: Hashable, Identifiable {
    case create
    case createWithTitle(String)
    case createWithContent(title: String, content: String)
    case edit(Entry)

    public var id: String {
        switch self {
        case .create:
            return "create"
        case .createWithTitle(let title):
            return "createWithTitle-\(title)"
        case .createWithContent(let title, _):
            return "createWithContent-\(title)"
        case .edit(let entry):
            return "edit-\(entry.id)"
        }
    }

    /// Stable zoom-transition source IDs. Distinct from `id` so create-with-title
    /// still morphs from the FAB, and chat-summary still morphs from sparkles
    /// regardless of the generated title.
    static let createZoomSourceID = "create"
    static let createFromChatZoomSourceID = "createFromChat"

    public var zoomSourceID: String {
        switch self {
        case .create, .createWithTitle:
            return Self.createZoomSourceID
        case .createWithContent:
            return Self.createFromChatZoomSourceID
        case .edit(let entry):
            return "edit-\(entry.id.uuidString)"
        }
    }
}

// MARK: - Navigation route for settings
public enum SettingsRoute: Hashable {
    case main
    case profile
    case appearance
    case voice
    case security
    case about
    case acknowledgments
    case weekly
    case patterns
}

// MARK: - Navigation route for AI Chat
public enum AIChatRoute: Hashable {
    case main
}

// MARK: - Navigation route for Drawer Menu
public enum DrawerRoute: Hashable {
    case aboutYourself
    case journalGoals
}
