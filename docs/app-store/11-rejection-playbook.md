# 11 — Rejection playbook

**Compiled 2026-08-07.**
**Sources:** [App Review](https://developer.apple.com/distribute/app-review/) ·
[Reply to App Review messages](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages/) ·
[App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-and-submission-statuses)

---

## 1. Our rejection history

### September 2026 — v1.0, Guideline 2.1 Information Needed

**Not a bug rejection and not a metadata rejection.** Apple asked for six pieces
of information plus *"a screen recording captured on a physical device, running
the latest operating system, demonstrating the app's functionality."* Nothing in
the binary was cited.

The notes **were** pasted into App Store Connect this time — the November 2025
failure mode did not repeat. The notes simply did not answer the questions Apple
asks, and nothing was attached:

| Apple's item | `review_notes.txt` as submitted |
|---|---|
| 1. Screen recording on a physical device | ❌ **No attachment.** No video existed in the repo or anywhere else |
| 2. Purpose, target audience, problem solved | ❌ Absent — §2 opened on navigation, never on what the app is *for* |
| 3. Setup / access instructions | ✅ §1–2 were strong, and the "Load Sample Entries" path was correct |
| 4. External services list | 🟠 Covered in §3 prose, never as the explicit list Apple asked for |
| 5. Regional differences | ❌ Absent entirely |
| 6. Regulated industry / protected third-party material | 🟠 §5 denied health positioning; said nothing about the bundled OpenRAIL-M TTS weights or OFL fonts |

**Root cause: the notes were written to pre-empt the rejections we feared rather
than to answer the questions Apple asks.** `08` §2's table ("What each section is
defending against") is the tell — every section is indexed to a guideline we were
worried about, and none to an item on Apple's standard information request. A
document optimized against imagined objections will miss the actual form.

**Resolution:** `review_notes.txt` restructured 1:1 onto Apple's six items, and
the same canonical text reused as the Resolution Center reply so the two cannot
drift. Demo video recorded on a physical Apple Intelligence iPhone per `08` §4.

**This one did not stay metadata-only.** A 2.1 information request needs no
binary, and the temptation is to reply and move on. But the support-email
re-point to `hello@withmemento.ai` sits in `Constants.swift`, and `strings` on
the submitted archive confirmed build 3 still carries
`contact@sebastianmendo.design`. Publishing the new address to the website while
the reviewer's copy of the app shows the old one would have re-created the very
defect D3 exists to prevent — several support addresses live at once. So build 4
ships the re-point, and A1 (Program License Agreement) and C3 (export →
`altool --validate-app`, which has never once completed) return to the critical
path. **Check what a metadata fix drags into the binary before calling it
metadata-only.**

**Lesson, encoded in `08`:** the notes have a required *shape*, not just required
content. Apple's six-item request is the shape. Answer it in its own order, and
answer the conditional items explicitly with "not applicable, because X" — a
blank is read as an omission, which is what happened to the sign-in fields in
November 2025 and to items 2, 5 and 6 here.

### November 2025 — v1.0, submission `c96f3d15-5c5c-4acc-9182-b2faf3aacff4`

Two citations, both **metadata rejections** — the binary was never the problem.

| Guideline | What Apple said | What was actually wrong |
|---|---|---|
| **5.1.2** — Data Use and Sharing | The App Store Connect privacy labels indicated tracking (Performance Data, Email, Name) while the app does not implement App Tracking Transparency | The labels were wrong. The app never tracked. Declaring tracking obliges you to implement ATT; declaring it without ATT is an automatic rejection |
| **1.5** — Developer Information | The Support URL was a bare landing page with no support information | It pointed at the site root, which had no contact method and no help content |

### What was done, and what was not

A support page (`docs/support.html`) was written, a reply drafted
(`APP_REVIEW_RESPONSE_TEMPLATE.txt`, now folded into §5 below), and the privacy
labels were to be corrected in App Store Connect.

**Nine months later, on 2026-08-07, both root causes are still live in
production:**

| | Evidence |
|---|---|
| **The Support URL still returns 404.** `https://sebmendo1.github.io/withMemento/support.html` → HTTP 404; the live index links only privacy and terms | `curl -o /dev/null -w "%{http_code}"` |
| **The published privacy policy still names OpenAI, Google, and Supabase** — third-party AI and a backend the app no longer uses | `curl -s …/privacy.html \| grep -io "openai\|google\|supabase"` |

### Why the fixes did not reach production — the lesson worth keeping

The corrected files **were** committed. They were committed to
`Meet-Memento-AI/Memento-Journal-iOS-AFM`, which has **GitHub Pages disabled**.
The live site is served from a **different repository and branch** —
`sebmendo1/withMemento` @ `Memento-v1.1`, path `/docs`.

`gh api repos/Meet-Memento-AI/Memento-Journal-iOS-AFM/pages` → **404**.
`gh api repos/sebmendo1/withMemento/pages` → `"branch": "Memento-v1.1", "path": "/docs"`.

**Three lessons, encoded in this library:**

1. **Publishing is not committing.** A fix to a hosted asset is not done until
   the hosted asset changes. `00`'s evidence column exists for this.
2. **Verify the artifact Apple sees, not the artifact you edited.** The check is
   `curl` against the production URL, not `ls` against the repo.
3. **A metadata rejection with a "no code change needed" conclusion is the
   easiest kind to leave half-finished**, precisely because it feels done once
   the file is written.

The fix is `00` A6 — enable Pages on the canonical repository and retire the
other site.

---

## 2. Metadata rejection vs binary rejection

Knowing which one you have is worth days.

| | **Metadata Rejected** | **Rejected** |
|---|---|---|
| What is wrong | Screenshots, description, keywords, support URL, privacy policy URL, age rating, subtitle, promotional text, or the review notes | Code, behavior, entitlements, privacy, or crashes |
| New build needed? | **No** | **Yes**, with an incremented build number |
| How to resolve | Fix in App Store Connect, reply in Resolution Center. The app usually returns to review quickly | Upload a new build; full review cycle |
| Cost | Hours | Days, plus a consumed build number |

**Both of our November 2025 citations were metadata rejections.** The correct
response was to fix App Store Connect and reply — no resubmission. Recognizing
this early is the difference between a same-day fix and an unnecessary build.

---

## 3. Resolution Center

**Where:** App Store Connect → your app → **App Review** → Resolution Center.
Accessible any time, even with no active submission.
**Role:** Account Holder, Admin, or App Manager.

**Flow:** unresolved-issues link → "In Progress" → **Resolve** → **Reply to App
Review** → reply (**4,000 character limit**) → optional **Attach File** →
Reply. Drafts can be saved.

Replies go back to the **same reviewer** and are typically answered in 24–48
hours. Rejections usually arrive with the guideline number and often screenshots
or device logs.

**How to write the reply:**

1. **Address each citation separately, by guideline number.**
2. **State what changed, concretely** — a URL, a setting, a build number.
3. **Attach evidence** where it helps: a screen recording of the flow the
   reviewer could not find, a screenshot of the corrected App Store Connect
   field.
4. **Ask a question if the citation is ambiguous.** Reviewers do answer, and a
   clarifying question costs one cycle where a wrong guess costs two.
5. **Do not argue the guideline.** That is what the Appeal is for (§4).

---

## 4. Expedited review and appeals

### Expedited review

Request: https://developer.apple.com/contact/app-store/?topic=expedite

Apple grants it for exactly two reasons: a **critical bug fix** — include exact
reproduction steps and user impact — or a **time-sensitive event** — include the
event name, date, and your app's association with it. Security vulnerabilities
are commonly accepted under the first.

Approved requests typically clear in **6–24 hours** `[secondary]`. Apple grants
them sparingly; abusing the channel reduces future grants. Treat it as roughly a
couple per year and **do not spend one on a launch date you chose yourself.**

### App Review Board appeal

Request: https://developer.apple.com/contact/app-store/?topic=appeal
(direct: `https://developer.apple.com/contact/request/app-review/appeal/`)

Apple's rules, verbatim in substance:

- Give **specific reasons why your app complies** with the cited guideline.
- **One appeal per rejected submission.**
- **Respond to any outstanding requests for information first.**

**Use it only when a guideline was misapplied or the app was misunderstood** —
not to re-argue a factual rejection. No published SLA; **typically 5–7 business
days** and sometimes longer, with **no live status in Resolution Center**.
`[secondary]`

For Memento, the realistic appeal scenario is a **5.1.1(ix)** or **1.4.1**
citation reading the app as a mental-health product. The defense is already
written: the archivist persona, the static crisis card, the description's "WHAT
IT WILL NOT DO" section, and the review notes' §5. That is why those exist as
artifacts rather than intentions.

### Other channels

- **30-minute Webex App Review appointments** with review specialists, bookable
  from the App Review page. Useful before a risky first submission.
- **Guideline change suggestions:** https://developer.apple.com/contact/app-store/?topic=guideline
- **Developer Forums.**

---

## 5. Reply templates

### 5.1 Metadata rejection — the November 2025 pattern

Preserved from `APP_REVIEW_RESPONSE_TEMPLATE.txt`, corrected for the current
architecture. **Do not send the original** — it claims the app collects email,
name, and journal content for authentication, which was true of the Supabase-era
app and is false now.

```
Hello App Review Team,

Thank you for your feedback on submission [ID].

Guideline [N] — [Title]:
[One paragraph: what was wrong, what changed, and where to verify it.
Name the exact App Store Connect field or the exact URL.]

[Repeat per citation.]

[If evidence helps:] A screen recording demonstrating [X] is attached.

The issues are resolved and the submission is ready for re-review. Please let
us know if anything remains unclear.

Best regards,
[Name]
```

### 5.2 If asked about AI processing (Guideline 5.1.2(i))

```
Memento does not share user content with any third-party AI service.

Text generation runs on the device using Apple's Foundation Models framework,
or on Apple's Private Cloud Compute for longer-context work. Private Cloud
Compute is Apple platform infrastructure; it stores nothing and is
independently verifiable. There is no other AI provider, no analytics SDK, and
no account system.

Entries are stored on the device and synced only through the user's own iCloud
private database, which we cannot read. Our privacy policy at [URL] describes
this, and the app shows which processing path produced each piece of generated
text at the point where it is displayed.
```

### 5.3 If asked for a demo account (Guideline 2.1)

```
Memento has no sign-in of any kind — no account system and no login screen.
Every feature is available immediately after installing, which is why the
Sign-In Information fields are blank.

The app offers an optional Face ID or passcode lock during onboarding. It is
skippable, and if it is enabled the device passcode works as a fallback on the
lock screen.

To see the reflection features, which need entries to work from:
Journal -> initials button, top-left (VoiceOver: "Menu") -> Profile ->
Settings -> "Load Sample Entries". That adds a fictional journal and is
reversible from the same row; it never touches real entries.
```

### 5.4 If asked for information under 2.1 (the September 2026 pattern)

Apple's standard information request has **six numbered items**. Answer them in
Apple's order, under Apple's numbers, and answer the conditional ones explicitly
rather than omitting them:

- **1 — recording.** Attach it. Name the device model and iOS version in the
  reply. Then state what the app does *not* have, so the reviewer stops looking:
  no registration/login/account-deletion flow (no accounts), no user-generated
  content shared between users (so no reporting/blocking mechanism applies), no
  paid content or in-app purchases.
- **2 — purpose and audience.** What it is for, who for, what problem, what value.
  Include the "archivist, not advisor; not a health product" line — it does
  double duty against 1.4.1 / 5.1.1(ix).
- **3 — setup and access.** No credentials; why the sign-in fields are blank; the
  app-lock skip and the device-passcode fallback; the sample-entries tap path.
- **4 — external services.** An explicit list, not prose. End with the negatives:
  no auth provider, no payment processor, no analytics or crash SDK, no
  third-party AI, no third-party packages.
- **5 — regional differences.** "Functions consistently across all regions" is an
  acceptable answer and Apple names it as one. Say so plainly, note the language,
  and separate *hardware* gating (Apple Intelligence) from *regional* gating.
- **6 — regulated industry / protected material.** Not regulated, does not present
  as such. Then list bundled assets we do not own and their licences.

**Never leave an item unanswered because it seems obviously inapplicable.**

---

## 6. Apple's common rejection reasons, annotated

Apple: *"Over 40% of unresolved issues relate to Guideline 2.1: App
Completeness."*

| Apple's reason | Our exposure |
|---|---|
| 1. Crashes and bugs | 🟠 Long recording + backgrounded capture + inference under memory pressure is the surface. Test a 60-minute session on low storage (`01` §2.4.2) |
| 2. Placeholder content | 🟢 **Closed 2026-08-11** — `Configuration.storekit` and its placeholder IDs deleted (`00` C5); `check_archive_hygiene.sh` guards it |
| 3. **Broken links** | 🟢 **Closed 2026-08-17** — all four legal URLs return 200 on the canonical host; `check_live_legal_urls.sh` guards it and is wired into CI |
| 4. **Incomplete information** | 🔴 **This is what we were cited for in September 2026** (§1). The demo-account absence *was* explained; items 2, 5 and 6 of Apple's request were not answered at all, and no recording was attached. See §5.4 |
| 5. **Privacy policy issues** | 🟢 **Closed 2026-09-12** — the live policy is byte-identical to `docs/privacy.html`, names no third-party AI processor, and discloses the spec-042 opt-in egress |
| 6. Unclear data access requests | 🟠 Purpose strings are adequate; `02` §4 strengthens them |
| 7. Inaccurate screenshots | ☐ Must match the shipping UI and use fictional entries (`04` §5) |
| 8. Substandard user interface | 🟢 Liquid Glass adoption, design system, HIG-aligned |
| 9. Web clippings / aggregators | 🟢 N/A |
| 10. Copycat apps | 🟢 N/A |
| 11. **Misleading users** | 🟠 The `REQ-POS-001` risk exactly — overstating the privacy boundary (including "100% on-device" while CloudKit private replica and PCC exist). Held by CI over both app strings and store copy (`04` §"three rules") |
| 12. Insufficient lasting value | 🟢 N/A |
| 13. **Submitted by the incorrect entity** | 🟠 Guideline 5.1.1(ix). Individual account + journaling = fine. Individual account + health positioning = rejection (`01` §1.4.1) |

---

## Verification

- [x] Both November 2025 root causes are closed **in production**, verified by
      `curl` against the published URLs — not by inspecting the repository.
      `bash scripts/ci/check_live_legal_urls.sh` → all four 200, privacy page
      byte-identical to `docs/privacy.html` (2026-09-17).
- [x] `APP_REVIEW_RESPONSE_TEMPLATE.txt` at the repo root is removed or
      redirected here; the stale version claiming email/name/journal collection
      is not sendable. **Confirmed gone 2026-09-17** — §5 is now the only source.
- [x] Every rejection this project receives is recorded in §1 with its guideline,
      its root cause, and how it was verified fixed. September 2026 added.
- [ ] `review_notes.txt` answers Apple's six-item request in Apple's order
      (§5.4), and a demo video recorded on a physical device is attached to the
      App Review Information screen.
