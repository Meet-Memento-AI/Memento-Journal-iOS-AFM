# docs/app-store/ — App Store Connect submission and review readiness

**Compiled 2026-08-07** against Apple's published documentation. Target:
**Memento 1.0, iOS 27 GA, paid subscription, "Data Not Collected" privacy label.**

This folder is the **single source of truth for everything Apple requires before
Memento can be submitted, reviewed, and released.** It is the store-facing
counterpart to `specs/` — where `specs/` answers *"what does the app do and how
is it built,"* this library answers *"what does Apple require, what have we
declared, and what is still missing."*

Memento was submitted once, in **November 2025, and was rejected** on two
metadata grounds (Guidelines 5.1.2 and 1.5). **Both root causes are still live in
production as of 2026-08-07** — see `11-rejection-playbook.md`. This library
exists so that does not happen a third time.

---

## Two standing rules

**1. No secrets in this folder.** This repository is public
(`Meet-Memento-AI/Memento-Journal-iOS-AFM`). No reviewer PIN, no App Store
Connect API key or `.p8`, no mailbox credential, no provisioning profile. Where a
real value is needed, these files carry a placeholder and a pointer to where the
value lives.

**2. Every factual claim about Apple's rules carries a source URL and a
"checked on" date.** Apple's rules move — the App Review Guidelines were last
revised **2025-11-13**, the age-rating questionnaire changed in **2025**, and a
new required declaration lands in **September 2026**. A claim without a date is a
claim you cannot trust a year from now. When you re-verify one, update the date.

---

## The gate ladder

| Gate | Means | Entry criteria live in |
|---|---|---|
| **Gate T — TestFlight external** | A build passes Beta App Review and can go to external testers | `09-testflight.md`, plus the build half of `07-build-signing-and-upload.md` |
| **Gate S — Submit for Review** | Everything Apple requires is entered, declared, and true; the Submit button is safe to press | **`00-readiness-checklist.md`** — the one page |
| **Gate L — Live** | Approved, released, and operating | `10-release-and-availability.md` |

`specs/ROADMAP.md` carries **Gate S** as a row so store readiness is visible in
the same status board as the engineering phases. Gate S sits after Phase 5.

---

## The files

