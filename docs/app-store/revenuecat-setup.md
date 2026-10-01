# RevenueCat setup: Memento Pro

The code side is in place (spec 021 R3/R4). This document covers the dashboard and App Store Connect setup the code expects. None of it lives in the repo.

## On/off switch

`RevenueCatConfig.isPaywallEnabled` (`withMemento/Services/Purchases/RevenueCatConfig.swift`) turns Memento Pro on or off. It is currently **on** (2026-09-30). When off, the SDK is never configured and every paid surface is open. No Pro section or Restore Purchases appears in Settings. This is the same fail-open path as a missing key. To turn the paywall on, set it to `true`.

To see the paywall while it is off, launch a Debug build with `-UITesting -PaywallPreview`. It presents over sample data and never configures the SDK.

To test the **live** flow while the switch is off, launch a Debug build with `-EnablePaywall`. It turns RevenueCat on for that launch only, using the Debug `test_` key against RevenueCat's **Test Store**: real offerings, and a "Test Store Purchase" prompt with **Test valid purchase**, **Test failed purchase** and **Cancel**. Release builds ignore it. `-ForceFreeTier` shows the free chat without RevenueCat at all.

## Identifiers the code depends on

| What | Value | Used in |
|---|---|---|
| Entitlement | `memento_ai_pro` | `EntitlementStore.entitlementID` |
| Products | `monthly`, `yearly` (App Store); `memento_pro_monthly`, `memento_pro_yearly` (Test Store) | Settings plan subtitle (`SettingsView.proPlanSubtitle`, matches any id containing `monthly`) |
| Offering | the **current** offering | `PaywallModel.load()` → `PaywallPlan.ordered(from:)` |

## App Store Connect

1. Create a subscription group **Memento Pro** with two auto-renewable subscriptions: `monthly` (1 month) and `yearly` (1 year). There is no lifetime purchase.
2. Set prices in App Store Connect only: **5.99 USD** for `monthly` and **59.99 USD** for `yearly` (DEC-015, 2026-09-30), with other storefronts at Apple's equivalents. The app never contains a price literal. The paywall shows the store's own price (spec 021 R1).
3. **No free trial** (DEC-014, 2026-09-26): **do not create an introductory offer on either product.** The free tier is the trial. The paywall never mentions a trial, so an offer set up here would make the App Store sheet disagree with the paywall's copy.
4. **Billing Grace Period:** turn it on for the subscription group (spec 021 R11). Billing retry is automatic.
5. Add the in-app purchase key (App Store Connect API key) to the RevenueCat project so RevenueCat can validate receipts.

## RevenueCat dashboard

1. **Products:** import `monthly` and `yearly`. For Debug builds, the **Test Store** uses `memento_pro_monthly` (5.99 USD) and `memento_pro_yearly` (59.99 USD), no introductory offer, because the `test_` key reads prices from there, not from App Store Connect. Test Store prices can't be edited once set, so these replaced the earlier `monthly`/`yearly` Test Store products (9.99/79.99) on 2026-09-30.
2. **Entitlement:** create `memento_ai_pro` and attach both products.
3. **Offering:** create `default` and mark it **Current**. Add these packages:
   - `$rc_annual` → `yearly`, listed **first**, because spec 021 R1 requires annual-first presentation.
   - `$rc_monthly` → `monthly`
4. **Paywall:** nothing to build in the dashboard. The app draws its own paywall (`PaywallView`) from the current offering, using the `$rc_annual` and `$rc_monthly` packages. Any other package type, a lifetime package included, is ignored. There is no trial: the button reads "Upgrade for {price} a year" (spec 021 R10).
5. **Placements** (spec 021 R9): create `onboarding`, `second_chat`, `daily_limit`, `clear_chat`, `chat_summary`, `weekly_review` and `locked_surface`, all pointing at `default`. Purchases then report which moment led to them, with no analytics SDK.
6. **Offering metadata:** `free_daily_messages` (number, default 10) and `first_chat_mode` (string). These are the knobs for spec 021 R12's experiments. The app falls back to bundled defaults when the metadata is missing.
7. **Experiments:** run one at a time, at the offering level only (spec 021 R12).
8. **Customer Center:** turn it on under *Customer Center*. Settings → *Manage Subscription* opens it for Pro users.
9. **Never** add custom attributes or integrations that send user data (spec 014 R4 / REQ-PRIV-001). The app only ever uses the anonymous app-user ID. `RevenueCatConfigTests.testNoRevenueCatIdentityOrAttributeCalls` enforces this on the code side.

