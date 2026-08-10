# 00 — Readiness checklist (Gate S)

**Compiled 2026-08-07.** This is the one page you work down before pressing
**Submit for Review**. Every row is either closed with evidence or names the
owner and what is blocking it.

- **Owner `agent`** — closeable from the repo by an implementation session.
- **Owner `☐ user`** — requires the **Account Holder** signed in to App Store
  Connect or developer.apple.com. An agent can prepare it and say exactly what to
  click; it cannot close it.
- **Evidence** — a command and its output, a URL and its status code, or a file
  path. A row without evidence is not closed. In July 2026 the support-URL row
  was ticked while the page was returning 404; that is the failure mode this
  column exists to prevent.

---

## Section A — Apple's clock (do these first)

These have review queues, approval steps, or verification delays that we do not
control. Everything else can be done in an afternoon; these cannot.

| # | Item | Owner | Blocks | Status / evidence |
|---|---|---|---|---|
| A1 | **Accept the current Program License Agreement** at developer.apple.com. Archive signing has been failing on a pending PLA since 2026-07-13. | ☐ user | Gate T | ☐ Open — `specs/002` Task 8 blocked on this since 2026-07-13 |
| A2 | **Sign the Paid Apps Agreement** (Business → Agreements), complete **tax forms** (W-9 or W-8BEN) and **banking**. Account Holder only, requires 2FA, cannot be undone. Without all three the app **cannot go on sale even after App Review approves it**. | ☐ user | Gate L | ☐ Open — required because 1.0 is paid. See `06`. |
| A3 | **Enroll in the App Store Small Business Program.** This is the eligibility gate for A4 and therefore for the entire Z1 architecture, not a commission perk. | ☐ user | Gate S (architecture) | ☐ Open — process researched in `specs/013` R5(a); filing date not yet recorded |
| A4 | **File the Private Cloud Compute access request** at `developer.apple.com/contact/request/private-cloud-compute/`. Separate, gated, and **Apple states no lead time anywhere** — this is the least controllable dependency in the project. | ☐ user | Gate S (architecture) | ☐ Open — `specs/013` R5(b); file immediately after A3 confirms |
| A5 | **Declare EU Digital Services Act trader status** and pass email + phone verification. Required since 2025-02-17; apps without it are **removed from the App Store in all 27 EU territories**. See `05` — this is a *decision*, because an individual developer's address and phone are **published on the EU product page**. | ☐ user | Gate S | ☐ Open — decision not yet made |
| A6 | **Enable GitHub Pages** on `Meet-Memento-AI/Memento-Journal-iOS-AFM`, source `main` → `/docs`. The live legal site is currently served from a *different* repo (`sebmendo1/MeetMemento` @ `Memento-v1.1`), which is why fixes committed here never reached production. | ☐ user | Gate S | ☐ Open — `gh api repos/Meet-Memento-AI/Memento-Journal-iOS-AFM/pages` → 404 (2026-08-07) |
| A7 | **Answer the updated age-rating questionnaire** (5-tier scale: 4+/9+/13+/16+/18+). Was due 2026-01-31; unanswered apps are blocked from submitting. | ☐ user | Gate S | ☐ Open — worked answers in `05` |
| A8 | **Answer the social-media capability declaration.** New in the July 2026 questionnaire; **required to submit new versions or updates from September 2026**. Our answer is "no". | ☐ user | Gate S | ☐ Open — becomes mandatory within weeks of this document's date |

---

## Section B — The three live rejection risks

Each of these is a defect that exists **right now in production or in the
binary**, and each maps to a guideline Apple has already rejected us on or would
reject us on.

