# 04 — Product page metadata and assets

**Compiled 2026-08-07.**
**Sources:** [Product page](https://developer.apple.com/app-store/product-page/) ·
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) ·
[App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/) ·
[App icons (HIG)](https://developer.apple.com/design/human-interface-guidelines/app-icons)

The **paste-able copy lives in `docs/app-store/metadata/en-US/*.txt`**, not in
this file. That is deliberate: `scripts/ci/lint_forbidden_phrases.py` scans
`.txt` files, so the App Store copy is held to `REQ-POS-001` by the **same CI
linter as the app's own strings**. This document explains the rules, records the
character counts, and covers the assets.

---

## The three rules every draft is checked against

**1. `REQ-POS-001` — the positioning claim.** The app routes to Private Cloud
Compute, so absolute-privacy claims are false. Forbidden, verbatim from
`specs/014` R3 and `technology/10` §6:

> ❌ "Nothing leaves your phone" · ❌ "No network calls" · ❌ "Turn on airplane
> mode and everything still works" · ❌ "There is no server" · ❌ "100% on-device"
>
> iCloud private-DB replica (spec 040) is the user's Apple ID, not a Memento
> account. Do not claim the journal never leaves this device.

Permitted, and used verbatim in the description:

> ✅ "No account. No analytics. No third-party AI. Your words are processed on
> your iPhone, or on Apple's Private Cloud Compute, which stores nothing and is
> independently verifiable. Nothing else."

Overstating the trust boundary is an existential brand risk in exactly the
community that would otherwise advocate for this app. It is also a Guideline
**2.3** accuracy problem.

**2. Guideline 2.3.7 / 4.1(c) — no competitor or third-party names, no
unverifiable claims, no pricing.** No "Otter", "Zoom", "Teams", "Notion",
"ChatGPT". **No transcription-accuracy percentage** — we cannot substantiate one.
No price in the description (2.3.7 forbids it; the store shows the price).

**3. Guidelines 1.4.1 / 5.1.1(ix) — no clinical framing.** No "therapy",
"mental health", "wellbeing", "anxiety", "depression", "heal", "coach". Memento
is enrolled as an **individual** developer; health positioning moves it toward
5.1.1(ix)'s "should be submitted by a legal entity" and toward a 13+/16+ age
rating. See `01` §1.4.1 and `05` §1. The description says this outright in its
"WHAT IT WILL NOT DO" section, which is both honest and a defensive artifact.

**Also:** Guideline **2.3.8** — all metadata must adhere to a **4+ rating** even
though the app is rated 9+.

---

## 1. The drafts and their counts

Verified 2026-08-07 (counts exclude the trailing newline):

| Field | File | Limit | Ours | |
|---|---|---|---|---|
| App Name | `metadata/en-US/name.txt` | 30 | **24** | ✅ |
| Subtitle | `metadata/en-US/subtitle.txt` | 30 | **29** | ✅ |
| Keywords | `metadata/en-US/keywords.txt` | 100 | **99** | ✅ |
| Promotional Text | `metadata/en-US/promotional_text.txt` | 170 | **146** | ✅ |
| Description | `metadata/en-US/description.txt` | ~4000 `[verify]` | **2656** | ✅ |
| What's New | `metadata/en-US/release_notes.txt` | ~4000 `[verify]` | **615** | ✅ |

> `[verify]` — 4000 is the widely-used figure; Apple does not publish it on the
> product-page documentation. Read it off the App Store Connect field counter and
> update this row.

### App Name — `Memento: Private Journal`

The in-app display name stays **"Memento"**
(`INFOPLIST_KEY_CFBundleDisplayName`); the store name carries a descriptor
because 2.3.7 requires a unique name and "Memento" alone is generic enough to
collide. No trademark, no competitor name, no Apple product name.

### Subtitle — `Private journal that reflects`

Shared across platforms, localizable. Makes no unverifiable claim: "reflects" is
a description of what the app does, not a performance assertion.

### Keywords — 99 characters

```
journal,diary,voice,memoir,reflection,notes,transcribe,dictation,memory,recall,writing,speech,daily
```

**Comma-separated with no spaces after commas** — spaces are allowed only
*within* a multi-word phrase, and a space after a comma wastes a character.
Deliberately excluded: the word "app"; the category name "Lifestyle"; plurals of
included singulars; any competitor name; and **wellness vocabulary**
("mindfulness", "gratitude", "self-care"), which would pull the product
positioning toward the line §3 above forbids.

### Promotional Text — the only free lever

**Editable at any time without submitting a new version.** Use it for launch
timing, seasonal messaging, or a known-issue notice. Everything else on the page
requires a version.

### Description

Structured for the truncated-first-paragraph reality: the first sentence is what
appears before "more". Sections: what it does (feature by feature), how it
handles your writing (the `REQ-POS-001` claim verbatim), **what it will not do**
(the anti-clinical statement), subscription disclosure, and device requirements.

**The subscription paragraph is required by Guideline 2.3.2** — in-app purchases
must be disclosed in the description. It states auto-renewal, the 24-hour
cancellation window, and where to manage it. It states no price, per 2.3.7.

**The requirements paragraph** is the honest handling of `DEC-001`: reflection
features need Apple Intelligence; capture, transcription, timeline, search, and
export do not. If `DEC-001` resolves to **Option B** (declare an Apple
Intelligence device requirement), this paragraph must change to say the app
requires such a device, and the requirement must be verified to actually gate
installs rather than merely warn.

### What's New

1.0 is a first release, so this is a feature list rather than a changelog. From
1.1 onward, Guideline **2.3.12** requires describing the actual changes; generic
text is acceptable only for pure bug-fix releases.

---

## 2. Editing workflow

1. Edit the `.txt` file, never this document.
2. Run the checks:
   ```
   python3 scripts/ci/lint_forbidden_phrases.py docs/app-store/metadata
   for f in docs/app-store/metadata/en-US/*.txt; do
     printf "%-24s %4d\n" "$(basename $f)" "$(( $(wc -m < "$f") - 1 ))"
   done
   ```
3. Update the counts table in §1.
4. Paste into App Store Connect.

`scripts/ci/check_asc_metadata.sh` runs both checks as a single gate.

---

## 3. Localization

**English (U.S.) only for 1.0.** This is a deliberate choice, not an oversight.

The app itself has no localization infrastructure — no `.lproj`, no `.xcstrings`
string catalog, all strings hardcoded — despite
`LOCALIZATION_PREFERS_STRING_CATALOGS = YES` in the project. Localized store
metadata in front of an English-only binary is a Guideline **2.3** accuracy
problem: the product page would promise an experience the app does not deliver.

Cost: reduced discoverability in non-English storefronts. Accept it for 1.0;
revisit when the app is localized. Apple derives the product page's "Languages"
list from the bundle's localizations, so the two must move together.

---

## 4. App icon

| Requirement | Status |
|---|---|
| 1024×1024 PNG in the asset catalog | ✅ `MeetMemento/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |
| Fully opaque, **no alpha channel** | ✅ Verified by spec 002 R2 (`sips -g hasAlpha` → `no`) |
| **Square, 90° corners** — do not pre-round | ✅ The system applies the mask |
| RGB | ✅ |

**Open design work:** the dark and tinted icon slots were **deliberately
removed** by spec 002 Task 2 — the previous "tinted" entry was a byte-identical
copy of the light icon and the dark slot was declared with no file. iOS falls
back to the light icon, which is valid but not ideal on iOS 26/27, where the
layered icon system and Icon Composer are the current direction. Producing real
dark and tinted variants is a design task, not a compliance blocker.

---

## 5. Screenshots

**1–10 per display size. `.jpg`/`.jpeg`/`.png`. No alpha channel or
transparency.** Apple will scale down from a larger display if a size is missing,
but the two below are the ones to actually produce.

| Display | Portrait | Required? |
|---|---|---|
| **iPhone 6.9″** (iPhone Air, 17 Pro Max, 16 Pro Max, 16 Plus, 15 Pro Max, 15 Plus, 14 Pro Max) | **1320 × 2868** | ✅ **Required** — the app runs on iPhone |
| **iPad 13″** (iPad Pro M4/M5, iPad Air M2–M4) | **2064 × 2752** | ✅ **Required** — `TARGETED_DEVICE_FAMILY = "1,2"` |
| iPhone 6.5″ | 1284 × 2778 | Only if 6.9″ is not provided |
| Everything else | — | Optional |

**Content rules:**

- **2.3.3** — must show the app **in use**. Not the launch screen, not title art.
  Memento has no login, so the first legitimate screen is the journal or capture
  surface.
- **2.3.9** — **fictional content only.** Journal entries visible in screenshots
  must be invented. This is not merely a privacy nicety: real entries in a
  screenshot are personal data published on a product page.
- Text overlays and device frames are permitted; they must highlight, not
  obscure, the actual UI.
- The UI shown must match the shipping build. Apple's common-rejection #7 is
  inaccurate screenshots.

**Recommended sequence (5 shots):** capture with the live recording indicator
visible (which doubles as evidence for Guideline **2.5.14**, `01` §2.5.14) →
timeline → a weekly reflection with its citations → Patterns → Ask answering a
question with sources.

**The alternative worth considering:** dropping `TARGETED_DEVICE_FAMILY` to
iPhone-only removes the iPad screenshot requirement and the obligation to make
every surface look right on a 13″ canvas. The trade-off is losing iPad users and
contradicting Guideline **2.4.1**'s preference that iPhone apps run on iPad where
possible. **Recommendation: keep iPad** — the app is a writing tool and the large
canvas suits it — and budget for the second screenshot set.

---

## 6. App previews — optional for 1.0

Not required. If one ships:

| Spec | Value |
|---|---|
| Count | Up to **3** per localization and display size |
| Duration | **15–30 seconds** |
| Max file size | **500 MB** |
| Resolution (iPhone 6.9″/6.5″/6.3″/6.1″) | **886 × 1920** portrait |
| Resolution (iPad 13″) | **1200 × 1600** portrait |
| Frame rate | **≤30 fps** |
| Codec | H.264 (10–12 Mbps, High Profile ≤4.0) or ProRes 422 HQ |
| Audio | 256 kbps AAC, 44.1 or 48 kHz; all tracks enabled |
| Poster frame | Defaults to 5 s |

**Guideline 2.3.4 — screen captures of the app only.** Narration and text
overlays are allowed; staged footage of a person using a phone is not. Previews
**autoplay muted**, so the first few seconds must work without sound — which
matters for an app whose most cinematic moment is speech becoming text.

---

## 7. Custom product pages and A/B testing

Available and unused for 1.0. Up to 35 custom product pages with alternate
screenshots, previews, and promotional text, each with its own URL — useful for
matching a landing page or a campaign to a specific store page. Product Page
Optimization can A/B test icon, screenshots, and previews against a percentage of
users, with results in App Analytics. Both are post-launch levers; noted so a
future session knows they exist.

---

## Verification

- [ ] `python3 scripts/ci/lint_forbidden_phrases.py docs/app-store/metadata` → OK.
- [ ] Every count in §1 is within limit and matches the file on disk.
- [ ] Grep of `docs/app-store/metadata/` for clinical vocabulary (`therapy`,
      `mental health`, `wellbeing`, `anxiety`, `depression`, `heal`, `coach`)
      and for competitor names returns nothing.
- [ ] Grep of the same for a `$` or a digit followed by `%` returns nothing
      (no pricing, no unverifiable accuracy claim).
- [ ] The subscription paragraph in `description.txt` states auto-renewal, the
      24-hour cancellation window, and where to manage it (2.3.2).
- [ ] The device-requirement paragraph matches whichever branch `DEC-001` took.
- [ ] Screenshots exist at **1320 × 2868** and **2064 × 2752**, contain only
      fictional entries, show the app in use, and one of them shows the recording
      indicator.
- [ ] App icon: `sips -g format -g hasAlpha` → `png` / `hasAlpha: no`.
