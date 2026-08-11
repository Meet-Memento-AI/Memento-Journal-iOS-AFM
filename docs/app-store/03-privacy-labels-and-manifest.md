# 03 — Privacy labels, privacy manifest, and required-reason APIs

**Compiled 2026-08-07.**
**Sources:** [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) ·
[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) ·
[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) ·
[Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)

This is the document that prevents a repeat of the **November 2025 Guideline
5.1.2 rejection**, whose cause was App Store Connect privacy labels that
declared tracking the app does not perform.

---

## The consistency rule

Three artifacts must say **exactly the same thing**, and each is edited in a
different place by a different mechanism:

| Artifact | Where it lives | How it changes | Reviewed by |
|---|---|---|---|
| **App Privacy nutrition label** | App Store Connect → App Privacy | Editable **at any time, without shipping a build** | App Review, and every user on the product page |
| **`PrivacyInfo.xcprivacy`** | `MeetMemento/PrivacyInfo.xcprivacy` | Ships in the binary | Automated validation at upload (ITMS-9105x) |
| **Privacy policy** | `docs/privacy.html` (published), `PRIVACY_POLICY.md` (source) | Published to GitHub Pages | App Review, and legally binding on us |

The label being editable without a build is precisely how it drifted last time:
the binary changed, the label did not. **Any change to one of these three
requires checking the other two in the same session.** `00`'s "do not press
Submit until" item 3 is this rule.

---

## 1. The nutrition label

### Target: **Data Not Collected**

Apple's definition of "collect", verbatim:

> "transmitting data off the device in a way that allows you and/or your
> third-party partners to access it **for a period longer than what is necessary
> to service the transmitted request in real time**."

**On-device processing is not collection.** The argument for Memento:

| Data | Where it goes | Collected? |
|---|---|---|
| Journal entries, transcripts, reflections | SwiftData on device; mirrored to the **user's own CloudKit private database** | **No** — CloudKit private database is the user's iCloud account, not our infrastructure. We have no access to it |
| Audio | Live buffers only. `SpeechService.swift` uses `AVAudioEngine` + `SFSpeechAudioBufferRecognitionRequest` with `requiresOnDeviceRecognition = true`; there is **no `AVAudioRecorder`, no `.m4a`, no persisted audio file** | **No** — on-device recognition is required, see below |
| Display name | `LocalProfileStore`, `UserDefaults`, never transmitted | **No** |
| Model prompts and completions | On-device (Z0) or **Apple Private Cloud Compute** (Z1), which stores nothing | **No** |
| Analytics | **There is no analytics SDK.** Study telemetry is collected manually via surveys and interviews (`REQ-EVAL-005`) | **No** |
| Crash and performance data | Apple's own, opt-in at the OS level, never surfaced to us via an SDK | **No** |

Corroborating evidence: `grep -rn "URLSession" MeetMemento --include="*.swift"`
returns **zero hits** (2026-08-07). The only outbound calls in shipping code are
two `UIApplication.shared.open` links to the privacy policy and terms.

### The two things that can break "Data Not Collected"

**1. `SFSpeechRecognizer` without `requiresOnDeviceRecognition = true`.**
**RESOLVED (2026-08-11, previously stale).** `MeetMemento/Services/SpeechService.swift`
**does** set `request.requiresOnDeviceRecognition = true` (see the comment block
at the call site: "Keep audio on the device"), so recognition cannot be routed
to Apple's servers; unavailable locales surface an error rather than a silent
off-device path. Spec 018 R1's `SpeechAnalyzer` migration remains the 2.0 plan,
but the 1.x label is safe on this point. (This paragraph previously claimed the
flag was unset — that was out of date, not a code change.)

**2. RevenueCat, if spec 021 ships it.** `REQ-MON-004` / **V8** is an open
verification item: does RevenueCat's SDK itself trigger a collection disclosure
for purchase data? **This document does not decide it** — `specs/021` R5 owns the
decision and the priority ordering is already recorded there: *if RevenueCat
forces a disclosure, evaluate StoreKit 2 direct and accept the loss of subscriber
analytics — the label is worth more than the dashboard.*

The ground-truth procedure (spec 021 R5, not closeable from documentation
reading): inspect the pinned RevenueCat SDK's own bundled privacy manifest, then
confirm against App Store Connect's aggregated privacy report on an archived
build with the SDK integrated.

### If a disclosure does become necessary

Should V8 or any future integration force a declaration, the fields to answer are
below. **This is a contingency table, not our current answer.**