| # | Item | Owner | Guideline | Status / evidence |
|---|---|---|---|---|
| B1 | **The Support URL returns 404.** `https://sebmendo1.github.io/MeetMemento/support.html` → HTTP 404; the live index links only privacy and terms. This is the *exact* reason Apple cited in November 2025. `docs/support.html` exists in this repo but has never been published (see A6). | agent + ☐ user | **1.5**, 2.1 | 🔴 **Live defect** — `curl -o /dev/null -w "%{http_code}" …/support.html` → `404` (2026-08-07) |
| B2 | **The live privacy policy describes third-party AI and a backend the app no longer uses.** The published page at `https://sebmendo1.github.io/MeetMemento/privacy.html` names **OpenAI, Google, and Supabase**. The app is on-device only. `PRIVACY_POLICY.md` at the repo root is equally stale (it has a "Google Gemini 2.5 Flash" section). `docs/privacy.html` in this repo *is* clean — it just was never published. | agent + ☐ user | **5.1.1(i)**, **5.1.2(i)**, 2.3 | 🔴 **Live defect** — `curl -s …/privacy.html \| grep -io "gemini\|supabase\|openai"` → matches (2026-08-07) |
| B3 | **`PrivacyInfo.xcprivacy` declared `NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`) for an API the app never calls.** No `systemUptime`, `mach_absolute_time`, or `kern.boottime` anywhere in `MeetMemento/`. Over-declaring is an unforced inaccuracy in exactly the metadata category we were rejected on. | agent | **5.1.2**, ITMS-91055 | ✅ **Fixed 2026-08-07** — block removed; `scripts/ci/check_privacy_manifest.sh` now fails on both over- and under-declaration |
| B4 | **The published privacy policy will become an overclaim when Z1 ships.** `docs/privacy.html` (the corrected version, not yet published) says content is *"processed on the device and are not sent to us or to any third-party AI service"* and makes no mention of **Private Cloud Compute**. That is accurate today, because no Z1 routing has shipped — and becomes false the moment `specs/017`'s PCC path lands. `REQ-POS-001` governs app strings and store copy; the privacy policy is the one place making the same claim *legally*. | agent | **5.1.2(i)**, `REQ-POS-001` | 🟠 **Open** — must be rewritten to state the Z0/Z1 boundary **before** PCC routing ships, not after. `01` §5.1.1(i) has the required content |
| B5 | **A third, older privacy policy is what users actually see.** `PRIVACY_POLICY.md` (repo root) describes Gemini and Supabase; the **live** page describes OpenAI, Google, and Supabase; `docs/privacy.html` is correct but unpublished. Three versions, one of them served. | agent + ☐ user | **5.1.1(i)** | 🟠 Root markdown banner-flagged 2026-08-07; resolution is A6 (publish) |

> **Already fixed, do not redo:** `NSPrivacyCollectedDataTypes` is now an **empty
> array** with an on-device-only comment — the stale EmailAddress / Name / UserID
> / UserContent entries are gone. `NSPrivacyAccessedAPICategoryFileTimestamp`
> (`C617.1`) is **correctly justified** by
> `MeetMemento/Services/LocalJournalStorage.swift:118-121`
> (`attributesOfItem` → `.modificationDate` on files inside the app container).
> `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) is justified by 11 call
> sites. `ITSAppUsesNonExemptEncryption = false` is present in `Info.plist`.

---

## Section C — Binary and project

| # | Item | Owner | Status / evidence |
|---|---|---|---|
| C1 | Bump the build number past the consumed `1.0(2)`. | agent | ✅ **Done 2026-08-07** — `CURRENT_PROJECT_VERSION` 2 → **3**. Floor recorded in `last-uploaded-build.txt`, enforced by `check_store_metadata.sh` |
| C2 | **Deployment target stays at `IPHONEOS_DEPLOYMENT_TARGET = 26.0`. Do not bump it.** | agent | ✅ **Correct as-is (2026-08-08)** — see below |
| C3 | Built with **Xcode 26 or later** using an iOS 26+ SDK — mandatory for uploads since **2026-04-28**. **Archive with the release Xcode (26.0.1), not the Xcode 27 beta.** | agent | ✅ Toolchain available — `xcodebuild -version` → **Xcode 26.0.1 (17A400)**, GA. Verify at archive time |
| C4 | `requiresOnDeviceRecognition` — `SFSpeechRecognizer` is used without it, so audio may leave the device, contradicting the positioning claim CI lints for. Either set it, migrate to `SpeechAnalyzer` per spec 018 R1, **or disclose the off-device path** per 5.1.2(i). | agent | ✅ **Fixed in code** (flag set unconditionally); docs updated 2026-08-10 in `03` |
| C5 | Submission noise removed: `Configuration.storekit` with placeholder product IDs `12345678`/`123456789`; dead `SubscriptionPlan.swift` with Supabase-era `CodingKeys`; linked-but-unused `AuthenticationServices.framework`; unhandled `memento://` URL scheme; orphan `GoogleIcon.imageset`. | agent | 🟠 **Partial 2026-08-10** — `SubscriptionPlan.swift`, `GoogleIcon.imageset`, `AuthenticationServices.framework` reference, and `memento://` removed; `Configuration.storekit` still excluded from target (report-only until `DEC-004`) |
| C6 | Release bundle contains only shipping resources — no xcconfigs, no `.storekit`, no internal docs. | agent | 🟠 **Regression found and fixed 2026-08-07** — `Config/Debug.xcconfig` and `Config/Release.xcconfig` had **dropped out** of the synchronized-group `membershipExceptions` set during the Supabase decommission, so they would have shipped in the bundle. Exactly spec 002 finding #7 recurring. Re-added; now guarded by `check_archive_hygiene.sh`. **Still re-verify on the actual archive** — the check reads the project file, not the built product |
| C7 | Usage-description strings are specific and defined exactly once. Apple's own common-rejection #6 is vague purpose strings. | agent | ✅ Present in `Info.plist`; wording review in `02` |
| C8 | App icon is 1024×1024 PNG, opaque, no alpha, square corners. | agent | ✅ `AppIcon.png` (spec 002 Task 2); dark/tinted variants deliberately absent — design TODO |
| C9 | A reviewer opening the app for the first time can reach the core experience. **>40% of unresolved App Review issues are Guideline 2.1**, and the reviewer will open an empty journal with no meeting to record. | agent | ☐ Open — seeded-sample decision in `01` §2.1 |

