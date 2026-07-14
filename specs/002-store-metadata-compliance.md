---
id: 002
title: Store Metadata and Binary Compliance
tier: P0
status: not-started
effort: 1-2 sessions
depends_on: [001]
findings: [missing-encryption-compliance-key, jpg-app-icons, empty-dark-icon-slot, white-accent-color, sample-targets-in-project, duplicated-usage-strings, asc-support-url-gap]
---

# 002 — Store Metadata and Binary Compliance

## Why

These are the findings that App Store Connect itself checks: the missing encryption
compliance key prompts on **every** upload, JPG app icons risk validation warnings,
and two sample/playground targets with `com.testing.*` bundle ids live in the project
alongside the shipping app. Fixing this batch means the first TestFlight archive
uploads and processes cleanly. Blocks **Gate 1**. Prior rejection history in
`.archive/APP_STORE_REJECTION_FIX.md` is relevant context.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | `ITSAppUsesNonExemptEncryption` not set anywhere → encryption-compliance prompt/warning on every ASC upload. App uses HTTPS/standard crypto only (PBKDF2 via CommonCrypto, ATS-only networking), so `false` is the correct declaration. | `MeetMemento/Info.plist` (absent); `grep -r ITSApp` → empty | BLOCKER |
| 2 | App icons are **JPG**: light = `AppIcon.jpg`, tinted = `AppIcon 1.jpg` (byte-identical copy of light, not actually tinted), and the declared **dark slot has no file**. Apple expects PNG without alpha; JPG risks upload warnings, and the empty dark declaration is untidy. | `MeetMemento/Assets.xcassets/AppIcon.appiconset/Contents.json` + `.jpg` files | HIGH |
| 3 | `AccentColor` is pure white (1,1,1,1) — invisible tint on light backgrounds. | `MeetMemento/Assets.xcassets/AccentColor.colorset/Contents.json` | MEDIUM |
| 4 | Extra targets in the project: `Sign In with Apple` (Apple sample-code target, bundle id `com.sebastianmendo.MeetMemento.Sign-In-with-Apple`) and `UIPlayground`/`UIPlaygroundTests`/`UIPlaygroundUITests` (bundle ids under `com.testing.*`). Submission noise; must never enter the archive. | `MeetMemento.xcodeproj/project.pbxproj` targets list | HIGH |
| 5 | Microphone/speech usage strings defined **twice with different wording**: pbxproj `INFOPLIST_KEY_NS{Microphone,SpeechRecognition}UsageDescription` ("…transcribe your journal entries using voice") vs `Info.plist` ("…transcribe your voice into journal entries"). `GENERATE_INFOPLIST_FILE = YES` merges both — winner unpredictable. | `project.pbxproj:908-909,944-945` vs `MeetMemento/Info.plist:44-47` | MEDIUM |
| 6 | ASC listing needs a **Support URL** — only a support email is wired in-app (`support@sebastianmendo.com`, which differs from the dev account email; mailbox unverified). A ready support page exists at repo root (`support.html`) but is not hosted at a known URL. | `AboutSettingsView.swift:274`, `DataUsageInfoView.swift:242`, root `support.html` | MEDIUM |

Also note (verified fine, no action): `PrivacyInfo.xcprivacy` complete; FaceID/mic/speech
strings present; ATS on; `LaunchScreen.storyboard` wired; portrait-only iPhone +
all-orientation iPad is intentional.

## Requirements

### R1. Encryption compliance declared
**Acceptance:** `ITSAppUsesNonExemptEncryption = false` present in the **built product's**
Info.plist (`plutil -p` on the archived app), and ASC upload no longer asks the export
compliance question.

### R2. App icon set is PNG, complete, and intentional
**Acceptance:** all icon entries are PNG without alpha channel
(`sips -g hasAlpha` → no); dark slot either has a real dark variant or the
declaration is removed; tinted slot has a real grayscale-tinted variant or is removed;
asset catalog compiles with zero icon warnings; archive passes ASC processing.

### R3. AccentColor is a real brand color
**Acceptance:** AccentColor matches the app's primary brand color in light and dark;
system-tinted controls (alerts, toggles, links not styled by the theme) are visible.

