# 01 — App Review Guidelines, assessed against Memento

**Source:** https://developer.apple.com/app-store/review/guidelines/
**Guidelines last revised by Apple:** 2025-11-13 ([changelog](https://developer.apple.com/news/?id=ey6d8onl))
**This assessment compiled:** 2026-08-07

Apple's own framing: *"This is a living document; new apps presenting new
questions may result in new rules at any time."* Re-read the changelog before
each submission.

This document does not reproduce all five sections clause by clause. It gives a
**full assessment — verdict, evidence, residual risk, mitigation — for the
guidelines that actually bite this app**, and a one-line verdict for the rest.

---

## The November 13, 2025 changelog

Verbatim, because two of these are directly about us:

- **1.2.1(a)** — creator apps must let users identify content exceeding the app's
  age rating, using an age restriction mechanism based on verified or declared age.
- **2.5.10** — deleted.
- **3.2.2(ix)** — loan apps: max 36% APR, no ≤60-day full repayment.
- **4.1(c)** — **new:** *"you cannot use another developer's icon, brand, or
  product name in your app's icon or name, without approval from the developer."*
- **4.7** — clarifies that HTML5/JavaScript **mini apps and mini games** are in scope.
- **4.7.2** — apps offering software not embedded in the binary may not extend or
  expose native platform APIs to that software without prior Apple permission.
- **4.7.5** — such apps must provide age-rating identification and an age
  restriction mechanism.
- **5.1.1(ix)** — adds **crypto exchanges** to the highly-regulated-fields list.
- **5.1.2(i)** — **"Clarifies that you must clearly disclose where personal data
  will be shared with third parties, including with third-party AI, and obtain
  explicit permission before doing so."** ← the AI amendment. See §5.1.2 below.

---

## Residual risk register, ranked

| Rank | Guideline | Risk | Mitigation owner |
|---|---|---|---|
| 1 | **2.1** | Reviewer opens an empty journal with nothing to reflect on and rejects for incompleteness. >40% of unresolved issues are 2.1. | This doc §2.1 + `08` |
| 2 | **1.5 / 2.1** | Support URL is **404 in production today**. Already rejected on this once. | `00` B1 |
| 3 | **5.1.1(i) / 5.1.2(i)** | Published privacy policy names **OpenAI, Google, Supabase** — third-party AI the app does not use. | `00` B2 |
| 4 | **5.1.2(i)** | `SFSpeechRecognizer` without `requiresOnDeviceRecognition` is an undisclosed off-device path. | `specs/018` R1 |
| 5 | **2.5.14** | Recording without a clear, persistent visual indication. | `specs/018` / `020` |
| 6 | **1.4.1 / 5.1.1(ix)** | Mental-health framing by an **individual** developer account. | This doc §1.4.1 |
| 7 | **4.10** | Paywall copy that reads as selling access to Apple Intelligence. | `specs/021` R4 |
| 8 | **2.4.2** | Sustained on-device inference during long capture drains battery / heats the device. | This doc §2.4.2 |

---

# Section 1 — Safety

## 1.2 User-Generated Content — **verdict: N/A today, with a hard trip-wire**

Apple requires four mechanisms of any app with UGC or social networking: a
filter for objectionable material, a report mechanism with timely response, the
ability to block abusive users, and published contact information.

**Why it does not apply.** Memento has no other users. Entries are private and
on-device; there is no feed, no comments, no shared workspace, no public link, no
server-side representation of any entry. The only outbound surfaces are a
user-driven `UIActivityViewController` share sheet
(`MeetMemento/Views/Settings/SettingsView.swift:274-292`) and clipboard copies
(`AIChat/AIOutputComponent.swift:181`, `AboutSettingsView.swift:253`). Those are
the user exporting their own words, not publishing to a service.

**Trip-wire — the moment any of these ship, 1.2 attaches in full:** shared
entries, public transcript links, team or family spaces, comments, a community
gallery of prompts. There is no partial version of 1.2; the filter/report/block/
contact quartet arrives together.

**Residual risk.** Some reviewers treat *generative model output* as content
requiring a reporting path, even when there is only one user. This is cheap
insurance and worth shipping regardless: a **"Report a problem with this
response"** affordance on every generative surface (weekly, monthly/Patterns,
Ask), routing to `contact@sebastianmendo.design`. It also strengthens the 1.4.1
posture below by demonstrating that objectionable output has a defined escalation
path.

**Acceptance:** either no sharing surface exists (asserted structurally — no
module outside export depends on a network or publish path), or the four
mechanisms ship together. A "Report a problem" affordance exists on each
generative surface.

---

## 1.4.1 Physical Harm + 5.1.1(ix) Highly Regulated Fields — **verdict: the line that must not be crossed**

These are two guidelines but one risk, so they are assessed together.

- **1.4.1** — medical apps receive heightened scrutiny and must disclose the data
  and methodology supporting any accuracy claim.
- **5.1.1(ix)** — apps in highly regulated fields (banking and financial
  services, **healthcare**, gambling, legal cannabis, air travel, crypto
  exchanges) *"should be submitted by a legal entity that provides the services,
  and not by an individual developer."*

**Memento is enrolled as an individual.** That is fine for a journaling and
personal-productivity app. It is a rejection risk for anything that reads as a
mental-health product.

This makes the existing NON-GOAL — *"no therapeutic advice, diagnosis, or
treatment framing; archivist persona, enforced by evaluation"*
(`specs/reference/technology/10-monetization-and-privacy.md` §8) — **not a
product-design preference but the thing that keeps this app out of 5.1.1(ix)**.
It is a hard constraint on three surfaces simultaneously:

1. **The App Store description and subtitle** (`04`) — no "therapy", "mental
   health", "wellbeing coach", "heal", "anxiety", "depression". Reflection,
   memory, journaling, patterns, recall.
2. **The paywall and marketing copy** — same.
3. **The archivist system prompt** (`docs/prompts/MEMENTO_SYSTEM_PROMPT.md`) — the
   model observes and recalls; it does not advise, diagnose, or recommend
   treatment.

Note that this is also what keeps the **age rating** at 9+ rather than 13+/16+ —
see `05`. The rating and the 5.1.1(ix) exposure are driven by the same property,
so they move together.

**Crisis content.** `REQ-SUR-004` (spec 019) specifies a static, respectful,
region-appropriate resource card, never generated counseling. Keep it static:
a generated crisis response is exactly the artifact that converts this app into a
healthcare app in a reviewer's reading.

**Acceptance:** a grep over App Store metadata, paywall copy, and the system
prompt for clinical vocabulary returns nothing; the crisis path renders static
content with no model call.

**Escalation path if the product ever wants health positioning:** form a legal
entity and re-enroll as an Organization *before* the copy changes, not after a
rejection.

---

## 1.5 Developer Information — **verdict: 🔴 live defect**

Requires an easy contact method **in the app** and a **Support URL**.

- In-app contact exists (`AboutSettingsView.swift:259-275`, a `mailto:` flow).
- **The Support URL returns HTTP 404 in production** as of 2026-08-07. This is
  the exact reason Apple cited in the November 2025 rejection. See `00` B1 and
  `11`.

**Acceptance:** `curl -o /dev/null -w "%{http_code}"` on the Support URL returns
`200`, the page offers a working contact address, and that address matches the
one in the app.

## 1.6 Data Security — **verdict: satisfied, re-verify after the rewrite**

PIN in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and
constant-time comparison (`SecurityService.swift`); PBKDF2-SHA256 entry
encryption (`EncryptionService.swift`); ATS on. `REQ-DATA-003` (SwiftData store
file protection level) is spec 015's and not yet verified.

## Rest of Section 1

| Guideline | Verdict |
|---|---|
| 1.1 Objectionable Content | N/A — no content Memento authors is objectionable by category; 1.1.6 (false information) is addressed by the non-advisory persona |
| 1.1.6 trick functionality | N/A |
| 1.3 Kids Category | N/A — not submitted to the Kids Category |
| 1.4.2–1.4.5 | N/A — no drug dosage calculators, no defibrillator features, no user-facing danger encouragement |
| 1.7 Reporting Criminal Activity | N/A |

---

# Section 2 — Performance

## 2.1 App Completeness — **verdict: the single highest risk**

Apple: *"Over 40% of unresolved issues relate to Guideline 2.1."* Verbatim
requirement:

> "Submissions to App Review… should be final versions with all necessary
> metadata and fully functional URLs included; placeholder text, empty websites,
> and other temporary content should be scrubbed before submission… include demo
> account info (and turn on your back-end service!) if your app includes a login."

**The demo-account requirement is moot** — Memento has no accounts at all (spec
023). But **the review notes must say so explicitly**, because a reviewer who
finds no credentials and no explanation may reject anyway. See `08`.

**The real 2.1 risk is the empty-app problem.** A reviewer launches Memento in a
quiet room with no meeting to record and no history to reflect on. The core value
proposition — *"a year from now this will know you"* — is invisible on a cold
install. Weekly reflections, monthly Patterns, and Ask all require a corpus.

Three ways to solve it, in order of preference:

1. **A reviewer-discoverable "Load sample entries" affordance** in Settings or
   onboarding, which seeds a small realistic corpus locally. Cheapest, honest,
   and it doubles as a genuinely useful onboarding option for real users. This
   is the recommendation.
2. **Pre-seeded content on first launch**, removable in one tap. Guarantees the
   reviewer sees it, but ships content to every user.
3. **A demo video attached to the review submission** showing the full flow.
   Necessary regardless as a backstop (see `08`), but not sufficient on its own —
   reviewers still want to reach the feature.

Whichever ships, the review notes must give the exact tap path.

**Also required by 2.1:** all URLs functional (blocked on `00` B1/B2), no
placeholder text or images, and — 2.1(b) — **in-app purchases complete, visible
to the reviewer, and functional**. The paywall does not exist yet; when it does,
`Configuration.storekit`'s placeholder product IDs `12345678`/`123456789` must be
replaced with real App Store Connect products or the reviewer will find a
non-functional purchase.

**Acceptance:** a cold-install walkthrough on a device reaches capture →
transcription → a generated reflection using only what the review notes describe,
with no account and no external setup.

---

## 2.3 Accurate Metadata

- **2.3.1(a)** — *"All new features must be described with specificity in Notes
  for Review. Generic descriptions rejected."* Every release, not just 1.0. `08`
  carries a rule that the notes are rewritten per release, never carried forward.
- **2.3.3** — screenshots must show the app **in use**, not a splash, title art,
  or login screen. Memento has no login, so the first screen a screenshot may
  show is the journal or capture surface.
- **2.3.7** — app name **≤30 characters**, accurate keywords, **no trademarks,
  competitor names, or pricing in metadata**; subtitles must not make
  unverifiable claims. Concretely: no "Otter", "Zoom", "Notion", "ChatGPT", and
  **no transcription-accuracy percentage** unless we can substantiate it.
- **2.3.8** — all metadata must adhere to a **4+ rating** even if the app is
  rated higher.
- **2.3.9** — display **fictional** account information in screenshots. Journal
  entries in screenshots must be invented, not real user content.
- **2.3.12** — What's New must describe changes; generic text is acceptable only
  for pure bug-fix releases.

**Verdict:** open, owned by `04`. All drafts there are checked against these.

## 2.4 Hardware Compatibility

- **2.4.1** — iPhone apps should run on iPad where possible. We ship
  `TARGETED_DEVICE_FAMILY = "1,2"`, so this is satisfied — and it is *why* iPad
  screenshots are mandatory (`04`).
- **2.4.2 — "don't rapidly drain battery or generate excessive heat."**
  **Verdict: real, under-estimated risk.** Sustained Foundation Models inference
  during and after long capture is exactly the workload this guideline names.
  Required test protocol, not a note:
  - Record 60 minutes with the app backgrounded on a physical device; observe
    `ProcessInfo.processInfo.thermalState` and battery delta.
  - Generate a weekly reflection over a full corpus and observe the same.
  - Acceptance: `thermalState` does not reach `.serious` in either run, and the
    device does not surface a system heat warning.

## 2.5 Software Requirements

| Sub-guideline | Verdict for Memento |
|---|---|
| **2.5.1** public APIs, current OS | ✅ — all Apple frameworks; no private API |
| **2.5.2** self-contained, no downloading executable code | ✅ **today** — no model is downloaded, no remote prompt manifest (`DEC-003` explicitly defers that to 2.1). **Guard:** if a downloaded model or remote prompt manifest ever ships, 2.5.2 and 4.2.3(ii) attach — disclose the download size, prompt the user, and explain it in the review notes |
| **2.5.4** background modes for intended purposes only (VoIP, audio, location, task completion, local notifications) | N/A today — **no background modes are declared**. Attaches if spec 018/020 add `audio` for long capture. Using `audio` as a keep-alive for inference rather than for playback/recording would be a violation |
| **2.5.5** IPv6-only network functionality | ✅ vacuously — `grep -rn "URLSession" MeetMemento --include="*.swift"` returns **zero** hits |
| **2.5.9** don't alter standard switches or native UI behavior | ✅ |
| **2.5.11 SiriKit & Shortcuts** — register only intents you can handle without launching the app; vocabulary must relate to your app, not generic terms | Attaches when spec 020 R1's four App Intents ship. Constraint: no generic phrases like "start recording" that a system-wide vocabulary would claim |
| **2.5.13** facial recognition for auth must use LocalAuthentication, not ARKit | ✅ — Face ID via `LocalAuthentication` |
| **2.5.14 — explicit consent + clear visual or audible indication when recording microphone** | 🟠 **Binding, and the one to design for.** See below |
| **2.5.18** ads limited to the main binary; no behavioral ads on sensitive data | N/A — no ads, ever |

### 2.5.14 in detail — recording indication

Apple requires an app that records the microphone to **explicitly request consent
and provide a clear visual or audible indication while recording**. The system
orange microphone dot is Apple's indicator, not ours; the guideline is about
*the app's own* affordance. Reviewers test this.

Required:

- A **persistent in-app recording indicator** — not a transient toast — visible
  for the entire duration of capture. A live waveform plus an unambiguous
  "Recording" label satisfies it; a small red dot in a corner is the minimum and
  is weaker.
- When capture continues with the app backgrounded, a **Live Activity / Dynamic
  Island presence**. Spec 020 R4 already plans Live Activities; this makes one of
  them non-optional if background capture ships.
- Consent at the start of every recording session, not only at first permission
  grant.

**Two-party-consent note.** The guidelines contain no dedicated wiretap rule, but
if Memento is ever positioned for recording *meetings with other people* (rather
than the user's own voice), a "notify participants" affordance and a line in the
review notes about jurisdictional consent become worth shipping. Today the app
records the user's own voice journaling, which does not raise this.

**Acceptance:** a UI test asserts the recording indicator is present and visible
for the full duration of a capture session; if background capture ships, a Live
Activity is created on backgrounding and torn down on stop.

## Rest of Section 2

| Guideline | Verdict |
|---|---|
| 2.2 Beta Testing | N/A — betas go to TestFlight (`09`); no compensated testers |
| 2.3.2 IAP disclosed in description/screenshots | Attaches with the paywall (spec 021) |
| 2.3.4 previews are screen captures only | Attaches if an app preview ships (`04`) |
| 2.3.5 correct category | ✅ Lifestyle — see §1.4.1 for why not Health & Fitness |
| 2.3.6 honest age rating | `05` |
| 2.3.10 no other-platform names/imagery | ✅ — but delete the orphan `GoogleIcon.imageset` (`00` C5) |
| 2.3.11 pre-order builds deliverable as submitted | N/A — no pre-order (`10`) |
| 2.5.3 no malicious code · 2.5.6 WebKit for web browsing · 2.5.15 Files integration · 2.5.16 widget relevance | N/A / satisfied |

---

# Section 3 — Business

Everything in this section is gated on `DEC-004` and the paywall, which spec 021
owns. This document records the constraints the paywall must satisfy; it does not
design it.

## 3.1.1 In-App Purchase — **verdict: attaches with the paywall**

> "If you want to unlock features or functionality within your app… you must use
> in-app purchase. Apps may not use their own mechanisms to unlock content or
> functionality, such as license keys…"

Consequences for Memento:
- Every unlock goes through StoreKit. No license keys, no promo-code redemption
  outside Apple's mechanism, no web-purchased unlock honored via a custom token.
- **If AI credits or transcription minutes are ever sold, they may not expire.**
- A **Restore Purchases** path is required. Spec 021 R3 already makes it
  prominent — visible without scrolling — because with no accounts it is the
  *only* cross-device entitlement path.

## 3.1.2 Subscriptions

- **Minimum 7-day duration**; must work across all the user's devices; must
  provide ongoing value.
- Free trials configured in App Store Connect, not hand-rolled.
- **Do not remove primary functionality that existing users already have** when
  introducing the subscription. This is why spec 021 R4's free-forever tier
  (capture, transcription, timeline, search, **export**) matters legally and not
  only ethically.

## 3.1.3(b) Multiplatform Services — **verdict: N/A, note for later**

If Memento ever gains a web app where users can subscribe, entitlements bought
there may be honored in-app — but outside the US storefront the iOS app may not
link to or advertise that purchase path.

## 4.10 Monetizing Built-In Capabilities — **verdict: a constraint spec 021 does not currently carry**

> Apps may not monetize built-in Apple hardware or OS capabilities, or Apple
> services and technologies.

Charging for Memento's reflections is fine. Charging for **"access to Apple
Intelligence"**, "unlock Private Cloud Compute", or "Apple's on-device model" is
not. The paywall must sell the *product* — weekly reflections, Patterns, Ask,
Personal Voice playback — never the Apple technology that produces it.

This interacts with spec 017 R3 (`REQ-INT-008`): the app may factually mention
that iCloud+ raises Apple's PCC quota, must not nag, and must not imply Memento
requires iCloud+. Add to that: it must not imply that **paying Memento** buys
Apple Intelligence capacity.

**Acceptance:** a grep of paywall and upsell copy for "Apple Intelligence",
"Private Cloud Compute", "on-device model", and "iCloud+" finds only factual,
non-transactional uses.

## Rest of Section 3

| Guideline | Verdict |
|---|---|
| 3.1.1(a) external purchase links | N/A — none |
| 3.1.5 cryptocurrencies | N/A |
| 3.2.2 unacceptable business models (forced ratings, download gates) | N/A — and note that `SKStoreReviewController` usage in `AboutSettingsView.swift:287` must stay unconditioned on any reward |

---

# Section 4 — Design

## 4.1(c) — **new November 2025**

> "you cannot use another developer's icon, brand, or product name in your app's
> icon or name, without approval from the developer."

Concretely: the app name, subtitle, and icon must not contain or depict Zoom,
Teams, Meet, Notion, Otter, ChatGPT, or any Apple product name. This binds `04`.

## 4.2 Minimum Functionality — **verdict: comfortably satisfied**

Memento is not a repackaged website; it uses Foundation Models, Core Spotlight,
`SpeechAnalyzer`, App Intents, and Liquid Glass. **4.2.3(ii)** — disclose
download size and prompt the user for post-install resources — is a guard, not a
current obligation (see 2.5.2).

## 4.5.4 Push Notifications — **verdict: attaches if notifications ship**

Push must not be required for the app to function, marketing pushes require
explicit opt-in via app UI, and an opt-out must exist. Memento currently declares
no push entitlement. Local notifications for reflection reminders would fall
under the same expectation of user control.

## 4.7 Mini Apps, Mini Games, Chatbots, Plug-ins — **verdict: N/A, with a named trip-wire**

4.7 governs apps that **host third-party software or chatbots**. Memento's AI is
first-party and embedded in the binary; there is no downloaded prompt manifest
(`DEC-003` defers it), no plug-in system, no user-authored agents. 4.7 does not
apply.

**Trip-wire:** if users can ever install prompts, personas, or agents authored by
anyone else, 4.7 lands — and it drags **1.2** (filter/report/block/contact),
**5.1** in full, **3.1** for any digital goods, and **4.7.5**'s age-restriction
mechanism with it. Treat "let users share custom prompts" as a decision with
guideline consequences, not a feature.

## 4.8 Login Services — **verdict: N/A**

Memento has no third-party or social login (spec 023 removed Sign in with Apple
along with all accounts). 4.8 governs apps that *offer* third-party login; with
none offered, there is nothing to provide an alternative to.

## Rest of Section 4

| Guideline | Verdict |
|---|---|
| 4.1(a)/(b) copycats, impersonation | N/A |
| 4.3 spam / duplicate bundle IDs | N/A |
| 4.4 extensions | Attaches when spec 020's widgets ship — extensions must be disclosed in metadata, no ads or IAP inside them |
| 4.6 alternate icons | N/A today |
| 4.9 Apple Pay | N/A |

---

# Section 5 — Legal

## 5.1.1 Data Collection and Storage

### (i) Privacy policy — **verdict: 🔴 live defect**

The policy must be linked in App Store Connect **and** reachable inside the app,
and must identify what data is collected, how, and every use; confirm that any
third party receiving user data provides equal protection; explain retention and
deletion; and describe how a user revokes consent or requests deletion.

**Current state.** The **published** policy at
`https://sebmendo1.github.io/MeetMemento/privacy.html` describes **OpenAI,
Google, and Supabase**, none of which the app uses. `PRIVACY_POLICY.md` at the
repo root is equally stale (it has a "Google Gemini 2.5 Flash" section).
`docs/privacy.html` in this repository *is* clean — it was simply never
published, because Pages is served from a different repository (`00` A6).

A privacy policy that names third-party AI processors the app does not use is
simultaneously a 5.1.1(i) defect, a 2.3 accuracy defect, and a direct
contradiction of the **"Data Not Collected"** label we intend to declare. Fix
before anything else in this section is meaningful.

**The rewritten policy must state**, in the vocabulary `specs/014` uses:
- Journal content, audio, and derived reflections are stored **on device**, in
  SwiftData, mirrored only to the user's **own CloudKit private database**.
- Generation happens **on device (Z0)** or on **Apple's Private Cloud Compute
  (Z1)**, which stores nothing and is independently verifiable. Apple is the
  platform, not a third-party data recipient — but say so explicitly rather than
  leaving it to inference (see 5.1.2(i)).
- **No analytics SDK. No third-party AI. No accounts.**
- If RevenueCat ships (spec 021), it receives **purchase events and an anonymous
  identifier only** — never content, never derived data.
- Retention, export, and deletion: the user's own words, exportable in Markdown
  and JSON and deletable, per `REQ-DATA-013`.

### (ii) Permission and purpose strings

Consent required for collection even if anonymous; **paid functionality must not
depend on granting data access**; consent must be withdrawable; *"Ensure your
purpose strings clearly and completely describe your use of the data."*

Apple's own common-rejection #6 is unclear data-access requests. Current strings
(`MeetMemento/Info.plist`):

| Key | Current | Assessment |
|---|---|---|
| `NSFaceIDUsageDescription` | "Memento uses Face ID to protect your private journal entries." | ✅ Specific, states what and why |
| `NSMicrophoneUsageDescription` | "Memento needs microphone access to transcribe your voice into journal entries." | 🟠 Adequate; strengthen by stating where processing happens |
| `NSSpeechRecognitionUsageDescription` | "Memento uses speech recognition to convert your voice to text for journaling." | 🟠 Same |

Recommended strengthening, which also serves 5.1.2(i) — see `02` for the final
wording — is to state the on-device boundary in the string itself, since the
permission dialog is the one place every user reads it.

**Constraint from (ii):** paid features must never be gated on granting a
permission. Spec 021 R4's free tier and the paywall must both be reachable
without, say, microphone access.

### (iii) Data minimization — **verdict: currently exemplary, protect it**

Only three permissions are requested and no location, photos, contacts, or
calendar. Specs 018 R5 (photo attachments) and 018 R6 (place and weather) would
add `NSPhotoLibraryUsageDescription` and `NSLocationWhenInUseUsageDescription`.
Each new permission is a reviewer question and a privacy-label input. Ship them
only when the feature genuinely lands, default-off, and update `03` and `04` when
they do.

### (v) Account Sign-In — **verdict: N/A, but expect the adjacent question**

*"If you create accounts you must offer in-app account deletion."* Memento
creates no accounts, so 5.1.1(v) does not apply — and this also removes the
Guideline 2.1 demo-account chore. What a reviewer will ask about instead is
**export and deletion of the user's local data**, which is `REQ-DATA-013` (spec
015). Have that path working and describe it in the review notes.

### (ix) Highly regulated fields

Assessed above under §1.4.1. Individual account + journaling positioning = fine.
Individual account + mental-health positioning = rejection risk.

### Rest of 5.1.1

| Sub | Verdict |
|---|---|
| (iv) no manipulating or forcing consent; provide alternatives for users who decline | ✅ — AI can be disabled entirely (`PreferencesService.aiEnabled`, `SettingsView.swift:162-189`) |
| (vi) surreptitious data discovery | N/A |
| (vii) SafariViewController must be visible | N/A — outbound links use `UIApplication.shared.open` |
| (viii) no compiling personal info from other sources | N/A |
| (x) optional basic contact info | ✅ — the display name is local, optional, and never transmitted |

---

## 5.1.2 Data Use and Sharing — **the guideline that matters most**

Verbatim, with the November 2025 addition in bold:

> "Unless otherwise permitted by law, you may not use, transmit, or share
> someone's personal data without first obtaining their permission… **You must
> clearly disclose where personal data will be shared with third parties,
> including with third-party AI, and obtain explicit permission before doing
> so.** … Your app may not require users to enable system functionalities… in
> order to access functionality, content, use the app, or receive monetary or
> other compensation…"

**We have already been rejected once under 5.1.2** — in November 2025, for
declaring tracking in the App Store Connect privacy labels that the app does not
perform. That was a labels defect (`03` owns it now). The 2026 exposure is
different and is about AI disclosure.

### Our position on Private Cloud Compute, stated rather than assumed

**Position:** Apple Private Cloud Compute is **Apple's own platform
infrastructure, not a third-party AI service.** It requires no API key, costs the
developer nothing, stores nothing, and is independently verifiable. Memento sends
no user content to any non-Apple model provider.

**But the position must be published, not inferred.** 5.1.2(i) asks for *clear
disclosure of where personal data will be shared*. A reviewer reading "AI
reflections" with no architecture statement will ask. Therefore:

1. The **privacy policy** states the Z0/Z1 boundary in plain language and names
   Apple PCC explicitly.
2. The **in-app zone-at-point-of-use disclosure** (spec 014 R2) is the runtime
   half of the same statement.
3. The **review notes** (`08`) state it in one paragraph so the reviewer never
   has to ask.
4. The permitted positioning language is `REQ-POS-001`'s, verbatim, and the
   forbidden absolutes ("nothing leaves your phone", "there is no server") stay
   forbidden while any PCC routing exists — see `04`, which holds App Store copy
   to the same CI linter the app is held to.

### The one place we genuinely do send audio off-device today

`SpeechService.swift` uses `SFSpeechRecognizer` **without setting
`requiresOnDeviceRecognition = true`**, so for some locales recognition may be
performed on Apple's servers. That is an undisclosed off-device path for the most
sensitive data the app touches. Three acceptable resolutions, in order:

1. Migrate to `SpeechAnalyzer`/`SpeechTranscriber` per spec 018 R1 (the planned
   path, and the one that makes the claim mechanically true).
2. Set `requiresOnDeviceRecognition = true` as an interim, accepting reduced
   locale coverage.
3. Disclose it — in the privacy policy, the purpose string, and the review notes.

Doing none of the three while shipping on-device positioning is the actual
5.1.2(i) violation.

### Other 5.1.2 sub-clauses

| Sub | Verdict |
|---|---|
| (ii) no repurposing data without further consent | ✅ |
| (iii) no surreptitious profiling or re-identification | ✅ — no analytics SDK at all (`REQ-MON-004` corollary) |
| (iv) no contact/photo databases; **no collecting installed-app info** | ✅ |
| (v) contact people only at the user's individualized initiative — **no "Select All"** | N/A today; attaches to any future invite or share-with-attendees flow |
| (vi) HealthKit/Clinical/depth data never for marketing or data mining | Attaches only if `DEC-006` resolves to include HealthKit context |
| ATT | **N/A — do not add `NSUserTrackingUsageDescription`.** Declaring tracking without implementing ATT is precisely the November 2025 rejection |

---

## 5.1.3 Health and Health Research — **verdict: N/A today; the tripwire for `DEC-006`**

If `DEC-006` (does HealthKit State of Mind context enter Z1 prompts?) ever
resolves "yes", three obligations attach at once: health data may not go to third
parties for advertising or data mining; **personal health information may not be
stored in iCloud** — which directly constrains the CloudKit mirroring in spec
015; and false data may not be written to HealthKit.

The conservative default already recorded in `technology/08` §3 — exclude
HealthKit entirely — is also the lowest-review-risk answer. Documented here so
the decision is made with the guideline visible rather than discovered afterward.

## 5.1.5 Location Services — **verdict: N/A today**

Attaches when spec 018 R6 (place and weather context) lands. Requirements then:
location must be *directly relevant* to a feature, consent obtained before
collection, and the purpose explained per the HIG. Since R6 specifies the feature
as **off by default**, the permission should be requested at the point of
enabling it, never at launch.

## 5.2 Intellectual Property

- **5.2.1 / 5.2.2** — the **content rights declaration** in App Store Connect
  (`02`, `05`) must be answerable truthfully. Memento displays no third-party
  content; the assets that need a provenance line are the 12 bundled fonts
  (Lora, Sora, Manrope — all open-licensed, record the licence) and
  `welcome-bg.mp4`.
- **5.2.4** — no implied Apple endorsement. Relevant to marketing copy that
  leans on Apple Intelligence adoption: describe what the app does, not what
  Apple thinks of it.
- **5.2.5** — no confusing similarity to Apple products or UI; Activity-ring-like
  visualizations should not resemble the Activity control. Worth a look at any
  Patterns/insights chart design.

## Rest of Section 5

| Guideline | Verdict |
|---|---|
| 5.1.4 Kids | N/A — not a kids app, no third-party analytics or ads regardless |
| 5.3 Gaming, Gambling, Lotteries | N/A |
| 5.4 VPN Apps · 5.5 Mobile Device Management · 5.6 Developer Code of Conduct | N/A / satisfied |

---

## Verification

- [ ] Support URL and privacy policy URL both return `200` and the policy
      describes the app that exists (§1.5, §5.1.1(i)).
- [ ] A cold-install walkthrough reaches capture → transcription → reflection
      using only the review notes (§2.1).
- [ ] `thermalState` stays below `.serious` through a 60-minute backgrounded
      capture and a full-corpus weekly reflection (§2.4.2).
- [ ] A recording session shows a persistent in-app indicator for its full
      duration; background capture, if shipped, creates a Live Activity (§2.5.14).
- [ ] Grep of App Store metadata, paywall copy, and
      `docs/prompts/MEMENTO_SYSTEM_PROMPT.md` finds no clinical vocabulary
      (§1.4.1) and no monetized-Apple-technology framing (§4.10).
- [ ] One of the three `requiresOnDeviceRecognition` resolutions has shipped
      (§5.1.2).
- [ ] `NSUserTrackingUsageDescription` is absent from every plist (§5.1.2).
- [ ] A "Report a problem with this response" affordance exists on each
      generative surface (§1.2).
