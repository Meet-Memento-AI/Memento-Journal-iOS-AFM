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

        /// GitHub Pages for this repo (`main` → `/docs`). Checklist A6.
        static let siteBase = URL(string: "https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM")!

        static let privacyPolicyURL = siteBase.appendingPathComponent("privacy.html")
        static let termsOfServiceURL = siteBase.appendingPathComponent("terms.html")
        static let supportURL = siteBase.appendingPathComponent("support.html")
    }
}