### R4. Only shipping targets can enter the archive
**Acceptance:** the `MeetMemento` scheme's archive action builds only the app target;
`Sign In with Apple` and `UIPlayground*` targets are either deleted (preferred — the
sample code has served its purpose) or clearly isolated from the Release/archive path;
no `com.testing.*` bundle id remains in the project.

### R5. One source of truth per Info.plist key
**Acceptance:** each usage-description string is defined in exactly one place
(recommend: keep them in `Info.plist`, delete the `INFOPLIST_KEY_*` duplicates from
build settings); wording reviewed once for accuracy ("Memento uses the microphone and
speech recognition to transcribe your voice into journal entries" style).

### R6. Support URL live and ASC checklist written
**Acceptance:** `support.html` hosted (e.g. `https://sebmendo1.github.io/MeetMemento/support.html`
— move it into `docs/` which is already the GitHub Pages root); the support mailbox
confirmed working (send/receive test); a short ASC metadata checklist committed in this
spec (support URL, privacy URL, category, age rating inputs, review notes + demo
account for the reviewer — the app requires sign-in, so **a demo account or App Review
bypass note is mandatory** per guideline 2.1).

## Out of Scope

- Account deletion actually working (guideline 5.1.1(v)) → **spec 003**.
- Privacy of release logs → **spec 005**.
- Screenshot/marketing asset production — real ASC listing work, not repo work; the
  R6 checklist records it as an external TODO.

## Tasks

- [ ] 1. Add `ITSAppUsesNonExemptEncryption` = `false` to `MeetMemento/Info.plist`. (R1)
- [ ] 2. Export/produce 1024×1024 PNG (no alpha) icons: light, dark, tinted. Replace the
      JPGs, fix `Contents.json`, delete stale files. (R2)
- [ ] 3. Set `AccentColor` to the brand primary (match `Theme.swift`'s primary token),
      with a dark-appearance variant if needed. (R3)
- [ ] 4. Remove the `Sign In with Apple` and `UIPlayground*` targets from
      `MeetMemento.xcodeproj` (delete target + source folders if truly dead; keep the
      folders out of the app target's compile sources either way). Verify the shared
      `MeetMemento` scheme archive-builds only the app. (R4)
- [ ] 5. Delete `INFOPLIST_KEY_NSMicrophoneUsageDescription` and
      `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` from all build configurations;
      settle final wording in `Info.plist`. (R5)
- [ ] 6. Move `support.html` → `docs/support.html`; verify it renders on GitHub Pages;
      test the support mailbox round-trip. (R6)
- [ ] 7. Write the ASC metadata checklist (bottom of this spec): support URL, privacy
      URL (`…/privacy.html` — already live), category `lifestyle`, age-rating answers,
      demo account for review, export compliance answer. (R6)
- [ ] 8. Archive → validate via Xcode Organizer "Validate App" against ASC. (all)

## Verification

- [ ] `plutil -p <archive>/Products/Applications/MeetMemento.app/Info.plist | grep ITSApp`
      → `false`.
- [ ] `sips -g format -g hasAlpha MeetMemento/Assets.xcassets/AppIcon.appiconset/*.png`
      → `png` / `hasAlpha: no` for every file; no `.jpg` remains in the appiconset.
- [ ] `grep -c "com.testing" MeetMemento.xcodeproj/project.pbxproj` → 0.
- [ ] `grep -c "INFOPLIST_KEY_NSMicrophone" MeetMemento.xcodeproj/project.pbxproj` → 0.
- [ ] Xcode Organizer → Validate App passes with no icon or plist warnings.
- [ ] Fresh simulator install: app icon renders correctly in light + dark home screens;
      mic permission dialog shows the final wording.

## Regression Guards

- `PrivacyInfo.xcprivacy` must remain in the app target's resources after target surgery.
- Sign in with Apple **entitlement** (`MeetMemento/MeetMemento.entitlements`) is unrelated
  to the sample *target* — deleting the target must not touch the entitlement or
  `AppleSignInService.swift`. Re-test Apple sign-in after removal.
- Custom fonts (12 `UIAppFonts` entries) still load — check a couple of screens.