### ⚠️ Do not target iOS 27, and do not archive with the beta toolchain

**Corrected 2026-08-08.** Rows C2 and C3 previously instructed a bump to iOS
27.0 and named the Xcode 27 beta as the archive toolchain. **Both were wrong and
would have made the app unsubmittable.**

- **iOS 27 has not shipped GA.** Every reference in this repository is to *Xcode
  27 beta 4 (27A5228h)* and the iOS 27.0 SDK. **Apple does not accept App Store
  builds made with beta software**, so a build targeting iOS 27 cannot be
  submitted, and one archived with the beta Xcode will be rejected at upload
  regardless of its deployment target.
- **The release toolchain already satisfies Apple's floor.** `xcodebuild
  -version` → **Xcode 26.0.1 (17A400)**, GA, shipping the iOS 26.0 SDK — which
  meets the "Xcode 26 / iOS 26 SDK or later" requirement in force since
  2026-04-28.
- **`REQ-PLAT-001` (iOS 27.0 deployment target) is a Memento 2.0 requirement,
  not a 1.x one.** It becomes actionable only after Apple ships iOS 27 publicly
  *and* Xcode 27 reaches GA. Until then the 2.0 architecture — Core Spotlight
  retrieval, PCC/Z1 routing, SwiftData + CloudKit — is unshippable by
  construction.

The project targets **26.0 in all four build configurations**, which is correct
and should stay that way. `scripts/ci/check_store_metadata.sh` does **not**
currently assert this; if a future session bumps it speculatively, nothing will
catch it — treat this note as the guard.

**Addressable-market consequence, recorded deliberately:** iOS 26.0 plus the
Apple Intelligence hardware requirement (A17 Pro / M-series) for the generative
surfaces is a narrow install base. The code handles it correctly —
`SystemLanguageModel.default.availability` returning `.unavailable(.deviceNotEligible)`
yields a designed empty state, while capture, voice, timeline, search, and
export keep working. **That is `DEC-001` Option A, already implemented**; see
`05` and record it in `specs/021` R2 rather than leaving the decision open.

---

## Section D — App Store Connect record

| # | Item | Owner | Status / evidence |
|---|---|---|---|
| D1 | Privacy Policy URL — required for **all** apps, must be reachable without login **and** from inside the app. | ☐ user | Blocked on A6 + B2 |
| D2 | Support URL — required, must be live. | ☐ user | Blocked on A6 + B1 |
| D3 | Support email standardized on **`contact@sebastianmendo.design`** (the developer-account address, already verified with Apple). Three addresses are currently in circulation. | agent + ☐ user | ☐ Open — update `AboutSettingsView.swift:259`, `DataUsageInfoView.swift:232`, `docs/support.html` |
| D4 | Categories: primary **Lifestyle**. Do **not** choose Health & Fitness or Medical — see `01` on 1.4.1 / 5.1.1(ix). | ☐ user | ✅ In project (`public.app-category.lifestyle`); confirm in ASC |
| D5 | Copyright string, content rights declaration, licence agreement. | ☐ user | ☐ Open — values in `02` |
| D6 | App Privacy nutrition label set to the target and **matching `PrivacyInfo.xcprivacy` and the privacy policy**. The label is editable without a build, which is exactly how it drifted last time. | ☐ user | ☐ Open — `03` |
| D7 | App Review Information: contact name/email/phone, notes, attachments. No demo account needed (no login) — but the notes must **say so**. | ☐ user | ☐ Open — ready-to-paste draft in `08` |
| D8 | Metadata: name, subtitle, keywords, promotional text, description, What's New — all within limits and compliant with `REQ-POS-001`. | agent + ☐ user | ☐ Open — drafts in `04` |
| D9 | Screenshots: **iPhone 6.9″ (1320×2868)** and **iPad 13″ (2064×2752)**. iPad is mandatory because `TARGETED_DEVICE_FAMILY = "1,2"`. | ☐ user | ☐ Open — `04` |
| D10 | Price and **tax category** — both required before submission. | ☐ user | 🔒 Blocked on `DEC-004` (spec 021) |
| D11 | Availability / territories, including the EU decision from A5 and the recommendation to exclude mainland China. | ☐ user | ☐ Open — `10` |
| D12 | Release option — **Manual** recommended for 1.0. | ☐ user | ☐ Open — `10` |

---

## Section E — Product decisions that gate the record

These are not checklist items an agent can close. They are open decisions whose
resolution unblocks rows above.

| Decision | Owner | Gates |
|---|---|---|
| `DEC-004` — final price and trial length | `specs/021` R1 | D10, the paywall, all ASC product configuration |
| `DEC-001` — ship on non-Apple-Intelligence (Reduced-tier) devices? | `specs/021` R2 | The device-requirement declaration and the paywall-presentability rule (`REQ-PLAT-004`) |
| **V8** — does RevenueCat's SDK force a collection disclosure? | `specs/021` R5/R8 | D6, and whether RevenueCat's privacy manifest + signature obligation attaches (`03` §3) |
| **EU trader status** — registered business address, or exclude the EU? | ☐ user | A5, D11 |
| **Seeded demo content** — what does a reviewer see on first launch? | ☐ user + agent | C9, D7 |

---

## Section F — What CI already guards

Four gates in `.github/workflows/spec-gates.yml` enforce the machine-checkable
half of this library continuously, so it cannot silently rot between releases.
Each was verified to **fail on a planted violation** before being wired.

| Gate | Enforces | Mode |
|---|---|---|
| `scripts/ci/check_privacy_manifest.sh` | Every required-reason API declared in `PrivacyInfo.xcprivacy` has a call site, **and every call site is declared**. Plus `NSPrivacyTracking = false`, empty `NSPrivacyCollectedDataTypes`, and no `NSUserTrackingUsageDescription` anywhere | Blocking |
| `scripts/ci/check_store_metadata.sh` | `ITSAppUsesNonExemptEncryption` present; usage strings present, specific, and defined exactly once; no `com.testing.*` bundle ids; build number above the recorded floor | Blocking |
| `scripts/ci/check_archive_hygiene.sh` | Every doc, config, and fixture under `MeetMemento/` is individually excluded from the target. Placeholder StoreKit product ids reported | Blocking; StoreKit half **report-only** until `DEC-004` |
| `scripts/ci/check_asc_metadata.sh` | Field character/byte limits; `REQ-POS-001`; no pricing or accuracy claims; no clinical vocabulary | Blocking |

Making them **required** status checks is a branch-protection setting —
`docs/BRANCH_PROTECTION_SETUP.md`.

**What CI cannot check, and why the ☐ user rows above exist:** whether a URL
returns 200 in production, whether a mailbox receives mail, whether an
agreement is signed, whether Apple approved a filing, or whether the App Store
Connect privacy label matches the manifest. Those need evidence, not a script.

---

## Do not press Submit until

1. `curl` returns **200** for `privacy.html`, `terms.html`, `support.html`, and
   `index.html` on the *published* host, and the App Store Connect URLs point at
   that host. **(B1, B2, A6)**
2. The published privacy policy describes the app that actually exists — no
   OpenAI, no Google, no Supabase — and states the on-device / Private Cloud
   Compute boundary in the words `specs/014` uses. **(B2)**
3. `PrivacyInfo.xcprivacy`, the App Store Connect privacy label, and the privacy
   policy **all say the same thing**. **(B3, D6)**
4. `xcodebuild archive` → `-exportArchive` → `altool --validate-app` completes
   with **zero ITMS errors**. **(C1–C6, `07`)**
5. A reviewer who launches the app cold can reach capture → transcription →
   reflection without an account, and the review notes tell them how. **(C9, D7)**
6. The Paid Apps Agreement, tax forms, and banking are all in effect. **(A2)**
7. Age rating and the social-media declaration are answered. **(A7, A8)**
8. EU trader status is declared and verified, or the EU is deselected. **(A5)**
