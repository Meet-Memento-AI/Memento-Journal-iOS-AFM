//
//  FeedbackDeviceIdentity.swift
//  MeetMemento
//
//  Install-scoped UUID used only as the spec 042 erase key. Created on first
//  consented enqueue. Not an account.
//

import Foundation

enum FeedbackDeviceIdentity {
    static let defaultsKey = "memento_verification_device_id"

    static func peek(defaults: UserDefaults = .standard) -> UUID? {
        guard let raw = defaults.string(forKey: defaultsKey) else { return nil }
        return UUID(uuidString: raw)
    }

    @discardableResult
    static func registered(defaults: UserDefaults = .standard) -> UUID {
        if let existing = peek(defaults: defaults) { return existing }
        let generated = UUID()
        defaults.set(generated.uuidString, forKey: defaultsKey)
        return generated
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
