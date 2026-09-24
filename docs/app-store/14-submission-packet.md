# 14 — Submission packet

**Compiled 2026-09-24.** One sitting in App Store Connect, in order, with every
value either a file you paste from or a fact with a command behind it.

`00-readiness-checklist.md` is still the row table and the authority on *what* is
required. This is the sequence for *doing* it. Where the two disagree, `00` wins and
this file is stale.

Two standards borrowed from `00`'s preamble, because they are what make this useful:
a row without evidence is not closed, and evidence is a command and its output, a URL
and its status code, or a file path.

---

## 0. Before you open App Store Connect

| # | Do this | Why it is first |
|---|---|---|
| 0.1 | **Xcode → Settings → Accounts → sign in again.** | `-exportArchive` fails with *"Your session has expired"*. This blocks C3, which blocks submit-gate 4, which blocks everything. Nothing else in the repo can move it. |
| 0.2 | Tell the agent when 0.1 is done. | The archive and export then run under `~/Downloads/Xcode.app` (27.0 GA, `27A266a`) and report the ITMS result. |

---

## 1. Paste-ready values

Every field below is a file. Paste the file, do not retype it — the lengths are gated
by `scripts/ci/check_asc_metadata.sh` and retyping is how a 100-character keyword
string becomes 101.

| ASC field | Source file | Value / length |
|---|---|---|
| App Name | `metadata/en-US/name.txt` | `Memento: Private Journal` (24/30) |
| Subtitle | `metadata/en-US/subtitle.txt` | `Private journal that reflects` (29/30) |
| Keywords | `metadata/en-US/keywords.txt` | 99/100 — **at the ceiling**, so any edit must subtract first |
| Promotional Text | `metadata/en-US/promotional_text.txt` | 146 chars |
| Description | `metadata/en-US/description.txt` | 2,345 chars |
| What's New | `metadata/en-US/release_notes.txt` | "First release." + 7 bullets |
| App Review Notes | `metadata/en-US/review_notes.txt` | 3,988/4,000 — answers Apple's six items in Apple's order |
| Resolution Center reply | `metadata/en-US/resolution_center_reply.txt` | 3,900/4,000 — only if the September 2.1 citation is still open |

**Do this one first: D8.** `description.txt` changed *after* the last build was
submitted — the companion line said "requires a compatible iPhone" while the app
ships `TARGETED_DEVICE_FAMILY = "1,2"` and Apple Intelligence runs on M-series iPads.
**The live product page still carries the old wording.** Re-paste `description.txt`.
Metadata edits do not need a new build, so this is fixable today regardless of C3.

### Screenshots — now in the repo (D9)

Both required slots are populated, correctly sized and verified distinct:

| Slot | Path | Size | Frames |
|---|---|---|---|
| iPhone 6.9″ | `metadata/en-US/screenshots/iphone-6.9/` | 1320×2868 | timeline, entry, ask, search |
| iPad 13″ | `metadata/en-US/screenshots/ipad-13/` | 2064×2752 | timeline, entry, ask, search |

iPad is **mandatory**, not optional, because of `TARGETED_DEVICE_FAMILY`. Regenerate
with `AppStoreScreenshotUITests` and verify with
`scripts/ci/export_screenshots.sh <result.xcresult> <slot> <WxH>`, which fails on a
wrong size *or* on duplicate frames.

**One known weakness, stated so you can decide rather than discover:** frame 3 shows
Ask's entry screen with its journal-derived starters, not Ask answering. Apple
Intelligence model assets are per-simulator and the one that has them
(`ChatDiag27`) is an iPhone 17 **Pro**, 1206×2622 — the wrong size for the 6.9″
slot. If you want Ask-answering frames, install the assets on a Pro Max simulator
and re-run with `SCREENSHOT_LIVE_REPLY=1`. The current frame is not an empty state —
the starters prove the journal was read — but it shows the door rather than the room.

---

## 2. The record

| ASC field | Value | Source |
|---|---|---|
| Primary language | English (U.S.) | `02` |
| Primary category | **Lifestyle** | `02` — **not** Health & Fitness, **not** Medical |
| Secondary category | ☐ **still undecided** | `02:45` |
| Price | **Free** | see §3 |
| Version release | **Manually release this version** | `02:77`, `10` §3 |
| Territories | Exclude mainland China; for 1.x also exclude the 27 EU | `05` §7, `10`, A5 |
| Privacy Policy URL | `https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/privacy.html` | D1 |
| Support URL | `https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/support.html` | D2 |

