//
//  PaywallModel.swift
//  withMemento
//
//  Spec 021: state for `PaywallView`. Sits between the view and
//  `EntitlementStore`, which stays the single source of truth for purchases
//  (R3). The preview model runs on RevenueCat's `TestStoreProduct` data and
//  never touches the SDK, so the screen can be designed and tested while
//  Memento Pro is switched off (`RevenueCatConfig.isPaywallEnabled`).
//

import Foundation
import RevenueCat

@MainActor
final class PaywallModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
        case purchasing
    }

    @Published private(set) var plans: [PaywallPlan] = []
    @Published var selectedID: String?
    @Published private(set) var phase: Phase = .loading

    /// Preview data only: purchase and restore do nothing.
    let isPreview: Bool
    private let store: EntitlementStore

    private init(store: EntitlementStore, isPreview: Bool) {
        self.store = store
        self.isPreview = isPreview
    }

    static func live() -> PaywallModel {
        PaywallModel(store: .shared, isPreview: false)
    }

    // MARK: - Derived

    var selected: PaywallPlan? {
        plans.first { $0.id == selectedID } ?? plans.first
    }

    var savingsPercent: Int? {
        PaywallPlan.savingsPercent(
            annual: plans.first { $0.kind == .annual },
            monthly: plans.first { $0.kind == .monthly }
        )
    }

    // MARK: - Actions

    func load() async {
        guard !isPreview else { return }
        phase = .loading
        let failure = store.offerings == nil ? await store.loadOfferings() : nil
        let loaded = PaywallPlan.ordered(from: store.offerings?.current)
        guard !loaded.isEmpty else {
            phase = .failed(failure ?? "Memento Pro isn't available right now.")
            return
        }
        plans = loaded
        if selectedID == nil { selectedID = loaded.first?.id }
        phase = .ready
    }

    /// True when Memento Pro is now active.
    func purchase() async -> Bool {
        guard phase == .ready, let plan = selected else { return false }
        if isPreview {
            store.lastError = "Purchases are off in preview."
            return false
        }
        phase = .purchasing
        defer { phase = .ready }
        return await store.purchase(plan.package)
    }

    func restore() async {
        if isPreview {
            store.lastError = "Purchases are off in preview."
            return
        }
        await store.restore()
    }
}

// MARK: - Preview data

#if DEBUG
extension PaywallModel {
    /// Launch with `-UITesting -PaywallPreview` to present the paywall over
    /// preview data (double-gated like `-SeedUpgradeFixture`).
    static var isPreviewLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITesting") && arguments.contains("-PaywallPreview")
    }

    /// Which entry point the harness shows: `-PaywallPreviewTrigger dailyLimit`
    /// (any `PaywallTrigger` case name). Defaults to whole-journal Ask.
    static var previewTrigger: PaywallTrigger {
        let name = UserDefaults.standard.string(forKey: "PaywallPreviewTrigger")
        return PaywallTrigger.allCases.first { "\($0)" == name } ?? .askWholeJournal
    }

    static func preview(phase: Phase = .ready) -> PaywallModel {
        let model = PaywallModel(store: .shared, isPreview: true)
        model.plans = PaywallPlan.ordered(from: PaywallFixtures.offering())
        model.selectedID = model.plans.first?.id
        model.phase = phase
        return model
    }
}

/// Store-shaped sample data. Prices are `Decimal`s formatted at runtime, so
/// no price literal appears in source (R1).
enum PaywallFixtures {
    static let locale = Locale(identifier: "en_US")

    static func offering() -> Offering {
        // Monthly listed before annual on purpose: the paywall must still
        // lead with the year. DEC-013 prices (2026-09-26): 59.99 a year and
        // 9.99 a month. No trial on either: the free tier is the trial.
        let packages = [
            package("$rc_monthly", .monthly, product("monthly", 9.99, .init(value: 1, unit: .month))),
            package("$rc_annual", .annual, product("yearly", 59.99, .init(value: 1, unit: .year))),
        ]
        return Offering(
            identifier: "default",
            serverDescription: "Preview",
            availablePackages: packages,
            webCheckoutUrl: nil
        )
    }

    private static func product(
        _ id: String,
        _ price: Decimal,
        _ period: SubscriptionPeriod
    ) -> StoreProduct {
        TestStoreProduct(
            localizedTitle: id,
            price: price,
            currencyCode: "USD",
            localizedPriceString: format(price),
            productIdentifier: id,
            productType: .autoRenewableSubscription,
            localizedDescription: id,
            subscriptionGroupIdentifier: "memento_pro",
            subscriptionPeriod: period,
            locale: locale
        ).toStoreProduct()
    }

    private static func package(_ id: String, _ type: PackageType, _ product: StoreProduct) -> Package {
        Package(identifier: id, packageType: type, storeProduct: product, offeringIdentifier: "default", webCheckoutUrl: nil)
    }

    private static func format(_ price: Decimal) -> String {
        price.formatted(.currency(code: "USD").locale(locale))
    }
}
#endif
