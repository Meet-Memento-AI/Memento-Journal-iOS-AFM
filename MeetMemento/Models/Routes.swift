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
}

// MARK: - Navigation route for settings
public enum SettingsRoute: Hashable {
    case main
    case profile
    case appearance
    case voice
    case security
    case about
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