## API keys

The keys live in gitignored xcconfig files, following the same pattern as the Supabase keys. The repository is public. See `withMemento/Config/RevenueCat.xcconfig.example`.

- **Debug:** `withMemento/Config/RevenueCat.xcconfig` holds the `test_…` key. It connects to RevenueCat's **Test Store**, so purchases work in the simulator without App Store Connect or sandbox accounts.
- **Release:** `withMemento/Config/RevenueCat.release.xcconfig` holds the production `appl_…` key. It is required before any TestFlight or App Store build, and a `test_` key must never ship.
- **CI / archive machine:** it needs the same files, written from a secret. A missing key isn't a build error. `EntitlementStore` stays off and **every paid surface is open** (fail-open, logged as `REVENUECAT_API_KEY missing`).

## Privacy

The SDK's bundled manifest (purchases-ios-spm 5.91.0) declares **Purchase History**, not linked to identity, not used for tracking, purpose App Functionality. `withMemento/PrivacyInfo.xcprivacy` repeats this declaration, and `scripts/ci/check_privacy_manifest.sh` checks that the two stay paired.

In App Store Connect → App Privacy, declare: **Purchases → Purchase History**, *not linked to the user*, *not used for tracking*, purpose *App Functionality*.

RevenueCat is also on Apple's list of SDKs that need a signature (ITMS-91061). The SPM binary ships signed, so check the upload report on the first archive.

## Go-live checklist: turning the Upgrade button into revenue

The free chat's **✦ Upgrade** pill, the reset dialog's **Keep it with Pro**, and the daily-limit note all open the paywall today, but only in Debug with `-ForceFreeTier`. Every item below must be done before `isPaywallEnabled` goes to `true`.

1. **App Store Connect**
   - The **Paid Apps agreement**, tax and banking forms are active. Without them no purchase can complete.
   - Subscription group **Memento Pro**: `yearly` 59.99 USD and `monthly` 5.99 USD, **no introductory offer** (DEC-014), Billing Grace Period on.
   - Each product has its display name and description, and a review screenshot of the paywall.
2. **RevenueCat**
   - Products, entitlement `memento_ai_pro`, and the current `default` offering (`$rc_annual` first).
   - The placements listed above, and offering metadata `free_daily_messages`.
   - Customer Center on.
   - The same prices on the Test Store products.
3. **Keys:** the production `appl_` key in the gitignored `RevenueCat.release.xcconfig` on the archive machine, written from a secret. A `test_` key must never ship.
4. **Compliance before submitting**
   - **App Privacy label:** Purchases → Purchase History, *not linked*, *not tracking*. `docs/app-store/00`, `03` and `13` still say otherwise and must be corrected first. A label that disagrees with the manifest is the November 2025 rejection pattern.
   - `docs/terms.html` gains a subscription section: what renews, and how to cancel in Settings.
   - `metadata/en-US/description.txt` gains the subscription paragraph (Guideline 2.3.2), with a link to the Terms of Use.
   - App Review notes explain what's free and what Pro adds, and how to reach the paywall: the chat's Upgrade button.
5. **Code:** pass each `PaywallTrigger.placement` to RevenueCat (`Purchases.shared.getCurrentOffering(forPlacement:)`), so purchases report where they came from (spec 021 R9, task 10).
6. **Switch on:** `RevenueCatConfig.isPaywallEnabled = true`.
7. **Sandbox and TestFlight pass**
   - Buy yearly and monthly. Restore on a second device.
   - Cancel, let it lapse, and check the free chat comes back.
   - Open the paywall from each entry point and check the placement shows in RevenueCat.
   - Hit the daily limit, and check a crisis phrase still gets the resource card.
   - On a device without Apple Intelligence, no purchase UI appears anywhere.
8. **Measure** (spec 021 R11): revenue per install at day 60, conversion by placement, and refund rate, all from RevenueCat and App Store Connect.