| Axis | Answer if RevenueCat ships and discloses |
|---|---|
| Data type | **Purchases → Purchase History** |
| Linked to the user? | **Not Linked** — the RevenueCat anonymous app-user ID is the only identifier that exists (spec 021 R3 forbids introducing a stable custom ID) |
| Used for tracking? | **No** — and therefore **no ATT, and no `NSUserTrackingUsageDescription`** |
| Purpose | App Functionality |

**Never declare tracking.** Declaring tracking obliges us to implement App
Tracking Transparency; declaring it *without* implementing ATT is the exact
November 2025 rejection.

### Data types we must never accumulate

- **Sensitive Info → biometric data.** A persisted speaker embedding or voice
  print for diarization would land here. Do not persist anything off-device that
  identifies a speaker.
- **Health & Fitness → Health.** Attaches only if `DEC-006` brings HealthKit
  State of Mind into prompts. See `01` §5.1.3.
- **Location → Precise/Coarse.** Attaches with spec 018 R6.

---

## 2. `PrivacyInfo.xcprivacy`

### Current state (verified 2026-08-07)

```
NSPrivacyTracking            = false                    ✅
NSPrivacyTrackingDomains     = []                       ✅
NSPrivacyCollectedDataTypes  = []                       ✅  (already corrected — do not redo)
NSPrivacyAccessedAPITypes:
  UserDefaults    → CA92.1                              ✅  justified
  FileTimestamp   → C617.1                              ✅  justified
  SystemBootTime  → 35F9.1                              🔴 NOT justified — remove
```

> The stale `EmailAddress` / `Name` / `UserID` / `UserContent` collected-data
> entries described in older notes are **gone**. The file now carries an empty
> array with an on-device-only comment. `CONSTITUTION.md` §2's "stale
> `.xcprivacy`" flag is satisfied on that point; the `SystemBootTime` row below
> is what remains.

### The rule

**Declare exactly what you call.** Under-declaring produces `ITMS-91053` at
upload. Over-declaring produces no error — which is why it survives — but it is
an inaccuracy in exactly the metadata category we were rejected on, and a
reviewer comparing the manifest to the binary has grounds to ask.

### Row-by-row justification

| Category | Reason | Justified by | Verdict |
|---|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` — "access user defaults in **just your app**" | **11 files** use `UserDefaults` (`AppStateStore.swift`, `PreferencesService.swift`, `LocalProfileStore.swift`, `SecurityService.swift`, `PromptRegistry.swift`, plus view models and views) | ✅ **Keep.** Switch to (or add) `1C8F.1` **only if** spec 020's widgets introduce a shared App Group suite — there is no `suiteName` usage today |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` — "access timestamps, size, or other metadata of files inside the app container" | `MeetMemento/Services/LocalJournalStorage.swift:118-121` — `fileManager.attributesOfItem(atPath:)` → `.modificationDate`, on files inside the app container. Consumed by `JournalService.swift:133,170` | ✅ **Keep.** `C617.1` is precisely the right reason for container-internal metadata |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | **Nothing.** `grep -rn "systemUptime\|mach_absolute_time\|kern.boottime" MeetMemento --include="*.swift"` → no matches | 🔴 **Remove.** The comment claims "for security features"; `SecurityService.swift` uses Keychain and constant-time comparison, not boot time |
| `NSPrivacyAccessedAPICategoryDiskSpace` | — | Not declared, and not used — `grep -rn "volumeAvailableCapacity\|systemFreeSize\|attributesOfFileSystem"` → no matches | ✅ **Correctly absent.** Add `E174.1` **only if** capture starts checking free space before recording — a plausible future requirement for long sessions |
| `NSPrivacyAccessedAPICategoryActiveKeyboards` | — | Not used | ✅ Correctly absent |

### Target state — the diff

Remove this block from `MeetMemento/PrivacyInfo.xcprivacy`:

```xml
<!-- System Boot Time: For security features -->
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
        <string>35F9.1</string>
    </array>
</dict>
```

Everything else stays. Enforced by `scripts/ci/check_privacy_manifest.sh`, which
checks **both directions** — every declared category has a call site, and every
required-reason API used in source is declared.

### Reference — reason codes we may plausibly need

