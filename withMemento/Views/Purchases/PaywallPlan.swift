//
//  PaywallPlan.swift
//  withMemento
//
//  Spec 021 R1: the plans `PaywallView` shows, and every string built from
//  their prices. Prices only ever come from the store (`localizedPriceString`,
//  `localizedPricePerMonth`), never from a literal. Pure, so the rules are
//  unit-testable without a configured SDK.
//

import Foundation
import RevenueCat
import SwiftUI

enum PaywallPlanKind: String, CaseIterable {
    case annual
    case monthly
}

struct PaywallPlan: Identifiable, Equatable {
    let kind: PaywallPlanKind
    let package: Package

    var id: String { package.identifier }
    var product: StoreProduct { package.storeProduct }
    /// The store's own formatted price ("59,99 €").
    var price: String { product.localizedPriceString }

    /// Annual first, then monthly (R1: the value is longitudinal, so the year
    /// leads). Other package types, lifetime included, are ignored: Memento Pro
    /// is a subscription only.
    static func ordered(from offering: Offering?) -> [PaywallPlan] {
        guard let offering else { return [] }
        let packages: [(PaywallPlanKind, Package?)] = [
            (.annual, offering.annual),
            (.monthly, offering.monthly),
        ]
        return packages.compactMap { kind, package in
            package.map { PaywallPlan(kind: kind, package: $0) }
        }
    }

    // MARK: - Copy

    var title: String {
        switch kind {
        case .annual: "Yearly"
        case .monthly: "Monthly"
        }
    }

    /// "a year" — the cadence after the price.
    var cadence: String {
        switch kind {
        case .annual: "a year"
        case .monthly: "a month"
        }
    }

    /// "yearly" / "monthly" — how often it renews.
    var billingWord: String {
        switch kind {
        case .annual: "yearly"
        case .monthly: "monthly"
        }
    }

    /// There is no free trial: the free tier is the trial, and it works on
    /// its own. The button frames Pro as an upgrade and says exactly what is
    /// charged, and how often.
    var ctaTitle: String {
        "Upgrade for \(price) \(cadence)"
    }

    /// The line under the button (App Review 3.1.2). The price and period are
    /// in the button, so this only says that it renews and can be cancelled.
    var disclosure: String {
        "Auto-renews \(billingWord). Cancel anytime."
    }

