# RevenueCat setup: Memento Pro

The code side is in place (spec 021 R3/R4). This document covers the dashboard and App Store Connect setup the code expects. None of it lives in the repo.

## Identifiers the code depends on

| What | Value | Used in |
|---|---|---|
| Entitlement | `memento_ai_pro` | `EntitlementStore.entitlementID` |
| Products | `monthly`, `yearly`, `lifetime` | Settings plan subtitle (`SettingsView.proPlanSubtitle`) |
| Offering | the **current** offering | `PaywallView()` with no explicit offering |

## App Store Connect

1. Create a subscription group **Memento Pro** with two auto-renewable subscriptions: `monthly` (1 month) and `yearly` (1 year).
2. Create a **non-consumable** in-app purchase: `lifetime`.
3. Set prices in App Store Connect only. The app never contains a price literal. The paywall renders `displayPrice` from the store (spec 021 R1).
4. Add the in-app purchase key (App Store Connect API key) to the RevenueCat project so RevenueCat can validate receipts.

## RevenueCat dashboard

1. **Products:** import `monthly`, `yearly` and `lifetime`.
2. **Entitlement:** create `memento_ai_pro` and attach all three products.
3. **Offering:** create `default` and mark it **Current**. Add these packages:
   - `$rc_annual` → `yearly`, listed **first**, because spec 021 R1 requires annual-first presentation.
   - `$rc_monthly` → `monthly`
   - `$rc_lifetime` → `lifetime`
4. **Paywall:** build it in *Paywalls* on the `default` offering. Choose a template that shows **Restore Purchases without scrolling**. With no accounts, restore is the only way to move a purchase to another device (R3).
5. **Customer Center:** turn it on under *Customer Center*. Settings → *Manage Subscription* opens it for Pro users.
6. **Never** add custom attributes or integrations that send user data (spec 014 R4 / REQ-PRIV-001). The app only ever uses the anonymous app-user ID. `RevenueCatConfigTests.testNoRevenueCatIdentityOrAttributeCalls` enforces this on the code side.

## API keys

The keys live in gitignored xcconfig files, following the same pattern as the Supabase keys. The repository is public. See `withMemento/Config/RevenueCat.xcconfig.example`.

- **Debug:** `withMemento/Config/RevenueCat.xcconfig` holds the `test_…` key. It connects to RevenueCat's **Test Store**, so purchases work in the simulator without App Store Connect or sandbox accounts.
- **Release:** `withMemento/Config/RevenueCat.release.xcconfig` holds the production `appl_…` key. It is required before any TestFlight or App Store build, and a `test_` key must never ship.
- **CI / archive machine:** it needs the same files, written from a secret. A missing key isn't a build error. `EntitlementStore` stays off and **every paid surface is open** (fail-open, logged as `REVENUECAT_API_KEY missing`).

## Privacy

The SDK's bundled manifest (purchases-ios-spm 5.91.0) declares **Purchase History**, not linked to identity, not used for tracking, purpose App Functionality. `withMemento/PrivacyInfo.xcprivacy` repeats this declaration, and `scripts/ci/check_privacy_manifest.sh` checks that the two stay paired.

In App Store Connect → App Privacy, declare: **Purchases → Purchase History**, *not linked to the user*, *not used for tracking*, purpose *App Functionality*.

RevenueCat is also on Apple's list of SDKs that need a signature (ITMS-91061). The SPM binary ships signed, so check the upload report on the first archive.
