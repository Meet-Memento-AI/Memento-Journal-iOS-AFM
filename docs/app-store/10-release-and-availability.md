# 10 — Release, availability, and post-launch operations (Gate L)

**Compiled 2026-08-07.**
**Sources:** [Overview of publishing](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store/) ·
[Select a version release option](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/) ·
[Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/) ·
[Manage availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/)

---

## 1. Pricing

**Both a price and a tax category must be set before submission.**

🔒 **Blocked on `DEC-004`** (`specs/021` R1) — final monthly and annual price and
trial length are an open product decision. The constraint that holds under either
option is **annual-first presentation**: the value proposition is explicitly
longitudinal, so leading with monthly is a positioning mismatch.

What this document adds to that decision, from the guidelines:

- **Guideline 3.1.2** — subscriptions must be **at least 7 days** and must work
  across all the user's devices.
- **Guideline 3.1.1** — no non-StoreKit unlock path; any consumable credits may
  **not expire**; **Restore Purchases** is required, and with no accounts it is
  the *only* cross-device entitlement path (`specs/021` R3 makes it visible
  without scrolling).
- **Guideline 2.3.7** — **no price anywhere in the metadata.** The store shows
  it. `04`'s description draft complies.
- **Guideline 4.10** — price the product, never the Apple technology (`01` §4.10).
- The paywall renders `Product.displayPrice` from StoreKit, never a literal
  (`specs/021` R1's acceptance criterion).

**Free trials** are configured in App Store Connect, not hand-rolled. A
time-limited free trial for a non-subscription product would instead be a
Non-Consumable at Price Tier 0 named "XX-day Trial" — not our shape.

---

## 2. Territories

**Where:** Pricing and Availability → App Availability → Manage. 175 storefronts.
Status indicators: red = unavailable, **yellow = action required from you**,
green = available.

| Territory | Decision | Reason |
|---|---|---|
| **EU (27)** | 🔒 **Pending** | DSA trader status publishes an individual developer's address and phone on the product page. Two branches costed in `05` §4 |
| **Mainland China** | **Exclude** | An **ICP filing number** is required to distribute; apps without one cannot publish updates and face removal. Effectively unobtainable for a foreign individual without a mainland entity |
| **South Korea** | Include | A content-rating declaration applies to organization-enrolled developers; scope for non-game individual developers is `[verify]` at selection time |
| Everywhere else | Include | |

**Removing a territory takes effect within 24 hours.** Existing owners keep the
app, keep receiving updates, and can re-download from purchase history as long as
the necessary agreements stay in effect.

Adding the EU later is a settings change, not a resubmission — so **Option B in
`05` §4 (launch without the EU) is reversible** and is the safe default if the
address decision is not resolved in time. Do not let it block launch.

---

## 3. Release option

Set **before submitting**, on the version page under *App Store Version Release*.

| Option | Behavior |
|---|---|
| **Manually release this version** | On approval the status becomes **Pending Developer Release**; you press the button. Apple emails a reminder if it sits there **more than 30 days** |
| **Automatically release this version** | Live immediately on approval |
| **Automatically release after App Review, no earlier than [date]** | Scheduled go-live once approved |

**Recommendation for 1.0: Manual.**

Two reasons specific to this launch. First, an iOS 27-GA-aligned launch means the
version may sit in **Pending Apple Release** anyway — Apple holds it until the
corresponding OS ships publicly. Second, manual release means approval and
go-live are separate events, so the support inbox, the published legal pages, and
whatever launch communication exists can all be confirmed working *after* Apple
says yes and *before* anyone can install.

---

## 4. Phased release — for updates, not for 1.0

Applies to **version updates only**, and only to users with automatic updates
enabled. Fixed 7-day curve:

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| **%** | 1 | 2 | 5 | 10 | 20 | 50 | 100 |

Two caveats that are easy to get wrong:

1. **Anyone can still download the new version manually from the App Store at any
   time**, regardless of the percentage. Phased release is a rollout throttle,
   **not a feature gate**. Do not use it as one.
2. **Removing the app from sale — including by letting the Developer Program
   membership lapse — permanently stops phased release for that version.** On
   reinstatement the version goes to **all users immediately**. To get a
   controlled rollout back you must make that version unavailable and submit a
   new one.

Controls: **pause** at any point, unlimited pauses, but **total paused time
cannot exceed 30 days**; **Release to All Users** jumps to 100%.

**Standing recommendation:** use phased release for every update that touches the
capture, transcription, or intelligence pipeline. With no server and no feature
flags, it is the only rollback lever short of an expedited hotfix.

---

## 5. Pre-orders — not recommended for 1.0

Available, but pre-order builds must be **complete and deliverable as submitted**
(Guideline 2.3.11), and material changes — including to the business model —
require restarting the pre-order. With `DEC-004` open, that is a trap. Revisit
for a later major version if there is a marketing reason.

---

## 6. Removing from sale

**Pricing and Availability → Remove App From Sale.** Takes effect in **all
territories within 24 hours**. Existing owners keep the app and keep receiving
updates. Restoring it later is supported. A specific *version* can also be made
unavailable for download without removing the app.

---

## 7. Post-launch operations

| Duty | Cadence | Owner |
|---|---|---|
| **Respond to App Store reviews** | Weekly. Requires Customer Support role or higher | ☐ user |
| **Support inbox** — `contact@sebastianmendo.design` | The support page promises a response; Guideline 1.5 requires the contact method to work | ☐ user |
| **Monitor first-time downloads against 2,000,000** and Small Business Program status | Every release. Crossing either starts a **6-month window** before Private Cloud Compute access is cut off. Exit paths in `06` §3 | `specs/021` R7 |
| **Re-read the App Review Guidelines changelog** before each submission | Per release. Last revision 2025-11-13 | agent |
| **Check `developer.apple.com/news/upcoming-requirements/`** | Per release. This is where the SDK minimum, the age-rating deadline, and the September 2026 social-media declaration were all announced | agent |
| **Renew the Developer Program membership** | Annual. A lapse removes the app from sale *and* permanently ends any phased release in flight | ☐ user |
| **Re-verify the published legal pages return 200** | Per release. This is the failure that has already bitten once | agent — `00` B1 |

---

## 8. Gate L exit criteria

- [ ] Status reaches **Ready for Distribution** and the app is actually
      purchasable — agreements in effect (`06` §2), not merely approved.
- [ ] Privacy policy, terms, and support pages all return **200** on the
      published host, and the in-app links reach them.
- [ ] The support mailbox receives and can reply to a test message.
- [ ] A purchase and a Restore Purchases both complete in production.
- [ ] The App Store product page shows the intended age rating, privacy label,
      screenshots, and description — read it as a user would, once, before
      telling anyone the app is out.

## Verification

- [ ] Price and tax category set; `DEC-004` recorded in `specs/021`.
- [ ] Territories match §2, with mainland China excluded and the EU decision
      applied.
- [ ] Release option is **Manual** for 1.0.
- [ ] Phased release is enabled for the first update, and the team knows it is
      not a feature gate.
- [ ] Every row in §7 has a named owner.