| File | Covers | Primary Apple sources |
|---|---|---|
| [`00-readiness-checklist.md`](00-readiness-checklist.md) | **Start here.** Every pre-Submit item, its owner, and its evidence | — (aggregates the rest) |
| [`01-review-guidelines-digest.md`](01-review-guidelines-digest.md) | The App Review Guidelines assessed against *this* app: verdict, evidence, residual risk, mitigation | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Nov 13 2025 changelog](https://developer.apple.com/news/?id=ey6d8onl) |
| [`02-app-store-connect-record.md`](02-app-store-connect-record.md) | Every field of the app record, with our value; roles; app and submission statuses | [App Information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) · [Role permissions](https://developer.apple.com/help/app-store-connect/reference/role-permissions/) |
| [`03-privacy-labels-and-manifest.md`](03-privacy-labels-and-manifest.md) | Nutrition label, `PrivacyInfo.xcprivacy`, required-reason APIs, third-party SDK obligations | [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) · [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) |
| [`04-metadata-and-assets.md`](04-metadata-and-assets.md) | Ready-to-paste name/subtitle/keywords/description/What's New, screenshot and icon specs | [Product page](https://developer.apple.com/app-store/product-page/) · [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) |
| [`05-age-rating-and-declarations.md`](05-age-rating-and-declarations.md) | Age rating, social-media declaration, export compliance, EU DSA trader status, content rights, accessibility labels | [Age ratings](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/) · [DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) |
| [`06-account-program-and-agreements.md`](06-account-program-and-agreements.md) | Enrollment, roles, Paid Apps Agreement + tax + banking, Small Business Program → PCC, entitlements | [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) · [Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements) |
| [`07-build-signing-and-upload.md`](07-build-signing-and-upload.md) | Archive → validate → upload, signing, ASC API key, the ITMS error playbook, version/build rules | [Submitting apps](https://developer.apple.com/app-store/submitting/) · [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) |
| [`08-app-review-information.md`](08-app-review-information.md) | The review-notes draft, contact fields, demo policy, attachments | [App Review Information](https://developer.apple.com/help/app-store-connect/reference/app-review-information/) |
| [`09-testflight.md`](09-testflight.md) | Internal vs external testing, Beta App Review, limits, expiry | [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) |
| [`10-release-and-availability.md`](10-release-and-availability.md) | Pricing, territories, release option, phased release, post-launch operations | [Overview of publishing](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store/) |
| [`11-rejection-playbook.md`](11-rejection-playbook.md) | Our rejection history, metadata vs binary rejection, Resolution Center, expedited review, appeals | [App Review](https://developer.apple.com/distribute/app-review/) |

Plus two data files:

| File | Purpose |
|---|---|
| [`metadata/en-US/*.txt`](metadata/en-US/) | The **paste-able App Store copy** — name, subtitle, keywords, promotional text, description, What's New, review notes. Kept as `.txt` so `scripts/ci/lint_forbidden_phrases.py` and `check_asc_metadata.sh` can check it, the same way the app's own strings are checked |
| [`last-uploaded-build.txt`](last-uploaded-build.txt) | Build numbers already consumed per version string. Read by `scripts/ci/check_store_metadata.sh` |

---

## How to use this library

1. Open `00-readiness-checklist.md`. Work top to bottom — it is ordered so that
   items on **Apple's clock** (agreements, program enrollments, entitlement
   requests, trader verification) come before items on **our clock**.
2. Rows marked **☐ user** can only be done by the Account Holder signed in to
   App Store Connect or developer.apple.com. An agent cannot close them; it can
   only prepare them and say exactly what to click.
3. When you close a row, record the **evidence** — a command and its output, a
   URL and its status code, a screenshot path. "Done" without evidence is how the
   support-URL row got ticked in July 2026 while the page was returning 404.
4. Anything that turns out to be an engineering change belongs in a numbered
   spec, not here. This library **cites** `specs/` and does not duplicate it.

---

## Relationship to `specs/`

| Concern | Owner |
|---|---|
| Pricing (`DEC-004`), Reduced-tier posture (`DEC-001`), StoreKit/RevenueCat integration, the **decision** on the privacy label (`REQ-MON-004` / V8) | `specs/021-monetization-and-store-compliance.md` |
| The positioning claim `REQ-POS-001` and the `TrustZone` disclosure UI | `specs/014-privacy-model-and-trust-boundary.md` |
| Small Business Program and Private Cloud Compute filings | `specs/013-phase-0-derisking-and-migration-prep.md` R5 |
| On-device transcription (`requiresOnDeviceRecognition`), Personal Voice posture | `specs/018-capture-and-voice-output.md` |
| Accessibility conformance that Accessibility Nutrition Labels would claim | `specs/020-system-integration-and-accessibility.md` R8 |
| Export and deletion (what a reviewer asks about instead of account deletion) | `specs/015-data-layer-swiftdata-cloudkit.md` `REQ-DATA-013` |
| **Everything Apple requires in App Store Connect, and whether we have it** | **this library** |

`specs/002-store-metadata-compliance.md` is **superseded** by this library. Its
completed binary-hygiene work remains valid and is recorded there; its App Store
Connect checklist has been migrated into `00-readiness-checklist.md` and
`02-app-store-connect-record.md`.

---

## A note on `docs/` being a published site

`docs/` is the GitHub Pages publishing root — `privacy.html`, `terms.html`,
`support.html`, and `index.html` are the public site linked from App Store
Connect and from inside the app. `docs/_config.yml` excludes `app-store/` so this
library is not served as web pages. That is a hygiene control, not a secrecy
control: the repository is public. See standing rule 1.
