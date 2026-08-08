# 09 — TestFlight (Gate T)

**Compiled 2026-08-07.**
**Sources:** [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) ·
[Export compliance for beta builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds)

TestFlight is **Gate T** — the rehearsal for Gate S. External TestFlight goes
through **Beta App Review**, which applies the same App Review Guidelines with
more tolerance for incompleteness. Anything Beta App Review objects to would
certainly have failed the real review.

---

## 1. Internal vs external

| | Internal | External |
|---|---|---|
| Who | Up to **100** App Store Connect users with the right role | Up to **10,000** people, by email invite or **public link**; no App Store Connect account needed |
| Beta App Review | **Not required** — available as soon as processing completes | **Required for the first build of each version** |
| Devices per tester | Up to 30 | — |
| Build lifetime | **90 days from upload**, then unavailable to testers | Same |

**Plan:** internal first (the developer's own devices), to confirm the build
installs and the core loop works on real hardware — several spec 013 gate items
need a physical iOS 27 device with Apple Intelligence anyway. Then external, to
exercise Beta App Review before the real submission.

---

## 2. Beta App Review

*"When you add the first build of your app to a group, the build gets sent to
App Review… A review is required only for the first build. Subsequent builds may
not require a full review."*

**What re-triggers a full review on a later build:**

- Changes to **export compliance** answers
- Changes to **entitlements** — push, in-app purchase, Family Sharing, CloudKit,
  HealthKit
- Changes to the **privacy nutrition label**
- **New purpose strings** in `Info.plist`
- Edits to the **beta app description** or **What to Test**

Every one of those is on Memento's roadmap: CloudKit and PCC entitlements
(`06` §4), the label decision (`03`), and photo/location purpose strings if specs
018 R5/R6 land. **Expect more than one Beta App Review**, and do not schedule as
if the first approval covers the beta period.

**Timing:** historically about 24 hours; 2025/2026 reports run **2–7 days** for
external review, with AI features, payment SDKs, and new permission strings
extending the wait. `[secondary]`

**If a TestFlight build is rejected:** you must submit a **new build** for review
before you can invite external testers. There is no metadata-only path here.

---

## 3. Required TestFlight metadata

| Field | Notes |
|---|---|
| **Beta App Description** | What the app does. Editing it re-triggers review |
| **What to Test** | Per build. Keep it specific — it doubles as the reviewer's orientation |
| **Feedback email** | `contact@sebastianmendo.design` |
| **Beta App Review contact** | Name, phone, email — same as `08` §1 |
| **Demo account** | **None needed** — no login. Say so, as in `08` |
| **Export compliance** | Answered per build **unless** `ITSAppUsesNonExemptEncryption` is in `Info.plist`. ✅ It is — so the prompt does not appear |

The `08` review-notes draft works nearly verbatim as the beta review notes. The
empty-app problem (`08` §3) applies identically: a tester or beta reviewer
installing cold sees no entries.

---

## 4. Rules

- **Guideline 2.2** — betas belong on TestFlight, not the App Store, and you may
  **not compensate testers**, including via crowdfunding rewards. Relevant to
  `specs/022`'s 30-day quality study: recruit participants, do not pay them for
  testing.
- **TestFlight installs do not count** toward the 2,000,000 first-time-download
  threshold that governs Private Cloud Compute eligibility (`06` §3).
- Builds not expired before App Store release remain testable by invited testers
  after launch — expire them deliberately if you do not want that.
- Managed Apple Accounts in reserved domains cannot test.

---

## 5. Gate T entry criteria

Everything needed to get a build to external testers:

- [ ] Program License Agreement accepted (`00` A1) — archive signing works.
- [ ] Build archives, exports, and passes `altool --validate-app` with zero ITMS
      errors (`07`).
- [ ] `CURRENT_PROJECT_VERSION` ≥ 3 (`07` §2).
- [ ] Privacy manifest correct (`03`) — the label and manifest are inputs to
      Beta App Review.
- [ ] Beta app description, What to Test, and feedback email entered.
- [ ] Beta App Review contact entered; demo-account absence explained.
- [ ] A cold-install path to the core experience exists (`08` §3) — testers hit
      the same empty-app wall reviewers do, and it is the single thing most
      likely to make beta feedback useless.

## Verification

- [ ] A build reaches internal testers and installs on a physical iOS 27 device
      with Apple Intelligence.
- [ ] The first external build passes Beta App Review; the date and duration are
      recorded here for future planning.
- [ ] No export-compliance prompt appears on upload (confirms
      `ITSAppUsesNonExemptEncryption` is reaching the built product).
- [ ] At least one tester who is not the developer completes capture →
      transcription → reflection without being told how.
