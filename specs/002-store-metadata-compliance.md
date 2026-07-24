---
id: 002
title: Store Metadata and Binary Compliance
tier: P0
status: paused (2026-07-23)
effort: 1-2 sessions
depends_on: [001]
findings: [missing-encryption-compliance-key, jpg-app-icons, empty-dark-icon-slot, white-accent-color, sample-targets-in-project, duplicated-usage-strings, asc-support-url-gap]
---

# 002 — Store Metadata and Binary Compliance

**Paused (2026-07-23):** the completed hygiene work in this spec (encryption
compliance key, PNG icons, sample-target removal, deduplicated usage strings,
bundle cleanup) is generic App Store hygiene, not backend-specific, and remains
valid — do not redo it. What's paused is the remaining ASC-submission work (Task 8
archive/validate, the support-email decision, the App Review demo account) since
there's no build worth submitting to App Store Connect until a Memento 2.0 (or
interim) build exists to submit. Resume when that build is ready.

**Superseded rows (2026-07-23, spec 023):** Memento 2.0 has **no accounts** — the
"app requires sign-in" premise behind this spec's demo-account requirement no
longer holds. On resume: the ASC checklist's "Demo account for App Review" row is
**moot** (guideline 2.1 only applies to sign-in-gated apps — review notes should
instead explain the optional app-lock/PIN); the App Review notes row's "AI
features call Supabase backend" wording is obsolete (on-device + Apple PCC); the
Sign in with Apple mention is obsolete.

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

| 7 | **(found during implementation, 2026-07-13)** The Release app bundle shipped junk via the `MeetMemento/` synchronized group: 5 SQL migration files (from a previously unknown **third** migrations dir nested at `MeetMemento/supabase/` — see spec 003), `Debug/Release.xcconfig` + templates, `config.toml`, `cli-latest`, `PLAN.md`, `File.txt`, `Configuration.storekit`, `PreviewMocks.json`, dev docs (`COMPONENT_TEMPLATE.md`, `UTILITIES_GUIDE.md`, `MonthlyInsightCard+Usage.md`, `Fonts/README.md`), a loose `Google-Icon.svg`, and `SupabaseConfig.swift.template`. Shipping DB schema + internal docs in the binary is information disclosure and submission noise. | verified via Release bundle listing | HIGH |
| 8 | **(found during implementation)** All four xcconfig files had the `//`-comment trap: `SUPABASE_URL = https://…` truncates to `https:` because xcconfig treats `//` as a comment — so following the documented local-xcconfig setup produced a silently broken backend URL. | `MeetMemento/Config/*` | HIGH (latent) |

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

- Account deletion actually working (guideline 5.1.1(v)) → was **spec 003**;
  spec 003 is now obsolete (2026-07-23) — see **spec 015** (data layer /
  export-and-deletion, `REQ-DATA-013`) for the 2.0 equivalent.
- Privacy of release logs → **spec 005**.
- Screenshot/marketing asset production — real ASC listing work, not repo work; the
  R6 checklist records it as an external TODO.

## Tasks

- [x] 1. Add `ITSAppUsesNonExemptEncryption` = `false` to `MeetMemento/Info.plist`. (R1)
      ✅ Verified in built product's Info.plist.
- [x] 2. Icons: light JPG converted to PNG via sips (1024×1024, `hasAlpha: no`); the
      empty dark slot and the byte-identical fake "tinted" entry **removed** from
      `Contents.json` (R2 allows removal; iOS falls back to the light icon). Real
      dark/tinted artwork can be added later as a design task. (R2)
- [x] 3. `AccentColor` set to brand primary: light `#7B3EC9` (primary500), dark
      `#9869D5` (primary400) — mirrors `Theme.swift`'s per-scheme `theme.primary`. (R3)
- [x] 4. All four sample targets removed via `xcodeproj` gem (targets, build phases,
      configs, product refs, `TargetAttributes`, groups). **Notable finding during
      re-verify:** the app target *depended on and embedded* `Sign In with Apple.appex`
      — a 100% inert Apple sample extension (© 2020, every override commented out) that
      was shipping inside the app bundle. Dependency + "Embed Foundation Extensions"
      phase removed; built product now has no `PlugIns/` dir. Source folders deleted
      from disk; stale `Sign In with Apple.xcscheme` deleted. `xcodebuild -list` shows
      only MeetMemento + its two test targets. (R4)
- [x] 5. `INFOPLIST_KEY_NS{Microphone,SpeechRecognition}UsageDescription` deleted from
      Debug + Release build settings; final wording settled in `Info.plist` (unified to
      display name "Memento"). (R5)
- [x] 6. `support.html` → `docs/support.html` (GitHub Pages root); support link added to
      `docs/index.html`. ⚠️ Mailbox verification is a user action — see checklist:
      three different addresses are currently in circulation. (R6)
