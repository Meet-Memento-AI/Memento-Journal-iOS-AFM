//
//  FreeChatAllowance.swift
//  withMemento
//
//  Spec 021 R4 `REQ-MON-006`: the free chat's daily message limit.
//
//  - Memento's own entitlement limit, counted on the device. It is not
//    Apple's PCC quota and never models it (017 R3 amendment): its copy
//    never mentions Apple, iCloud+ or quota.
//  - Counts the person's messages per local day and resets at local
//    midnight. No running "N left" is ever shown.
//  - The limit comes from RevenueCat offering metadata `free_daily_messages`
//    (so R12 can test it without a release), with a bundled default.
//  - Crisis-adjacent messages are never blocked and never counted (026 R4
//    amendment); the caller checks `SafetyClassifier` first.
//

import Foundation
import RevenueCat

@MainActor
final class FreeChatAllowance {
    static let shared = FreeChatAllowance()

    static let defaultDailyLimit = 10
    static let metadataKey = "free_daily_messages"

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let limitProvider: @MainActor () -> Int?

    private static let dayKey = "memento_free_chat_day"
    private static let countKey = "memento_free_chat_count"

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        limitProvider: @escaping @MainActor () -> Int? = { FreeChatAllowance.limitFromOffering() }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.limitProvider = limitProvider
    }

    /// Today's limit: the offering's metadata when it carries a sensible
    /// value, otherwise the bundled default.
    var dailyLimit: Int {
        guard let value = limitProvider(), value > 0 else { return Self.defaultDailyLimit }
        return value
    }

    /// Messages sent today.
    var usedToday: Int {
        defaults.string(forKey: Self.dayKey) == todayKey ? defaults.integer(forKey: Self.countKey) : 0
    }

    var isExhausted: Bool { usedToday >= dailyLimit }

    /// Records one message. Call only for messages that count.
    func recordMessage() {
        let count = usedToday + 1
        defaults.set(todayKey, forKey: Self.dayKey)
        defaults.set(count, forKey: Self.countKey)
    }

    private var todayKey: String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Reads `free_daily_messages` from the current RevenueCat offering, if
    /// the SDK has loaded one.
    static func limitFromOffering() -> Int? {
        EntitlementStore.shared.offerings?.current?.getMetadataValue(for: metadataKey, default: 0)
    }
}
