# 11 — Rejection playbook

**Compiled 2026-08-07.**
**Sources:** [App Review](https://developer.apple.com/distribute/app-review/) ·
[Reply to App Review messages](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages/) ·
[App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-and-submission-statuses)

---

## 1. Our rejection history

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
| **The Support URL still returns 404.** `https://sebmendo1.github.io/MeetMemento/support.html` → HTTP 404; the live index links only privacy and terms | `curl -o /dev/null -w "%{http_code}"` |
| **The published privacy policy still names OpenAI, Google, and Supabase** — third-party AI and a backend the app no longer uses | `curl -s …/privacy.html \| grep -io "openai\|google\|supabase"` |

### Why the fixes did not reach production — the lesson worth keeping

The corrected files **were** committed. They were committed to
`Meet-Memento-AI/Memento-Journal-iOS-AFM`, which has **GitHub Pages disabled**.
The live site is served from a **different repository and branch** —
`sebmendo1/MeetMemento` @ `Memento-v1.1`, path `/docs`.

`gh api repos/Meet-Memento-AI/Memento-Journal-iOS-AFM/pages` → **404**.
`gh api repos/sebmendo1/MeetMemento/pages` → `"branch": "Memento-v1.1", "path": "/docs"`.

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
[exact tap path to the sample-entries affordance]
```

---

## 6. Apple's common rejection reasons, annotated

Apple: *"Over 40% of unresolved issues relate to Guideline 2.1: App
Completeness."*

| Apple's reason | Our exposure |
|---|---|
| 1. Crashes and bugs | 🟠 Long recording + backgrounded capture + inference under memory pressure is the surface. Test a 60-minute session on low storage (`01` §2.4.2) |
| 2. Placeholder content | 🟠 `Configuration.storekit` carries product IDs `12345678`/`123456789` (`00` C5) |
| 3. **Broken links** | 🔴 **Live — the Support URL is 404** (§1) |
| 4. Incomplete information | 🟠 The demo-account absence must be *explained*, not just left blank (`08`) |
| 5. **Privacy policy issues** | 🔴 **Live — the published policy names AI vendors the app does not use** (§1) |
| 6. Unclear data access requests | 🟠 Purpose strings are adequate; `02` §4 strengthens them |
| 7. Inaccurate screenshots | ☐ Must match the shipping UI and use fictional entries (`04` §5) |
| 8. Substandard user interface | 🟢 Liquid Glass adoption, design system, HIG-aligned |
| 9. Web clippings / aggregators | 🟢 N/A |
| 10. Copycat apps | 🟢 N/A |
| 11. **Misleading users** | 🟠 The `REQ-POS-001` risk exactly — overstating the privacy boundary. Held by CI over both app strings and store copy (`04` §"three rules") |
| 12. Insufficient lasting value | 🟢 N/A |
| 13. **Submitted by the incorrect entity** | 🟠 Guideline 5.1.1(ix). Individual account + journaling = fine. Individual account + health positioning = rejection (`01` §1.4.1) |

---

## Verification

- [ ] Both November 2025 root causes are closed **in production**, verified by
      `curl` against the published URLs — not by inspecting the repository.
- [ ] `APP_REVIEW_RESPONSE_TEMPLATE.txt` at the repo root is removed or
      redirected here; the stale version claiming email/name/journal collection
      is not sendable.
- [ ] Every rejection this project receives is recorded in §1 with its guideline,
      its root cause, and how it was verified fixed.
