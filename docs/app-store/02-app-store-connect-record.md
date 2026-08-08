# 02 — The App Store Connect record

**Compiled 2026-08-07.** Every field of the app record, with our value, who can
edit it, and its status.

**Sources:** [App Information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) ·
[Role permissions](https://developer.apple.com/help/app-store-connect/reference/role-permissions/) ·
[App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-and-submission-statuses)

---

## 1. Identity — immutable once set

| Field | Value | Note |
|---|---|---|
| **Bundle ID** | `com.sebastianmendo.MeetMemento` | **Immutable after the first build is uploaded.** Already uploaded — locked |
| **SKU** | *(record the existing value from App Store Connect)* | Internal only, immutable |
| **Apple ID (app)** | `6754416850` | Recorded in `MeetMemento/Views/Monetization/Configuration.storekit` as `_applicationInternalID` — confirm in App Store Connect |
| **Team ID** | `F3NM4HTMW8` | `DEVELOPMENT_TEAM` in `project.pbxproj` |
| **Primary language** | English (U.S.) | The fallback for every territory without a localization, and the language reviewers read first |
| **Display name** | **Memento** | `INFOPLIST_KEY_CFBundleDisplayName` — note this differs from the project/target name `MeetMemento` |

> The app record already exists — the November 2025 submission used it. This is a
> **new version** on an existing record, not a new app.

---

## 2. App Information

| Field | Value | Editor role | Status |
|---|---|---|---|
| **Primary category** | **Lifestyle** (`public.app-category.lifestyle`) | Account Holder / Admin / App Manager | ✅ Set in project; confirm in ASC |
| **Secondary category** | **Productivity** *(recommended)* | same | ☐ Decide |
| **Privacy Policy URL** | `https://<published-host>/privacy.html` | same | 🔴 Blocked — `00` A6, B2 |
| **User Privacy Choices URL** | *(leave blank)* | same | Optional; the in-app export/delete path serves this purpose |
| **Content Rights** | **No** third-party content | same | ☐ Confirm asset provenance first — `05` §5 |
| **Age Rating** | Expect **9+** | same | ☐ `05` §1 |
| **License Agreement** | Apple's standard EULA | same | ✅ Default. `TERMS_OF_SERVICE.md` is our own terms, published at `/terms.html`, and is additional to — not a replacement for — the EULA |
| **Routing App Coverage File** | N/A | — | Not a routing app |
| **DSA trader status** | *(decision pending)* | Account Holder / Admin | 🔴 `05` §4, `00` A5 |

### Why not Health & Fitness

Choosing **Health & Fitness** or **Medical** as a category invites Guideline
**1.4.1** scrutiny and moves the app toward **5.1.1(ix)**'s highly-regulated
fields, which says such apps *"should be submitted by a legal entity… and not by
an individual developer."* Memento is enrolled as an individual. **Lifestyle**
(or Productivity) is both accurate and the low-risk answer. See `01` §1.4.1.

---

## 3. Version information (per release)

| Field | Value | Status |
|---|---|---|
| **Version** | `1.0` | `MARKETING_VERSION` in `project.pbxproj`. Still usable — 1.0 was uploaded and rejected but **never released**, and Apple compares against the last *released* version |
| **Build** | must exceed **2** | `CURRENT_PROJECT_VERSION = 2` was consumed by the rejected upload. See `07` |
| **Copyright** | `2026 Sebastian Mendoza` | Year rights were obtained, then the owner's name. **No © symbol** — Apple adds it |
| **Support URL** | `https://<published-host>/support.html` | 🔴 Currently 404 in production — `00` B1 |
| **Marketing URL** | `https://<published-host>/` | Optional; the landing page is live |
| **Name / Subtitle / Keywords / Promotional Text / Description / What's New** | see `04` and `docs/app-store/metadata/en-US/` | ☐ Drafts written, not entered |
| **Screenshots** | iPhone 6.9″ + iPad 13″ | ☐ `04` §5 |
| **App Previews** | Optional for 1.0 | ☐ `04` §6 |
| **App Review Information** | contact, notes, attachments | ☐ `08` |
| **Version Release option** | **Manually release this version** | ☐ `10` §3 |
| **Price and tax category** | 🔒 Blocked on `DEC-004` | `specs/021` R1 |
| **Availability / territories** | 🔒 Blocked on the EU decision; exclude mainland China | `05` §7, `10` |

---

## 4. Usage strings — the wording that ships

Apple's own common-rejection #6 is *unclear data access requests*. These strings
are the one piece of privacy copy every user actually reads, so they carry the
on-device boundary too — which also serves Guideline **5.1.2(i)** (`01` §5.1.2).

Defined in **`MeetMemento/Info.plist` only** — the duplicate
`INFOPLIST_KEY_NS*UsageDescription` build settings were deleted by spec 002 R5
and must not come back (`GENERATE_INFOPLIST_FILE = YES` merges both, and the
winner is unpredictable).

| Key | Current | Recommended |
|---|---|---|
| `NSFaceIDUsageDescription` | "Memento uses Face ID to protect your private journal entries." | **Keep as is.** Specific, accurate, states what and why |
| `NSMicrophoneUsageDescription` | "Memento needs microphone access to transcribe your voice into journal entries." | "Memento uses the microphone to record voice entries. Your recordings are transcribed on your iPhone and are not stored on any server." |
| `NSSpeechRecognitionUsageDescription` | "Memento uses speech recognition to convert your voice to text for journaling." | "Memento uses speech recognition to turn your voice into journal text on your iPhone." |

> ⚠️ **The recommended microphone and speech strings are only true once
> `requiresOnDeviceRecognition` is resolved** (`00` C4, `specs/018` R1). Do not
> ship a purpose string that is more absolute than the code. If the
> `SpeechAnalyzer` migration has not landed, keep the current, weaker wording —
> an accurate vague string beats an inaccurate specific one.

**Strings to add only when the feature ships** (`01` §5.1.1(iii) — data
minimization): `NSPhotoLibraryUsageDescription` with spec 018 R5,
`NSLocationWhenInUseUsageDescription` with spec 018 R6. Never add
`NSUserTrackingUsageDescription` — see `03`.

---

## 5. Who can do what

| Action | Required role |
|---|---|
| Sign the Paid Apps Agreement; renew membership; create App Store Connect **API keys**; remove auto-renewable subscriptions from sale | **Account Holder only** |
| Enter DSA trader status | Account Holder or Admin |
| Create distribution certificates; manage identifiers and profiles | Account Holder or Admin |
| Edit App Information, App Privacy, pricing, metadata; upload builds; submit for review | Account Holder, Admin, or App Manager |
| Reply to App Review messages | Account Holder, Admin, or App Manager |
| Upload builds only | Developer |

Memento is a solo individual enrollment, so the enrollee is the Account Holder
and holds every one of these. The table matters because **rows marked `☐ user` in
`00` are exactly the ones that require an interactive App Store Connect or
developer.apple.com session** — an agent cannot close them.

---

## 6. Status reference

So a future session can read App Store Connect without guessing.

### App statuses

| Status | Means |
|---|---|
| **Prepare for Submission** | Record created, metadata still being entered |
| **Ready for Review** | All required metadata entered, not yet submitted |
| **Waiting for Review** | Apple has the submission, review not started. You may still edit *certain* metadata and remove the build from review; you **cannot** edit screenshots or previews |
| **In Review** | Being reviewed. You may still remove the build from review |
| **Invalid Binary** | The build does not meet current binary requirements — upload a new one |
| **Metadata Rejected** | The **binary is fine**; fix metadata in App Store Connect and reply. **No new build needed** — the cheap rejection |
| **Rejected** | Binary or behavior problem. Requires a new build with an incremented build number |
| **Developer Rejected** | You removed it from review |
| **Pending Developer Release** | Approved; you press the button (Manual release). Apple emails a reminder if it sits here **>30 days** |
| **Pending Apple Release** | Held until the corresponding OS version ships publicly — **this is what an iOS 27-GA-aligned launch will show** |
| **Processing for Distribution** | Approved and released; live within 24 hours |
| **Ready for Distribution** | Live — *"To distribute your app, your agreements must be in effect"* (see `00` A2) |
| **Waiting for Export Compliance** | A CCATS file is in Apple's review. N/A for us — `05` §3 |

### Submission statuses

`Waiting for Review` · `In Review` · `Processing` (you removed it) ·
**`Unresolved Issues`** (one or more items rejected) · `Rejected`.

### Submission concurrency

**One app-version submission under review at a time**, plus at most one
items-only submission (in-app purchases, in-app events, custom product pages).
Items from different platforms cannot share a submission. *"Submissions may not
be reviewed in the order submitted."*

---

## Verification

- [ ] Every field in §2 and §3 is either filled with the value recorded here or
      has a named blocker.
- [ ] Privacy Policy URL and Support URL both return `200` on the published host,
      and the Privacy Policy URL is also reachable from inside the app
      (`SettingsView.swift`).
- [ ] Category is Lifestyle; neither Health & Fitness nor Medical is selected.
- [ ] Copyright is `2026 Sebastian Mendoza` with no © symbol.
- [ ] `grep -c "INFOPLIST_KEY_NSMicrophone\|INFOPLIST_KEY_NSSpeech" MeetMemento.xcodeproj/project.pbxproj` → **0**
      (usage strings defined once, in `Info.plist`).
- [ ] Usage strings match §4 **and** are no more absolute than the code that
      backs them.
