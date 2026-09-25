//
//  EntitlementStore.swift
//  withMemento
//
//  Spec 021 R3: the single observable source of truth for Memento Pro.
//
//  Data diet (spec 014 R4 / REQ-PRIV-001): RevenueCat is the sole Z2 exception
//  and receives purchase receipts under its *anonymous* app-user ID only.
//  There are no accounts (spec 023), so never call `logIn`, never pass an
//  `appUserID`, never set attributes, email, or anything derived from user
//  content. Restore Purchases is the only cross-device path.
//

import Foundation
import RevenueCat

@MainActor
final class EntitlementStore: ObservableObject {
    static let shared = EntitlementStore()

    static let entitlementID = "memento_ai_pro"
    private static let cachedIsProKey = "memento_pro_cached_is_pro"

    /// Last known entitlement, persisted so gates are right on the first frame
    /// (and offline) before the SDK reports. The SDK's own CustomerInfo cache
    /// is authoritative as soon as it arrives.
    @Published private(set) var isPro: Bool
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isRestoring = false
    /// User-facing message for the last failed action; views clear it.
    @Published var lastError: String?

    /// False when the key is missing or under tests. The paywall can't render
    /// without a configured SDK, so ProAccess treats this as unlocked rather
    /// than offering a purchase that would crash.
    private(set) var isConfigured = false
    private var streamTask: Task<Void, Never>?

    private init() {
        isPro = UserDefaults.standard.bool(forKey: Self.cachedIsProKey)
    }

    /// Active Memento Pro entitlement, if any (for plan name / renewal date).
    var activeEntitlement: EntitlementInfo? {
        customerInfo?.entitlements[Self.entitlementID].flatMap { $0.isActive ? $0 : nil }
    }

    // MARK: - Setup

    func configure() {
        guard !isConfigured else { return }
        let env = ProcessInfo.processInfo
        // Tests never reach the SDK (unconfigured → paid surfaces open).
        if env.environment["XCTestConfigurationFilePath"] != nil { return }
        if env.arguments.contains("-UITesting") { return }
        guard let apiKey = RevenueCatConfig.apiKeyFromBundle() else {
            AppLogger.log("[Purchases] REVENUECAT_API_KEY missing — Memento Pro disabled")
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        // No appUserID: RevenueCat generates and keeps an anonymous one.
        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true

        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    // MARK: - Reads

    func refresh() async {
        guard isConfigured else { return }
        do {
            apply(try await Purchases.shared.customerInfo())
        } catch {
            // Offline is fine: the cached isPro stands.
            AppLogger.log("[Purchases] customerInfo failed: \(error.localizedDescription)")
        }
    }

    func loadOfferings() async {
        guard isConfigured else { return }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            AppLogger.log("[Purchases] offerings failed: \(error.localizedDescription)")
            lastError = Self.message(for: error)
        }
    }

    // MARK: - Actions

    /// For custom purchase UI. The RevenueCat paywall purchases on its own and
    /// the result arrives here through `customerInfoStream`.
    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        guard isConfigured else { return false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            apply(result.customerInfo)
            return !result.userCancelled && isPro
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    func restore() async {
        guard isConfigured, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            apply(try await Purchases.shared.restorePurchases())
            if !isPro {
                lastError = "No Memento Pro purchase was found for this Apple Account."
            }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    func apply(_ info: CustomerInfo) {
        customerInfo = info
        let active = info.entitlements[Self.entitlementID]?.isActive == true
        if active != isPro { isPro = active }
        UserDefaults.standard.set(active, forKey: Self.cachedIsProKey)
    }

    // MARK: - Errors

    /// Plain-language copy for RevenueCat errors. `nil` for a user cancel,
    /// which is not an error worth showing.
    static func message(for error: Error) -> String? {
        guard let code = (error as? ErrorCode) ?? (error as NSError).rcErrorCode else {
            return "Something went wrong. Please try again."
        }
        switch code {
        case .purchaseCancelledError:
            return nil
        case .networkError, .offlineConnectionError:
            return "You're offline. Connect to the internet and try again."
        case .purchaseNotAllowedError:
            return "Purchases aren't allowed on this device. Check Screen Time restrictions."
        case .paymentPendingError:
            return "Your purchase is pending approval. Memento Pro unlocks once it's approved."
        case .productAlreadyPurchasedError, .receiptAlreadyInUseError:
            return "This purchase is already active. Try Restore Purchases."
        case .storeProblemError:
            return "The App Store had a problem. Please try again in a moment."
        case .productNotAvailableForPurchaseError, .configurationError:
            return "Memento Pro isn't available right now. Please try again later."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

private extension NSError {
    var rcErrorCode: ErrorCode? {
        domain == ErrorCode.errorDomain ? ErrorCode(rawValue: code) : nil
    }
}