| Category | Code | Meaning |
|---|---|---|
| UserDefaults | `CA92.1` | Access user defaults in just your app |
| UserDefaults | `1C8F.1` | Access user defaults shared across an **App Group** |
| FileTimestamp | `C617.1` | Metadata of files inside the app / App Group / CloudKit container |
| FileTimestamp | `DDA9.1` | Display file timestamps to the user; must not leave the device |
| FileTimestamp | `3B52.1` | Files the user specifically granted access to (document picker) |
| DiskSpace | `E174.1` | Check sufficient space to write, or low-space cleanup |
| DiskSpace | `85F4.1` | Display disk space to the user |
| SystemBootTime | `8FFB.1` | Compute absolute timestamps of in-app events; boot time itself must not leave the device |

> **Verify against the SDK, not from memory.** Apple's reason-code page is
> JS-rendered and does not always fetch cleanly. Xcode's property-list editor
> autocompletes the canonical set for the installed SDK — that is the safest
> source of truth. Codes are versioned.

---

## 3. Third-party SDK obligations

Since **May 1, 2024**, uploading requires approved reasons for required-reason
APIs used by the app **or any third-party SDK it links**, and SDKs on Apple's
published list must ship **both a privacy manifest and a signature**.

### Our current dependency surface

| Package | Linked? | On Apple's list? | Obligation |
|---|---|---|---|
| `SVGKit/SVGKit` 3.0.0 | Yes (`project.pbxproj`) | **No** | None. Off `specs/dependency-allowlist.txt` — needs a `REQ-MON-005` decision record or removal |
| `dominikmartn/ProgressiveBlurHeader` (branch `main`) | Yes — the only third-party `import` in the app | **No** | None. Same allowlist status |
| `CocoaLumberjack` 3.9.0 | Transitive (SVGKit), not imported | **No** | None |
| `apple/swift-log`, `nikstar/VariableBlur` | Pinned in `Package.resolved`, not linked | — | None; candidates for removal |

**No third-party privacy manifest or signature requirement applies today.** None
of the linked packages appears on Apple's list.

### The one that changes this

**RevenueCat (`purchases-ios`) is on Apple's list.** If spec 021 lands it, three
obligations attach at once:

1. Its bundled `PrivacyInfo.xcprivacy` must be present — pin a version that ships
   one.
2. It must be used as a **signed** binary dependency.
3. Its declared collected-data types merge into **our** label (Apple: you are
   responsible for your third-party partners' disclosures). This is V8.

Failure modes to expect: `ITMS-91061` (missing SDK privacy manifest),
`ITMS-91053/91054/91055` (API declaration family). See `07`.

**Rule going forward:** any new third-party dependency requires a check against
[Apple's list](https://developer.apple.com/support/third-party-SDK-requirements/)
*before* it is added, recorded alongside the `REQ-MON-005` decision record that
`specs/021` R6 already requires. The dependency-allowlist CI check
(`scripts/ci/check_dependency_allowlist.sh`) is the enforcement point; it runs
report-only today and becomes a hard gate before Gate S.

---

## 4. Entering the label in App Store Connect

**Where:** App Store Connect → your app → **App Privacy** → Edit.
**Who:** Account Holder, Admin, or App Manager.
**When:** any time — it does not require a build, which is both the convenience
and the hazard.

Steps for the target state:

1. Privacy Policy URL — the published, corrected policy (`00` B2, A6).
2. Data collection question → **"Data Not Collected"**, assuming V8 resolves
   favorably or RevenueCat is not shipped.
3. Save, then **re-read the product page preview** and confirm it says what the
   `.xcprivacy` and the policy say.
4. Record the date and the answer in `00` D6, with a screenshot path as evidence.

If V8 forces a disclosure, use the contingency table in §1 and update all three
artifacts in the same session.

---

## Verification

- [ ] `grep -c "SystemBootTime" MeetMemento/PrivacyInfo.xcprivacy` → **0**.
- [ ] `scripts/ci/check_privacy_manifest.sh` passes, and fails on a planted
      violation in **both** directions (a declared-but-unused category, and a
      used-but-undeclared API).
- [ ] `grep -rn "NSUserTrackingUsageDescription" .` → no matches in any plist.
- [ ] `grep -rn "URLSession" MeetMemento --include="*.swift"` → no matches, or
      every hit is accounted for in this document and the privacy policy.
- [ ] The App Store Connect privacy label, `MeetMemento/PrivacyInfo.xcprivacy`,
      and the published privacy policy all state the same thing — checked
      together, in one session, with the date recorded.
- [ ] V8's verdict is recorded in `specs/021` R5 and mirrored to
      `specs/reference/technology/11-verification-queue.md` before the label is
      submitted.
- [ ] If RevenueCat is linked: its bundled privacy manifest is present, the
      dependency is signed, and its declared data types are merged into our label.
