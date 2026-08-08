# 06 — Developer account, program, and agreements

**Compiled 2026-08-07.** Everything upstream of the app record. These are the
items on **Apple's clock** — approval steps, verification delays, and review
queues we do not control — which is why `00` puts them first.

**Sources:** [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) ·
[Role permissions](https://developer.apple.com/help/app-store-connect/reference/role-permissions/) ·
[Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements) ·
[Provide tax information](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/) ·
[Certificates](https://developer.apple.com/support/certificates/)

---

## 1. Enrollment: individual

Memento is enrolled as an **individual** (team `F3NM4HTMW8`), not an
organization. Two consequences worth stating plainly:

**The seller name on the App Store is the developer's personal legal name.**
Individual enrollments cannot display a company name, alias, or trade name. If
"Memento" or a company name should appear as the seller, that requires an
Organization enrollment, which requires a legal entity and a **D-U-N-S number**.

**Guideline 5.1.1(ix).** Apps in highly regulated fields — banking and financial
services, **healthcare**, gambling, legal cannabis, air travel, crypto exchanges
— *"should be submitted by a legal entity that provides the services, and not by
an individual developer."* This is the constraint that makes the non-clinical
positioning in `01` §1.4.1 and `04` §3 load-bearing rather than stylistic.

| | Individual (us) | Organization |
|---|---|---|
| Seller name | Personal legal name | Legal entity name |
| D-U-N-S | Not required | **Required** (free) |
| Public website | Not required | **Required**, on the org's domain |
| Cost | $99/year | $99/year |
| Typical turnaround | 24–48 h `[secondary]` | 1–2 weeks `[secondary]` |

**When to reconsider Organization:** if the product ever wants health
positioning (`01` §1.4.1), or if the **EU DSA trader** decision (`05` §4) leads
to forming an entity anyway. Those two reasons point the same direction, so if
either arrives, do both at once.

### Phantom requirements — do not chase these

Two rules are widely misquoted as "new developer accounts must wait N days
before they can ship." **Neither applies to App Store distribution.**

1. **The two-year rule is for EU alternative distribution only** — Web
   Distribution and alternative marketplaces require an *organization*
   incorporated in the EU, membership in good standing for two continuous years,
   and >1M first annual EU installs. Irrelevant to the App Store.
2. **The device-registration lag is real but unrelated.** Apple documents that
   for *new* memberships, enabling registered test devices "may require
   additional processing for one month or more." This affects development and
   ad-hoc builds, not App Store or TestFlight submission.
3. The "12 testers for 14 days" rule people remember is **Google Play's**, not
   Apple's.

---

## 2. Agreements, tax, and banking — the silent release blocker

**Memento 1.0 is paid, so all three are required.** The failure mode is
distinctive: the app passes App Review, reaches **Ready for Distribution**, and
still does not go on sale, because *"To distribute your app, your agreements must
be in effect."*

| Item | Required for | Who |
|---|---|---|
| **Apple Developer Program License Agreement (PDLA)** | Everything. Accepted as part of membership | Account Holder |
| **Paid Apps Agreement** | Any paid app **or any in-app purchase**, including IAP in a free app | **Account Holder only.** Requires a 2FA code. **Cannot be undone** |
| **Tax forms** | Paid Apps. Every developer completes a **US** form regardless of country: **W-9** if US-based, or the questionnaire routes to **W-8BEN** (individual) | Account Holder / Finance |
| **Banking** | Paid Apps. Account in the name of the individual on the agreement | Account Holder / Finance |

**Two failure modes to watch for:**

- Status **"Pending Agreement"** means an unsigned agreement or incomplete tax or
  banking information. The app cannot go on sale.
- When Apple publishes a **new version** of the Paid Apps Agreement, you
  **cannot create new apps or new in-app purchases** until you accept it. This
  is the same class of blocker as the **Program License Agreement update that has
  been blocking archive signing since 2026-07-13** (`00` A1) — an unaccepted
  agreement silently breaks tooling that looks unrelated.

**Sequencing note:** the Paid Apps Agreement is also a prerequisite for the Small
Business Program (§3), which is a prerequisite for Private Cloud Compute access,
which is a prerequisite for the architecture. Sign it early.

---

## 3. Small Business Program → Private Cloud Compute

**This is not a commission perk. It is the eligibility condition for the
architecture.** The chain, from `specs/reference/technology/10-monetization-and-privacy.md` §1:

> SBP enrollment → fewer than 2M first-time downloads → approved PCC access
> application → free PCC inference → no server tier.

Break any link and the economics and the design both change.

The filing process is **already researched and recorded in `specs/013` R5** —
cite it, do not re-derive it. Summary:

**(a) Small Business Program.** Eligibility: ≤$1M USD in prior-calendar-year
proceeds, **or new to the App Store** — Memento qualifies either way pre-launch.
Requires being the Account Holder, accepting the Paid Apps Agreement (Schedule
2), and disclosing Associated Developer Accounts. Apple's marketing copy calls it
"about five minutes"; Apple's program terms elsewhere describe an **approval**
step with commission changes taking effect 15 days after the end of the fiscal
month of approval. **File first, immediately** — it is free and it gates (b).

**(b) Private Cloud Compute access.** A **separate, explicit request** at
`developer.apple.com/contact/request/private-cloud-compute/`. It does not happen
automatically on SBP enrollment. Eligibility: SBP enrolled, fewer than 2,000,000
first-time downloads, and the PCC entitlement assigned to the account.
**Apple states no lead time anywhere** — a confirmed documentation gap, and the
least controllable dependency in the project. File the moment (a) confirms.

**(c) Journaling Suggestions.** Previously assumed to need a filing;
`specs/013` R5 research concluded it is a **standard Xcode-addable capability**
(`com.apple.developer.journal.allow`, Signing & Capabilities → "+ Capability" →
Journal) with no request form. 🟡 confidence. Confirm with one click when spec
018 R4 is picked up; if Xcode surfaces an approval prompt instead, the research
was wrong and it becomes a real filing.

### The standing operational duty

This is **not a one-time filing**. Crossing **2,000,000 first-time App Store
downloads**, or letting SBP enrollment lapse — *including by exceeding the $1M
prior-year proceeds cap, i.e. by succeeding* — starts a **6-month migration
window** before PCC access is cut off. TestFlight and ad-hoc installs do not
count toward the threshold.

The exit paths are already specified elsewhere and are cited, not invented: pin
all routing to Z0 (`specs/017` R2's `REQ-INT-004` override, degraded but honest
per `specs/014` R2), or move to a paid provider through `specs/017` R7's
`REQ-INT-015` escape hatch — which has privacy-label and marketing-copy
consequences (`REQ-INT-016`).

**Monitoring belongs on the release checklist:** check download count and SBP
status at every release. `specs/021` R7 owns this.

---

## 4. Entitlements

Current entitlement surface — `MeetMemento/MeetMemento.entitlements` contains
**exactly one** entry:

```xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.sebastianmendo.MeetMemento</string>
</array>
```

That is all. No iCloud, no CloudKit, no HealthKit, no Sign in with Apple (removed
by spec 023), no push, no background modes, no App Groups, no associated domains.

| Entitlement | Lead time | Needed by | Status |
|---|---|---|---|
| **Private Cloud Compute** | 🔴 **Unknown — Apple states none** | The whole Z1 architecture | ☐ Unfiled — `00` A4 |
| **CloudKit** | None | `specs/015` data layer | ☐ Not yet added |
| **Journaling Suggestions** | Likely none (🟡) | `specs/018` R4 | ☐ Confirm in Xcode |
| Background modes (audio, processing) | None | Long capture, if it ships | ☐ Not yet added — note Guideline 2.5.4 (`01`) |
| Siri / App Intents | None | `specs/020` R1 | ☐ Not yet added |
| HealthKit | None, **but review scrutiny** | Only if `DEC-006` says yes | ⛔ Recommend not |
| WeatherKit | None, quota-limited | `specs/018` R6 | ☐ Optional |
| Push (local notifications only) | None | Reminders, if they ship | ☐ Not yet added |

**Every entitlement added here changes three other things**: the App ID's
capabilities in the developer portal, the provisioning profile (regenerate), and
potentially the privacy manifest and label. Adding one without the others is the
root cause of most `ITMS-90xxx` entitlement errors — see `07`.

**HealthKit carries extra weight:** it activates Guideline 5.1.3, including the
prohibition on storing personal health information in iCloud, which directly
constrains the CloudKit mirroring in `specs/015`. `DEC-006`'s conservative
default (exclude entirely) is also the lowest-review-risk answer.

---

## 5. Certificates, identifiers, and profiles

| Asset | Rule | Ours |
|---|---|---|
| **App ID** | Explicit, matching the bundle ID. Capabilities must be enabled **on the App ID**, not only in Xcode | `com.sebastianmendo.MeetMemento` |
| **Apple Distribution certificate** | Belongs to the *team*, used for TestFlight and App Store. **Account Holder or Admin only.** Apple documents one per team; tooling docs commonly cite up to three | ☐ Verify one exists and is not expiring |
| **App Store provisioning profile** | Must reference the distribution certificate and the App ID with matching capabilities | Automatic signing manages it |
| **Signing style** | `CODE_SIGN_STYLE = Automatic`, no `PROVISIONING_PROFILE_SPECIFIER` | ✅ Fine for Xcode Organizer; insufficient for headless CI — see `07` |

**Revoking a distribution certificate invalidates every provisioning profile that
references it.** Never revoke casually.

---

## 6. App Store Connect API key — for CI

Needed to move uploads off manual Xcode Organizer runs (`07`).

- **Users and Access → Integrations → App Store Connect API.**
- **Only the Account Holder can create Team keys.** Use a **Team** key, not an
  Individual key — `altool` historically did not support Individual keys for
  uploads.
- Assign the narrowest workable role (App Manager is enough to upload and submit).
- You receive an **Issuer ID**, a **Key ID**, and `AuthKey_<KeyID>.p8`.
- **The `.p8` is downloadable exactly once.** Apple keeps no copy. Lose it and
  you revoke and recreate.

**Storage:** outside this repository, which is public. A password manager or the
CI secret store. `.p8` files must be in `.gitignore`. Never in `docs/app-store/`
— standing rule 1 in the README.

---

## Verification

- [ ] Program License Agreement accepted; archive signing succeeds (`00` A1).
- [ ] Paid Apps Agreement signed; tax form completed; banking entered. App Store
      Connect shows no "Pending Agreement" state.
- [ ] Small Business Program filing date recorded in `specs/013` R5.
- [ ] Private Cloud Compute access request filing date recorded in `specs/013`
      R5, with any stated lead time.
- [ ] Journaling Suggestions confirmed as an Xcode-addable capability (or the
      research corrected and a real filing made).
- [ ] Every entitlement in the shipping `.entitlements` is enabled on the App ID
      and present in the provisioning profile.
- [ ] One valid, non-expiring-soon Apple Distribution certificate exists.
- [ ] An App Store Connect **Team** API key exists; the `.p8` is stored outside
      the repository; `git ls-files | grep -c "\.p8$"` → **0**.
- [ ] The SBP / 2M-download monitoring duty is on the release checklist
      (`specs/021` R7).