    /// One VoiceOver phrase for the billing toggle segment.
    func accessibilityLabel(savingsPercent: Int?) -> String {
        var parts = [title, "\(price) \(cadence)"]
        if let savingsPercent { parts.append("save \(savingsPercent) percent") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Arithmetic

    /// Whole-percent saving of the annual plan over twelve monthly payments,
    /// rounded down so the claim is never overstated. Nil when there is no
    /// real saving to show.
    static func savingsPercent(annual: PaywallPlan?, monthly: PaywallPlan?) -> Int? {
        guard let annual, let monthly else { return nil }
        let twelveMonths = monthly.product.price * 12
        guard twelveMonths > 0, annual.product.price < twelveMonths else { return nil }
        var fraction = (twelveMonths - annual.product.price) / twelveMonths * 100
        // Round in Decimal first: `NSDecimalNumber.intValue` misreads values
        // with a long mantissa, which store prices built from floats have.
        var whole = Decimal()
        NSDecimalRound(&whole, &fraction, 0, .down)
        let percent = Int(truncating: whole as NSDecimalNumber)
        return percent >= 1 ? percent : nil
    }
}

// MARK: - Features

/// A row of the Free / Pro comparison table, per spec 021 R4 as amended by
/// DEC-013. Memory and insights lead ("what they get, with memory and
/// insights first"). The last rows are the free-forever promise: journaling,
/// reading and export are never locked.
struct PaywallFeature: Equatable {
    let name: String
    /// True when the free tier includes it. Pro includes every row.
    let inFree: Bool

    static let all: [PaywallFeature] = [
        PaywallFeature(name: "Memory across all your entries", inFree: false),
        PaywallFeature(name: "Insights and patterns", inFree: false),
        PaywallFeature(name: "Sunday weekly review", inFree: false),
        PaywallFeature(name: "Unlimited chats and summaries", inFree: false),
        PaywallFeature(name: "Unlimited journaling", inFree: true),
        PaywallFeature(name: "Read and export every entry", inFree: true),
    ]

    static var proOnly: [PaywallFeature] { all.filter { !$0.inFree } }

    /// One VoiceOver phrase for the row.
    var accessibilityLabel: String {
        "\(name): \(inFree ? "included free" : "Pro only")"
    }
}

// MARK: - Headline

/// What the person just did that opened the paywall (spec 021 R9). The
/// headline names that action. The description says what they keep for free
/// and what the upgrade adds, because the free tier does a lot on its own
/// (DEC-013: "Journaling in Memento is free forever. The AI is what people
/// pay for.").
enum PaywallTrigger: CaseIterable, Identifiable {
    var id: Self { self }

    case settings
    case onboarding
    case secondChat
    case dailyLimit
    case clearChat
    case chatSummary
    case weeklyReview
    case patterns
    case askWholeJournal

    /// The surface a `.proGated(_:)` lock card names. Nil for an unknown
    /// name, so a new gate has to be added here on purpose
    /// (`PaywallPlanTests.testEveryGatedSurfaceHasATrigger`).
    init?(gate: String) {
        switch gate {
        case "Weekly reflections": self = .weeklyReview
        case "Patterns": self = .patterns
        default: return nil
        }
    }

    /// The headline: short, declarative, in the brand's serif. It never
    /// cites a number. It adapts to the journal by choosing the phrase that
    /// is true right now (see `PaywallContext`).
    func title(in context: PaywallContext) -> String {
        switch self {
        case .settings:
            return "Your journal, remembered."
        case .onboarding:
            return "This is just the beginning."
        case .secondChat:
            return "More to talk about."
        case .dailyLimit:
            return "More to say?"
        case .clearChat:
            return "Worth keeping."
        case .chatSummary:
            return "From chat to journal."
        case .weeklyReview:
            return context.hasBusyWeek ? "Your week, in focus." : "One week at a time."
        case .patterns:
            return context.hasPatternHistory ? "See what repeats." : "Patterns take time."
        case .askWholeJournal:
            return context.hasJournal ? "Every entry. One conversation." : "A chat that remembers."
        }
    }

    /// One short line: what Pro does for them. Settings and onboarding also
    /// say that journaling stays free, since nothing more specific opened them.
    func subtitle(in context: PaywallContext) -> String {
        switch self {
        case .settings:
            return "Pro brings memory to every entry. Your writing stays free."
        case .onboarding:
            return "Pro remembers every entry. Journaling stays free."
        case .secondChat:
            return "Pro gives you unlimited chats."
        case .dailyLimit:
            return "Your messages return tomorrow. Or go unlimited with Pro."
        case .clearChat:
            return "Pro saves every conversation."
        case .chatSummary:
            return "Pro turns your conversations into entries."
        case .weeklyReview:
            switch (context.hasBusyWeek, context.isSunday) {
            case (true, true): return "Pro turns this week's writing into today's recap."
            case (true, false): return "Pro turns this week's writing into a Sunday recap."
            case (false, true): return "Pro writes a short recap of your week, today."
            case (false, false): return "Pro writes a short recap of your week, every Sunday."
            }
        case .patterns:
            return context.hasPatternHistory
                ? "Pro finds the people, places and moods that return."
                : "Keep writing. Pro will show you what repeats."
        case .askWholeJournal:
            return context.hasJournal
                ? "Free chat sees your latest entry. Pro sees them all."
                : "As you write, Pro remembers every entry."
        }
    }

    /// The RevenueCat placement the purchase reports (spec 021 R9 table).
    /// Settings isn't a re-offer moment, so it has its own.
    var placement: String {
        switch self {
        case .settings: "settings"
        case .onboarding: "onboarding"
        case .secondChat: "second_chat"
        case .dailyLimit: "daily_limit"
        case .clearChat: "clear_chat"
        case .chatSummary: "chat_summary"
        case .weeklyReview: "weekly_review"
        case .patterns, .askWholeJournal: "locked_surface"
        }
    }
}

// MARK: - Context

/// Local, non-content facts the paywall copy adapts to: counts and the day,
/// never anything from an entry's text. The copy never shows these numbers;
/// they only choose the phrase that is true right now, so there is no "see
/// what repeats" after two entries.
struct PaywallContext: Equatable {
    var entryCount: Int
    var entriesThisWeek: Int
    var isSunday: Bool

    /// Previews, the DEBUG harness, and anywhere the journal isn't known:
    /// every headline falls back to its general form.
    static let unknown = PaywallContext(entryCount: 0, entriesThisWeek: 0, isSunday: false)

    init(entryCount: Int, entriesThisWeek: Int, isSunday: Bool) {
        self.entryCount = entryCount
        self.entriesThisWeek = entriesThisWeek
        self.isSunday = isSunday
    }

    init(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) {
        entryCount = entries.count
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        entriesThisWeek = week.map { week in entries.filter { week.contains($0.createdAt) }.count } ?? 0
        isSunday = calendar.component(.weekday, from: now) == 1
    }

    /// More than one entry, so "every entry" means more than the latest one.
    var hasJournal: Bool { entryCount >= 2 }
    /// Enough writing for patterns to be more than noise.
    var hasPatternHistory: Bool { entryCount >= 10 }
    /// More than one entry this week, so a weekly recap has something to
    /// draw on.
    var hasBusyWeek: Bool { entriesThisWeek >= 2 }
}

extension EnvironmentValues {
    /// Set once at the root (`ContentView`) from the journal, so every
    /// paywall sheet presented below it can tailor its copy.
    @Entry var paywallContext: PaywallContext = .unknown
}
