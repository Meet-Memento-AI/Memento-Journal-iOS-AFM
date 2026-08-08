# 05 — Age rating and the compliance declarations

**Compiled 2026-08-07.** Covers the declarations that are neither code nor
marketing copy, but which block submission or cause removal if wrong.

**Sources:** [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/) ·
[Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/) ·
[Updated age ratings news](https://developer.apple.com/news/?id=ks775ehf) ·
[Export compliance](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/) ·
[EU DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) ·
[Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/) ·
[Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)

---

## 1. Age rating

### The 2025 overhaul

Apple replaced the four-tier scale with five: **4+, 9+, 13+, 16+, 18+**. The old
12+ and 17+ are gone. Answers to the updated questionnaire were **due
2026-01-31**; apps that have not answered are **blocked from submitting new
versions or updates**. Ratings now vary by country/region and surface on iOS 26 /
iPadOS 26 / macOS Tahoe 26 and later.

Questionnaire categories: **In-App Controls · Capabilities · Mature Themes ·
Medical or Wellness · Sexuality or Nudity · Violence · Chance-Based Activities**.

### Worked answers for Memento

| Category | Answer | Why |
|---|---|---|
| **In-App Controls** | Parental controls: no. Content filters: no. Communication limits: N/A. Spending limits: N/A (single subscription, no consumables) | Nothing to restrict — there is no other user and no external content |
| **Capabilities — user-generated content** | **No** | Entries are private, on-device, single-user. No feed, no sharing surface, no other users. See `01` §1.2 |
| **Capabilities — messaging / communication with strangers** | **No** | No messaging of any kind |
| **Capabilities — web browsing / arbitrary web content** | **No** | Two `UIApplication.shared.open` links to our own privacy and terms pages. **No in-app browser, no `WKWebView`.** Answering yes here would force **16+** |
| **Capabilities — advertising** | **No** | No ads, ever |
| **Capabilities — location sharing** | **No** | No location permission today. Re-answer if spec 018 R6 ships place context |
| **Capabilities — social media** | **No** | See §2 — this becomes a *required* answer in September 2026 |
| **Mature Themes — profanity, crude humor, horror** | None | The archivist persona does not generate them; the **user's own words** may contain anything, but the app does not author or publish them |
| **Medical or Wellness** | ⚠️ **The decision point.** See below | |
| **Sexuality or Nudity** | None | |
| **Violence** | None | |
| **Chance-Based Activities** | None | No loot boxes, no simulated gambling |

### The Medical-or-Wellness answer is the whole rating

Apple's scale:

- **4+** — no health or wellness content at all.
- **9+** — adds **"health and wellness topics"**.
- **13+** — adds **"infrequent medical or treatment information"**.
- **16+** — adds **"frequent medical or treatment information"**.

Apple explicitly says AI assistant and chatbot functionality must be factored in:
*the frequency with which the app can surface sensitive content determines the
rating.* A journaling app whose model responds to entries about a hard week is
touching wellness topics whether or not we intend it to.

**Recommendation: answer for 9+ and hold the archivist persona.**

- **4+ is not honestly reachable.** Claiming a generative reflection surface can
  never touch a wellness topic is a claim the first user with a difficult week
  disproves. A rating that understates the app is a 2.3.6 problem.
- **13+/16+ is what we must avoid**, and the way to avoid it is the same
  constraint that keeps us out of Guideline **5.1.1(ix)** (highly regulated
  fields, individual developer): the model must never produce **treatment
  information** — no advice, no coping protocols, no diagnosis, no clinical
  vocabulary. See `01` §1.4.1.

**The rating and the 5.1.1(ix) exposure are the same property viewed twice.**
Enforcing the non-advisory persona buys both.

**Crisis content** (`REQ-SUR-004`): a static, respectful, region-appropriate
resource card is a *pointer to help*, not treatment information. Keeping it
static — never generated — is what keeps it on the 9+ side of the line.

### The "higher age requirement" override

New in 2025: you may manually set a rating **higher** than the questionnaire
computes, to reflect your own terms. You may not set it lower. Not needed here.

**Acceptance:** the questionnaire is answered as above; the computed rating is
recorded in `02`; a grep of `docs/prompts/MEMENTO_SYSTEM_PROMPT.md` and the
`PromptRegistry` for clinical vocabulary returns nothing.

---

## 2. Social-media capability declaration — **new, and imminent**

**Source:** [App Store — what's new](https://developer.apple.com/app-store/whats-new/) ·
[news](https://developer.apple.com/news/?id=tlur8uvi)

- **From July 2026** the age-rating questionnaire includes a question about
  whether the app has **social media capabilities**.
- **From September 2026** answering it is **required to submit new versions or
  updates.**
- Apps that declare it get a **Social Media content descriptor** on the product
  page, and are included in the per-category **Time Allowances** parental
  controls arriving in iOS/iPadOS/macOS **27**.

**Our answer: No.** Memento has no feed, no messaging, no profiles, no sharing to
other users.

**This is on the critical path.** As of this document's date (2026-08-07) the
requirement is weeks away. It costs one form field; discovering it at submit time
costs a submission cycle. `00` A8.

---

## 3. Export compliance

### Our declaration and its reasoning

`MeetMemento/Info.plist` already contains:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

This removes the export-compliance question from **every** subsequent upload,
including TestFlight builds. The reasoning, recorded here so a future session
does not have to re-derive it:

| Apple's matrix | Memento |
|---|---|
| Only encryption **provided by the Apple operating system** → **no documentation required** | ✅ This is us. PBKDF2-SHA256 via **CommonCrypto** and key storage in the **Keychain** (`EncryptionService.swift`, `SecurityService.swift`) are OS-provided. Transport is **ATS-only HTTPS** (`NSAllowsArbitraryLoads = false`) — and in practice there is no `URLSession` in the app at all |
| Industry-standard algorithm **not** provided by the OS (a bundled crypto library) → **French encryption declaration** if distributing in France | ❌ Not us. No bundled OpenSSL, libsodium, or equivalent. Verify this stays true whenever a dependency is added |
| **Proprietary** encryption → **US CCATS + French declaration** | ❌ Not us |

**Therefore: no French declaration, no CCATS, no
`ITSEncryptionExportComplianceCode`.**

**Guard:** if a dependency ever bundles its own crypto implementation, this
declaration becomes false and row 2 applies. The dependency-allowlist check
(`specs/021` R6) is the place that would catch it.

### Annual self-classification report — `[verify]`

An app relying on **exempt** encryption may still owe the US Bureau of Industry
and Security a **year-end self-classification report, due February 1** for the
prior calendar year. Apple links to the filing instructions from its
encryption-export page. This is **flagged `[verify]`** — the applicability to an
app that uses only Apple-OS-provided encryption is not stated unambiguously in
Apple's documentation. Check before the first February after launch.

---

## 4. EU Digital Services Act — trader status

**This is a decision, not a form-fill.**

### The requirement

Under DSA Articles 30 and 31, Apple must verify and **publicly display** trader
contact information for anyone distributing in the 27 EU territories.

- **Since 2024-10-16** — trader status is required to submit apps or updates for
  EU distribution.
- **Since 2025-02-17** — apps **without** trader status are **removed from the
  App Store in the EU** until status is provided and verified.
- You must declare status **even if you do not distribute in the EU.** Set at
  account level under **Business → Agreements → Compliance**; overridable per app
  under **App Information → App Store Regulations and Permits → Digital Services
  Act**. Account Holder or Admin.

### Who is a trader

*"Any natural or legal person… acting for purposes relating to his or her trade,
business, craft or profession."* A **paid** app with a subscription is a
commercial activity. **Memento's developer is a trader.**

### What must be supplied — and what becomes public

For an **individual** enrollment: **address or P.O. box, phone number, email
address**, and payment account details, plus certification of EU-law compliance
and business verification documentation. Email and phone are verified via 2FA.

**The address and phone number are displayed publicly on the EU product page.**
For an individual developer that means a home address and a personal phone
number, visible to anyone. It cannot be hidden.

### The two branches

| Option | What it costs | What it buys |
|---|---|---|
| **A — Supply a registered business address** (registered agent, virtual business address, or a formed legal entity) | Setup cost and annual fee; a legal entity would also change the **seller name** on the store and require re-enrollment as an Organization | EU distribution with no personal address exposure. If a legal entity is formed anyway, it also removes the Guideline **5.1.1(ix)** exposure discussed in `01` §1.4.1 |
| **B — Deselect all 27 EU territories at launch** | Loses a large, privacy-conscious market that is arguably Memento's best-fit audience | Zero setup, zero exposure. Reversible later once an address exists |

**Recommendation: Option A**, because a P.O. box or registered-agent address is
cheap relative to the market, and because it composes with the legal-entity path
that `01` §1.4.1 already flags as the escalation route if the product ever wants
health positioning. But this is the user's call — it involves personal
information and money.

**This document records the decision; it does not make it.** `00` A5.

---

## 5. Content rights

**App Store Connect → App Information → Content Rights.** The question is whether
the app contains, shows, or accesses **third-party content**, answerable only as
"Yes, and I have the necessary rights" or "No".

**Our answer: No** — Memento displays only the user's own content and content the
app generates from it.

Assets that need a recorded provenance line before answering, because they are
third-party works bundled in the binary:

| Asset | Location | Licence | Status |
|---|---|---|---|
| Lora (4 weights) | `MeetMemento/Resources/Fonts/` | SIL Open Font License 1.1 — verify | ☐ Record |
| Sora (5 weights) | `MeetMemento/Resources/Fonts/` | SIL Open Font License 1.1 — verify | ☐ Record |
| Manrope (3 weights) | `MeetMemento/Resources/Fonts/` | SIL Open Font License 1.1 — verify | ☐ Record |
| `welcome-bg.mp4` | app bundle | Unknown — must be original, licensed, or replaced | ☐ **Verify** |
| `SVGKit`, `ProgressiveBlurHeader` | SPM | Open source — record licence in the allowlist decision record | ☐ Record |

Open-font licences do not make the answer "Yes" (fonts are embedded software
components, not displayed third-party content), but the licences must be
satisfiable on request. `welcome-bg.mp4` is the one to actually check — a stock
video without a licence is a Guideline **5.2.1** problem.

---

## 6. Accessibility Nutrition Labels

**Status: voluntary today.** Apple: *"You'll be given ample time and evaluation
resources before this is mandatory, but over time, you'll be required to share
accessibility support details."* **No mandatory date has been announced** and it
does not appear on the upcoming-requirements page as of 2026-08-07.

- Displayed on iOS 26 / iPadOS 26 / macOS 26 / tvOS 26 / visionOS 26 / watchOS 26
  and later, **per platform**.
- Since September 2025 users can **search and filter the App Store by
  accessibility feature** — declaring is a discovery advantage, not only a
  compliance one.
- **Editable at any time without a new submission.** But: *"If an app
  inaccurately claims feature support, App Review may contact the developer and
  request an update to the label or the app."*

### Apple's bar

Users must be able to complete **all common tasks** using the feature. Apple
defines common tasks as: the app's **primary functionality**, the **first-launch
experience**, **login** (N/A here), the **purchase flow**, and **settings**.

### Recommended declarations, gated on `specs/020` R8

| Feature | Declare? | Depends on |
|---|---|---|
| **VoiceOver** | Yes | `REQ-A11Y-001` — every interactive element labeled, decorative images hidden, Accessibility Inspector reports zero missing descriptions |
| **Larger Text** | Yes | `REQ-A11Y-001` — Dynamic Type through AX5, zero `.system(size:)`, 200%+ scaling |
| **Voice Control** | Yes | `REQ-A11Y-003` — labels double as Voice Control targets |
| **Sufficient Contrast** | Yes | Design-system audit |
| **Differentiate Without Color Alone** | Yes | Design-system audit |
| **Reduced Motion** | Yes | Liquid Glass surfaces honor Reduce Motion / Reduce Transparency |
| **Dark Interface** | Yes | Theme already ships light and dark |
| **Captions** | ⚠️ **Highest-signal, decide deliberately** | See below |
| **Audio Descriptions** | No | No video content to describe |

**Captions deserves a decision.** An app whose core output is a **transcript**
and whose reflections are **spoken aloud** by `AVSpeechSynthesizer` is exactly the
app users will filter for. But Apple's bar is *all common tasks* — declaring
Captions means the spoken reflection playback has a synchronized text
presentation, not merely that transcripts exist elsewhere in the app. Since
reflections are rendered as complete text before playback (spec 018 R7), this is
plausibly already true; confirm against the shipped playback surface before
declaring.

**Do not declare anything until `specs/020` R8's verification passes.** An
inaccurate accessibility claim invites App Review contact and is a worse outcome
than declaring nothing.

**Adjacent driver:** the **EU Accessibility Act** obligations became applicable
2025-06-28 for consumer-facing digital products in the EU — the same feature set,
under a different legal instrument. If Option A is taken in §4, this becomes a
compliance matter, not only a marketing one.

---

## 7. Regional availability declarations

| Territory | Requirement | Recommendation |
|---|---|---|
| **EU (27)** | DSA trader status, verified | See §4 — decision pending |
| **Mainland China** | **ICP filing number** required to distribute; apps without one cannot publish updates and face removal. Effectively unobtainable for a foreign individual without a mainland entity | **Deselect mainland China** |
| **France** | French encryption declaration — only if row 2 or 3 of §3 applied | N/A for us |
| **South Korea** | Content-rating declaration for organization-enrolled developers; scope for non-game apps is `[verify]` | Check at territory-selection time |

Territory selection itself is in `10`.

---

## Verification

- [ ] Age-rating questionnaire answered with the §1 answers; computed rating
      recorded in `02`; the Medical-or-Wellness answer matches what the app can
      actually produce.
- [ ] Social-media capability declared **No** (required from September 2026).
- [ ] `plutil -p` on the **archived** product shows
      `ITSAppUsesNonExemptEncryption => false`; no dependency bundles its own
      crypto implementation.
- [ ] EU trader status decision recorded; if Option A, status shows **verified**
      in App Store Connect; if Option B, all 27 EU territories are deselected.
- [ ] Content rights answered **No**; every row in §5's asset table has a
      recorded licence, and `welcome-bg.mp4`'s provenance is confirmed.
- [ ] Accessibility Nutrition Labels either left blank, or declared only for
      features `specs/020` R8 has verified — with Captions decided explicitly.
- [ ] Mainland China deselected in territories.
