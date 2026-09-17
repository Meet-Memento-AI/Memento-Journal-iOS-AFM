# 08 — App Review Information

**Compiled 2026-08-07.**
**Source:** [App Review Information](https://developer.apple.com/help/app-store-connect/reference/app-review-information/)

This is the screen App Review reads before touching the app. Apple: *"You must
provide the following information to App Review. It isn't visible to customers
and can be edited at any time."*

Over **40% of unresolved App Review issues are Guideline 2.1 (App Completeness)**
— and for Memento the 2.1 risk is not a missing demo account, it is that **a
reviewer opens an empty journal with nothing to reflect on.** This screen is
where that gets solved.

---

## 1. The fields

| Field | Required? | Our value |
|---|---|---|
| **First name / Last name** | Yes | ☐ user |
| **Phone number** | Yes | ☐ user — Apple uses this to reach you during review |
| **Email** | Yes | **`hello@withmemento.ai`** |
| **Sign-in required** | — | **No.** Leave username and password **blank** |
| **Notes** | Optional in Apple's UI, **mandatory in practice for this app** | `docs/app-store/metadata/en-US/review_notes.txt` — **≤4000 bytes** |
| **Attachment** | Optional | **A demo video.** See §4 |

### Sign-in information: blank, and say why

Guideline 2.1's demo-account requirement applies to apps that have a login.
Memento has none — spec 023 removed accounts entirely. Leaving the fields blank
with no explanation risks a reviewer treating it as an omission, so **§1 of the
notes states it in the first line.**

The optional app lock is the one thing that can leave a reviewer stuck, so the
notes name the escape hatch: **the device-passcode fallback** on the lock screen
(the forgot-PIN recovery path decided in spec 023). **Do not put a PIN in the
notes, in this repository, or in any file here** — the repository is public, and
in any case the fallback makes it unnecessary.

---

## 2. The draft

The paste-able notes live in **`docs/app-store/metadata/en-US/review_notes.txt`**
so they are covered by `scripts/ci/lint_forbidden_phrases.py` along with the rest
of the store copy.

Hard cap **4000 bytes**. Re-check with `wc -c` after every edit.

> ⚠️ **Headroom is 11 bytes** as of 2026-09-17 (3989/4000). Any addition must be
> paid for by a deletion. Do not add a section without measuring first.

**Permissions no longer get their own section.** The five usage-description keys
are covered inline in §3 ("allow Microphone and Speech Recognition", "Every
permission is optional") because Apple's six items do not ask for a permissions
table and the byte budget does not stretch to one. The purpose strings themselves
are what 5.1.1(ii)/(iii) is graded on, and those live in `Info.plist` and are
gated by `check_store_metadata.sh` — not here.

### The required shape — Apple's six items

**Rewritten 2026-09-17 after the September 2026 Guideline 2.1 rejection.** The
previous version of this section organized the notes around *guidelines we were
defending against*, and the resulting document did not answer Apple's standard
information request. Three of its six items had no answer anywhere in the notes.
See `11` §1.

The notes are structured 1:1 onto Apple's request, in Apple's order, so a
reviewer can tick items off:

| § | Apple's item | Must contain |
|---|---|---|
| 1 | — (framing) | No account, no demo credentials, and **why the Sign-In fields are blank**. Plus the three explicit not-applicables: no registration/login/deletion flow, no shared user-generated content, no paid content or IAP |
| 2 | **2 — purpose and audience** | What it is for, who for, the problem, the value. Carries the "archivist, not advisor; not a health product" line, which also serves 1.4.1 / 5.1.1(ix) |
| 3 | **3 — setup and access** | The app-lock skip, the device-passcode fallback, and the exact sample-entries tap path. This is the empty-app defense (2.1) |
| 4 | **4 — external services** | An explicit list, not prose: Apple Foundation Models, SpeechAnalyzer, NLEmbedding, Vision, CloudKit private DB, MapKit geocoding, bundled CoreML TTS, Supabase (opt-in feedback only). Then the negatives — no auth provider, payment processor, analytics SDK, third-party AI, or third-party packages. Serves 5.1.1 / 5.1.2(i) |
| 5 | **5 — regional differences** | "Functions consistently across all regions," the language, and *hardware* gating (Apple Intelligence) held separate from *regional* gating |
| 6 | **6 — regulated industry / protected material** | Not a regulated product. Bundled assets we do not own and their licences: TTS weights (BigScience OpenRAIL-M), its Apache-2.0 runtime fork, SIL OFL fonts — all attributed in `MeetMemento/Views/Settings/AcknowledgmentsView.swift` |
| 7 | — | Contact |

**Do not mention Private Cloud Compute.** It is stubbed unavailable
(`PCCSessionProviding.swift`) and is not in this binary.

**Release-specific content** is still governed by 2.3.1(a) — *"All new features
must be described with specificity… Generic descriptions rejected"* — so the
feature list is rewritten every release and never carried forward.

**No IAP section is needed while 1.x ships free.** `DEC-004` and `specs/021` are
2.0. If a subscription ever ships, 2.1(b) requires product identifiers, the
paywall location, and Ready-to-Submit confirmation to be added here.

---

## 3. The seeded-demo decision — ✅ **made and shipped**

**Resolved 2026-08-11, recorded here 2026-09-17.** Option A shipped:
`MeetMemento/Services/SampleContentService.swift` plus the **"Load Sample
Entries"** row at `MeetMemento/Views/Settings/SettingsView.swift:317`. The row is
**not** `#if DEBUG` gated, so a reviewer can reach it in the Release build, and
the notes give the exact tap path. This section is retained for the reasoning,
not as an open question.

A reviewer launching Memento cold has no entries, so Weekly, Patterns, and Ask —
the whole value proposition — have nothing to operate on. Three options, from
`01` §2.1:

| Option | Cost | Verdict |
|---|---|---|
| **A — a "Load sample entries" affordance** in Settings or onboarding, seeding a small realistic corpus locally | One screen and a fixture file. `Fixtures/` already exists with a validated corpus and a CI validator | ✅ **Recommended.** Honest, reviewer-discoverable, and genuinely useful to real users who want to see what the app does before committing to it |
| **B — pre-seed on first launch**, removable in one tap | Ships demo content to every user; muddies a product whose premise is *your* words | Fallback |
| **C — demo video only** | Cheapest | ❌ Not sufficient alone. Reviewers want to reach the feature, not watch it. Necessary as a **backstop**, which is why §4 exists regardless |

Whichever ships, the notes must give the **exact tap path**, and the entries must
be obviously fictional (they will be visible in the reviewer's session and,
separately, in screenshots — Guideline 2.3.9).

Option C's warning held up exactly as written: the September 2026 rejection came
with **no** attachment at all, and a reviewer asked for the recording anyway. The
backstop in §4 is not optional.

---

## 4. Attachments

Apple supports attaching files, with descriptions and links in the notes. Exact
file-type and size limits are not published on the help page — `[verify]` in the
App Store Connect UI at upload time.

**Attach a demo video. This is mandatory, not advisory** — the September 2026
rejection asked for it by name: *"A screen recording captured on a physical
device, running the latest operating system, demonstrating the app's
functionality. The recording must begin with launching the app and show the
typical user flow."*

Constraints Apple stated, all of which are load-bearing:

- **Physical device**, not a simulator. Record on the Apple Intelligence iPhone.
- **Latest OS.** iOS 26.
- **Must begin at app launch** — start on the Home screen and tap the icon.
- Record the **Release build of the submitted binary**, not a debug build.

90–120 seconds, one unbroken take, no narration required:

1. Home screen → tap the Memento icon.
2. Welcome → "Get Started" → privacy explainer → "Open my journal".
3. Onboarding; at the lock step tap **"Skip for now"** — shows the lock is
   optional and that no credentials exist.
4. Journal opens **empty** → initials button top-left → Profile → Settings →
   **"Load Sample Entries"** → back to a populated Journal. This is the shot that
   answers "how does a reviewer reach the features".
5. New-entry button → grant Microphone and Speech Recognition → speak a sentence
   with the recording indicator visible → Save.
6. Swipe left to Chat → ask a question → **tap a citation** and land on the
   source entry.
7. Settings → "Export Your Journal" → share sheet appears → cancel.
8. Settings → **"Delete Everything"** → both confirmation steps → first launch.

Step 5 doubles as the evidence for Guideline **2.5.14** (clear indication while
recording). Step 8 pre-empts "where is your deletion flow" — Apple asks about
account deletion, and showing data deletion answers the question behind it.

Note the device model and iOS version; they go in the reply. **Store the file
outside this repository** — it contains sample-journal text and the repo is
public.

---

## 5. Standing rules

0. **Answer Apple's six items, in Apple's order.** The notes have a required
   *shape*, not just required content — see §2. Never leave an item unanswered
   because it looks obviously inapplicable; write "not applicable, because X".
   A blank reads as an omission. This is the September 2026 lesson (`11` §1).
1. **Rewrite the release-specific content every release.** 2.3.1(a) rejects
   generic descriptions. Do not carry forward.
2. **Never put a credential in the notes.** No PIN, no key, no password. The
   device-passcode fallback removes the need.
3. **Re-check the byte count** after every edit — `wc -c` against 4000.
4. **Run the phrase linter** — the notes are subject to `REQ-POS-001` like every
   other user-facing claim, and a reviewer reading an absolute privacy claim in
   the notes and finding PCC routing in the binary is the worst possible way to
   be caught overstating.
5. **The notes and the privacy policy must agree.** Section 4 of the notes is a
   compressed restatement of the policy; if the policy changes, this changes.
6. **The notes and the Resolution Center reply are one text.** Both cap at 4000
   (bytes and characters respectively). Write once, paste twice — a reply that
   says something the Notes field does not is a contradiction in the reviewer's
   own tab.

---

## Verification

- [ ] `wc -c docs/app-store/metadata/en-US/review_notes.txt` → **< 4000**.
- [ ] `python3 scripts/ci/lint_forbidden_phrases.py docs/app-store/metadata` → OK.
- [ ] All six of Apple's items are answered, in Apple's order (§2), with the
      conditional ones answered explicitly rather than omitted.
- [ ] No bracketed placeholders remain: `grep -n "\[" review_notes.txt`.
- [ ] `grep -inE "pin|password|passcode is|api.?key" docs/app-store/metadata/en-US/review_notes.txt`
      surfaces only the device-passcode-fallback sentence — no actual secret.
- [ ] Contact name, phone, and email are entered in App Store Connect; the email
      is `hello@withmemento.ai` and matches the in-app support address.
- [ ] Sign-in fields are blank and §1 of the notes explains why.
- [ ] The seeded-sample path in §3 matches a real affordance in the shipping
      build, verified by walking it on a cold install — not by reading
      `SettingsView.swift`. Confirm the row is reachable in **Release** (it is
      not `#if DEBUG` gated; re-check if that file changes).
- [ ] The demo video is attached, was captured on a **physical** device on the
      latest iOS, **begins at app launch**, and shows all eight steps in §4.
- [ ] The Resolution Center reply and the Notes field contain the same text
      (§5 rule 6), and the reply is under **4000 characters**.