Both URLs return 200 and the privacy page is byte-identical to `docs/privacy.html`,
asserted by `scripts/ci/check_live_legal_urls.sh`. **The old `sebmendo1.github.io`
host is dead — do not paste it.** That host serving a stale policy is the November
2025 rejection.

---

## 3. Free, and why that closes A2

**1.x is Free with no in-app purchases.** Evidence rather than intent: `StoreKit`
appears exactly once in the app target, in `AboutSettingsView` for
`@Environment(\.requestReview)` — the rate-this-app prompt. No `SKProduct`, no
`Product.products`, no `Transaction.currentEntitlements`, no RevenueCat in the
resolved package set.

So by `00` A2's own rule — *"Skip if 1.x is Free (no IAP)"* — the Paid Apps
Agreement, tax forms and banking are **not** blockers, and submit-gate 6 is
satisfied by the skip. Set D10 to Free.

This is the largest user-owned blocker on the checklist and it is closed by a
`grep`, which is why it is worth stating with the evidence attached.

---

## 4. Rows ticked on a statement, not a command

`00`'s preamble: *"In July 2026 the support-URL row was ticked while the page was
returning 404; that is the failure mode this column exists to prevent."* These six
rows are currently ☑ *user-confirmed* or 🟡 *presumed*, which is the same shape.
None is reachable from the repo. Each line below is what to look at and what to
paste back.

| Row | Screen | Field | Expected | Paste back |
|---|---|---|---|---|
| **D6** | ASC → App Privacy | Data collection | Tracking = **No**. Declared: **Other User Content**, **Other Data Types**, **User ID** — *linked, not tracking*; purposes **App Functionality + Analytics**. Journal content **not** collected. | A screenshot of the summary panel |
| **A1** | developer.apple.com → Agreements | Program License Agreement | Accepted, current version | The agreement version and date shown |
| **A7** | ASC → App Information → Age Rating | 5-tier questionnaire | Answered; expected **9+** | The resulting rating badge |
| **A8** | ASC → App Information | Social-media capability declaration | Answered **No** | The answer as shown |
| **D7a** | ASC → App Review Information | Demo video attachment | A physical-device recording **beginning at app launch** | The filename and duration |
| **D5** | ASC → App Information | Copyright, content rights, licence agreement | Values in `02` | The three fields as shown |

**D6 is the one to be slowest about.** `00` says in terms that it "is the row that
caused the November 2025 rejection". Submitting **Data Not Collected** is wrong and
has been since spec 042 — `PrivacyInfo.xcprivacy`'s collected types are no longer
empty. If you find `12` A0.3 saying otherwise, it was corrected on 2026-09-24; check
the date on what you are reading.

**A5's residual:** deselecting the 27 EU territories is decided and reversible, but
the **account-level trader question** still needs answering regardless.

---

## 5. Do not press Submit until

The nine conditions are in `00`. State as of 2026-09-24:

| # | Condition | State |
|---|---|---|
| 1 | Legal pages 200 **and** ASC URLs point at them | Pages ✅ gated; ASC paste ☐ (D1/D2) |
| 2 | Policy matches the 1.x binary; **no PCC mention** | ✅ — the PCC leaks in `04`, `11` §5.2 and `03` were fixed 2026-09-24; B4 is deliberately deferred |
| 3 | Manifest ↔ ASC label ↔ policy agree | Manifest ✅ gated; label ☐ (D6) |
| 4 | archive → export → validate, zero ITMS | ❌ **blocked on §0.1** |
| 5 | Reviewer reaches capture → transcription → Chat with no account | App ✅; notes paste ☐ (D7) |
| 5a | Notes answer all six items **and** a device video is attached | Notes ✅ 3,988 bytes; video ☐ (D7a) |
| 6 | Paid agreements, or Free | ✅ **Free** — see §3 |
| 7 | Age rating and social-media declaration | ☑ statement only (§4) |
| 8 | EU declared **or** deselected | Decided; account-level question ☐ |

**One hard blocker: §0.1.** Everything else is a paste or a look.

---

## 6. What the repo guarantees, and what it cannot

Green on every run, so you do not need to re-check them by hand:
`check_store_metadata` · `check_asc_metadata` · `check_privacy_manifest` ·
`check_live_legal_urls` · `check_app_size` · `check_archive_hygiene` ·
`lint_forbidden_phrases` · `export_screenshots` · plus 1,075 unit tests.

What no gate can see: anything behind an Apple login. That is exactly §4, and it is
why those rows want a screenshot rather than a tick.
