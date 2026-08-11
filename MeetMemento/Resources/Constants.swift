//
//  Constants.swift
//  MeetMemento
//
//  Single source of truth for the support address and hosted legal pages, so
//  the three surfaces that show them (Settings, About, Data Usage) can never
//  drift apart again — three different support emails were in circulation
//  before this existed (checklist D3).
//

import Foundation

enum Constants {
    /// Legal/contact endpoints. The email is the developer-account address
    /// verified with Apple; App Store Connect fields must match it.
    enum Legal {
        static let supportEmail = "contact@sebastianmendo.design"

        // TODO(user-confirm): repoint at the Meet-Memento-AI GitHub Pages host
        // once checklist A6 publishes docs/ from this repo. Until then these
        // stay on the currently-live host — an in-app link must never 404.
        static let privacyPolicyURL = URL(string: "https://sebmendo1.github.io/MeetMemento/privacy.html")!
        static let termsOfServiceURL = URL(string: "https://sebmendo1.github.io/MeetMemento/terms.html")!
    }
}