- [x] 7. ASC metadata checklist written (bottom of this spec). (R6)
- [x] 9. **(added during implementation)** Bundle hygiene: stray `File.txt` deleted;
      nested `MeetMemento/supabase/` moved to `supabase/UNRECONCILED-app-folder-copy/`
      (content untouched — spec 003 reconciles it; its `.temp/` cache and empty
      `functions/` dir dropped); everything else excluded from the app target via the
      synchronized-group exception set (note: **directory-level membershipExceptions
      don't work** — files must be listed individually). Clean Release rebuild verified:
      bundle now contains only binary, plists, assets, fonts, launch storyboard,
      `AISuggestionPrompts.json`, `welcome-bg.mp4`, and the crypto dependency bundle.
      (evidence row 7)
- [x] 10. **(added during implementation)** Fixed the xcconfig `//`-comment trap in all
      four Config files using the `$()` empty-substitution escape
      (`https:/$()/…`), with explanatory comments; verified the full URL now reaches
      the built Info.plist. (evidence row 8; spec 006's CI assertion still pending)
- [ ] 8. Archive → validate via Xcode Organizer "Validate App" against ASC.
      **BLOCKED (user action):** archive signing fails with *"PLA Update available —
      agree to the latest Program License Agreement"* at developer.apple.com, after
      which the team provisioning profile can regenerate. Release device build compiles
      clean (`CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED), so only signing +
      Organizer validation remain. (all)

## ASC metadata checklist (Task 7)

Enter/verify in App Store Connect when creating the TestFlight/App Store record:

| Field | Value | Status |
|-------|-------|--------|
| Bundle ID | `com.sebastianmendo.MeetMemento` | in project ✅ |
| Display name | Memento | in project ✅ |
| Category | Lifestyle (`public.app-category.lifestyle`) | in project ✅ |
| Privacy Policy URL | `https://sebmendo1.github.io/MeetMemento/privacy.html` | live, linked in-app ✅ |
| Support URL | `https://sebmendo1.github.io/MeetMemento/support.html` | file hosted this spec — **confirm it renders after push** |
| Marketing URL (optional) | `https://sebmendo1.github.io/MeetMemento/` | live ✅ |
| Export compliance | `ITSAppUsesNonExemptEncryption=false` in plist — answer "None of the above / standard encryption" if asked | ✅ |
| Support email | ⚠️ **DECIDE + VERIFY**: three addresses in circulation — in-app `support@sebastianmendo.com` (`AboutSettingsView.swift`, `DataUsageInfoView.swift`), support page `support@meetmemento.app`, account `contact@sebastianmendo.design`. Pick one, update the other surfaces, send/receive test. | ☐ user |
| Demo account for App Review | **MANDATORY** (app requires sign-in, guideline 2.1). Create a reviewer account (email+OTP is interactive — provide a test account with a fixed OTP path, or note Sign in with Apple; consider a review-notes explanation of the PIN step and provide the PIN). | ☐ user |
| Age rating questionnaire | Expect 4+/9+: no UGC sharing (journal is private), no web browsing, AI chat is grounded on user's own content — answer "infrequent/mild" only if applicable | ☐ user |
| Screenshots | 6.7" + 6.1" (+ iPad if keeping iPad support — note: project targets iPhone+iPad, so iPad screenshots are REQUIRED unless `TARGETED_DEVICE_FAMILY` drops to iPhone-only) | ☐ user |
| App Review notes | Mention: PIN/FaceID lock (give PIN), mic/speech used for voice journaling, AI features call Supabase backend | ☐ user |
| Prior rejection context | `.archive/APP_STORE_REJECTION_FIX.md` — review before submitting | ☐ user |

## Verification

- [x] Built product's `Info.plist` shows `ITSAppUsesNonExemptEncryption => false`
      (verified via `plutil -p` on the Debug product; key is in the source plist so it
      carries to archives). ✅ 2026-07-13
- [x] `sips -g format -g hasAlpha …/AppIcon.png` → `png` / `hasAlpha: no`; no `.jpg`
      remains; asset catalog compiled icon variants present in built product. ✅
- [x] `grep -c "com.testing" project.pbxproj` → 0; `xcodebuild -list` shows only
      MeetMemento/MeetMementoTests/MeetMementoUITests; built product has no
      `PlugIns/`. ✅
- [x] `grep -c "INFOPLIST_KEY_NSMicrophone" project.pbxproj` → 0. ✅
- [x] Debug sim build + unsigned Release device build both BUILD SUCCEEDED. ✅
- [ ] Xcode Organizer → Validate App — **user action** (blocked on accepting the
      Apple Program License Agreement at developer.apple.com; then archive + validate).
- [ ] Fresh simulator install: icon renders in light + dark home screens; mic
      permission dialog shows the final "Memento…" wording — quick user smoke check.

## Regression Guards

- `PrivacyInfo.xcprivacy` must remain in the app target's resources after target surgery.
- *(2026-07-23: this guard is superseded by spec 023, which removes the SIWA
  entitlement deliberately — the guard below protected against *accidental*
  removal during target surgery and is kept for historical accuracy only.)*
  Sign in with Apple **entitlement** (`MeetMemento/MeetMemento.entitlements`) is unrelated
  to the sample *target* — deleting the target must not touch the entitlement or
  `AppleSignInService.swift`. Re-test Apple sign-in after removal.
- Custom fonts (12 `UIAppFonts` entries) still load — check a couple of screens.
