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
| **Email** | Yes | **`contact@sebastianmendo.design`** |
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

**Current size: 3866 bytes of Apple's 4000.** Headroom is tight — 134 bytes. The
three bracketed placeholders must be filled before submission, and filling them
must not push the file over. Re-check with `wc -c` after every edit.

### The three placeholders

| § | Placeholder | Blocked on |
|---|---|---|
| 2(b) | The exact label and navigation path of the **seeded-sample affordance** | The seeded-demo decision — see §3 |
| 6 | The specific feature list for **this** release | Rewrite every release (2.3.1(a)) |
| 7 | Subscription product identifiers, paywall location, and Ready-to-Submit confirmation | `DEC-004`, `specs/021` |

### What each section is defending against

| § | Guideline | What it pre-empts |
|---|---|---|
| 1 | 2.1 | "You didn't give us a demo account" |
| 2 | **2.1** | The empty-app rejection — the single highest risk |
| 3 | **5.1.1, 5.1.2(i)** | "Where does user content go, and which AI processes it?" The November 2025 amendment requires disclosing third-party AI; stating plainly that there is none, and that Apple PCC is the only off-device path, answers it before it is asked |
| 4 | 5.1.1(ii), 5.1.1(iii) | Vague purpose strings — Apple's own common-rejection #6 |
| 5 | 1.2, 2.3.6, **1.4.1 / 5.1.1(ix)** | UGC obligations; age-rating honesty; and the statement that this is **not** a health product, which is what keeps an individual-developer account out of 5.1.1(ix) |
| 6 | **2.3.1(a)** | *"All new features must be described with specificity… Generic descriptions rejected"* |
| 7 | **2.1(b)** | In-app purchases must be complete, visible, and functional to the reviewer |

---

## 3. The seeded-demo decision — must be made before submission

A reviewer launching Memento cold has no entries, so Weekly, Patterns, and Ask —
the entire paid tier and the whole value proposition — have nothing to operate
on. Three options, from `01` §2.1:

| Option | Cost | Verdict |
|---|---|---|
| **A — a "Load sample entries" affordance** in Settings or onboarding, seeding a small realistic corpus locally | One screen and a fixture file. `Fixtures/` already exists with a validated corpus and a CI validator | ✅ **Recommended.** Honest, reviewer-discoverable, and genuinely useful to real users who want to see what the app does before committing to it |
| **B — pre-seed on first launch**, removable in one tap | Ships demo content to every user; muddies a product whose premise is *your* words | Fallback |
| **C — demo video only** | Cheapest | ❌ Not sufficient alone. Reviewers want to reach the feature, not watch it. Necessary as a **backstop**, which is why §4 exists regardless |

Whichever ships, the notes must give the **exact tap path**, and the entries must
be obviously fictional (they will be visible in the reviewer's session and,
separately, in screenshots — Guideline 2.3.9).

**This decision is open.** `00` Section E.

---

## 4. Attachments

Apple supports attaching files, with descriptions and links in the notes. Exact
file-type and size limits are not published on the help page — `[verify]` in the
App Store Connect UI at upload time.

**Attach a demo video for 1.0.** Not because the app needs special hardware, but
because the flow it demonstrates — speech becoming text becoming a cited
reflection — is the thing a reviewer might not reach on their own. 60–90 seconds,
screen recording, no narration required:

1. Onboarding, skipping the app lock.
2. Loading sample entries.
3. Recording a short voice entry, showing the recording indicator.
4. Generating a weekly reflection and tapping through to a citation.
5. Asking a question and seeing the answer with its sources.

Step 3 doubles as the evidence for Guideline **2.5.14** (clear indication while
recording).

---

## 5. Standing rules

1. **Rewrite the notes every release.** Section 6 is the release-specific one;
   2.3.1(a) rejects generic descriptions. Do not carry forward.
2. **Never put a credential in the notes.** No PIN, no key, no password. The
   device-passcode fallback removes the need.
3. **Re-check the byte count** after every edit — `wc -c` against 4000.
4. **Run the phrase linter** — the notes are subject to `REQ-POS-001` like every
   other user-facing claim, and a reviewer reading an absolute privacy claim in
   the notes and finding PCC routing in the binary is the worst possible way to
   be caught overstating.
5. **The notes and the privacy policy must agree.** Section 3 of the notes is a
   compressed restatement of the policy; if the policy changes, this changes.

---

## Verification

- [ ] `wc -c docs/app-store/metadata/en-US/review_notes.txt` → **< 4000**.
- [ ] `python3 scripts/ci/lint_forbidden_phrases.py docs/app-store/metadata` → OK.
- [ ] All three bracketed placeholders are filled.
- [ ] `grep -inE "pin|password|passcode is|api.?key" docs/app-store/metadata/en-US/review_notes.txt`
      surfaces only the device-passcode-fallback sentence — no actual secret.
- [ ] Contact name, phone, and email are entered in App Store Connect; the email
      is `contact@sebastianmendo.design` and matches the in-app support address.
- [ ] Sign-in fields are blank and §1 of the notes explains why.
- [ ] The seeded-sample path in §2(b) matches a real affordance in the shipping
      build, verified by walking it on a cold install.
- [ ] The demo video is attached and shows all five steps in §4.
