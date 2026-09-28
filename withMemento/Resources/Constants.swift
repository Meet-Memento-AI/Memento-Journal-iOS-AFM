//
//  Constants.swift
//  withMemento
//
//  Single source of truth for the support address and hosted legal pages, so
//  the three surfaces that show them (Settings, About, Data Usage) can never
//  drift apart again — three different support emails were in circulation
//  before this existed (checklist D3).
//

import Foundation

enum Constants {
    /// Legal/contact endpoints. App Store Connect fields must match this
    /// email — the support field, and the App Review / TestFlight contact.
    enum Legal {
        /// Re-pointed 2026-09-17 from `contact@sebastianmendo.design` (the
        /// Apple developer-account address) to the product's own domain.
        /// Guideline 1.5 requires this mailbox to actually receive, so it
        /// must be live before submission — see checklist D3.
        static let supportEmail = "hello@withmemento.ai"

        /// GitHub Pages for this repo (`main` → `/docs`). Checklist A6.
        static let siteBase = URL(string: "https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM")!

        static let privacyPolicyURL = siteBase.appendingPathComponent("privacy.html")
        static let termsOfServiceURL = siteBase.appendingPathComponent("terms.html")
        static let supportURL = siteBase.appendingPathComponent("support.html")
    }
}
