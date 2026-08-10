//
//  Constants.swift
//  MeetMemento
//

import Foundation

struct Constants {
    struct Legal {
        /// GitHub Pages root for this repo (`docs/` publishing source).
        static let siteBaseURL = "https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM"
        static var privacyPolicyURL: URL { URL(string: "\(siteBaseURL)/privacy.html")! }
        static var termsOfServiceURL: URL { URL(string: "\(siteBaseURL)/terms.html")! }
        static var supportPageURL: URL { URL(string: "\(siteBaseURL)/support.html")! }
    }

    struct Support {
        static let email = "contact@sebastianmendo.design"
    }

    struct Storage {
        static let userDefaultsKey = "com.meetmemento.userdefaults"
    }
}
