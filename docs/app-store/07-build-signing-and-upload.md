# 07 — Build, signing, and upload

**Compiled 2026-08-07.**
**Sources:** [Submitting apps](https://developer.apple.com/app-store/submitting/) ·
[Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) ·
[Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) ·
[App build statuses](https://developer.apple.com/help/app-store-connect/reference/app-build-statuses/)

**Current state: there is no release automation.** No fastlane, no
`ExportOptions.plist`, no archive or upload script, no App Store Connect API key.
Every upload has been a manual Xcode Organizer action with no reproducible record
and no pre-upload validation. `specs/002` Task 8 — "Archive → validate via Xcode
Organizer" — has been open since 2026-07-13, blocked on an unaccepted Program
License Agreement.

This document is the pipeline that replaces that.

---

## 1. Hard requirements at upload time

| Requirement | In force since | Our position |
|---|---|---|
| Built with **Xcode 26 or later**, using an **iOS 26+ SDK** | **2026-04-28** | ✅ We build with the Xcode 27 beta toolchain — see the project's toolchain note. Uploads from an older Xcode are **rejected**, not warned |
| **Privacy manifest** with approved reasons for required-reason APIs, in the app **and every listed third-party SDK** | 2024-05-01 | ✅ `MeetMemento/PrivacyInfo.xcprivacy` — but remove the unjustified `SystemBootTime` row first (`03`) |
| Listed third-party SDKs must be **signed** | 2024-05-01 | ✅ N/A — none of our packages is on Apple's list. Changes if RevenueCat ships (`03` §3) |
| Age-rating questionnaire answered | 2026-01-31 | ☐ `05` §1 |
| Social-media capability declared | **2026-09** | ☐ `05` §2 — weeks away |
| EU DSA trader status | 2025-02-17 | ☐ `05` §4 |

---

## 2. Version and build numbering

Apple compares `CFBundleShortVersionString` against the **last version actually
released on the App Store**, not the highest ever uploaded.

**Our situation.** `1.0` build `2` was uploaded in November 2025 and **rejected —
never released.** Therefore:

- **`1.0` is still available** as a version string. Nothing was released, so
  there is no floor to exceed.
- **`CURRENT_PROJECT_VERSION` must exceed `2`**, because build numbers are
  consumed permanently per version string — even by builds that were rejected or
  deleted.

| Setting | Current | Target |
|---|---|---|
| `MARKETING_VERSION` | `1.0` | `1.0` — keep |
| `CURRENT_PROJECT_VERSION` | `2` | **≥ 3** |

**Rules to keep:**
- `CFBundleShortVersionString` is at most **three dot-separated components,
  digits only**. `1.0`, `1.0.1`, `1.4.332` are valid; `1.0b`, `1.0.0.1` are not.
- Violations produce **ITMS-90062**.
- Disable `manageAppVersionAndBuildNumber` in `ExportOptions.plist` if you want
  build numbers to come deterministically from the project rather than from
  Xcode's auto-increment.

`scripts/ci/check_store_metadata.sh` enforces the floor against a committed
last-uploaded record so this cannot silently regress.

---

## 3. The pipeline

### 3.1 Archive

```sh
xcodebuild \
  -project MeetMemento.xcodeproj \
  -scheme MeetMemento \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/MeetMemento.xcarchive \
  archive
```

Run under the pinned toolchain (`DEVELOPER_DIR=…`), as `ios-build-online.yml`
already does.

### 3.2 Export

`ExportOptions.plist` lives at [`docs/app-store/ExportOptions.plist`](ExportOptions.plist) — it does not contain secrets:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>F3NM4HTMW8</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
```

> `method` is `app-store-connect` on Xcode 15+; older Xcode used `app-store`.

```sh
xcodebuild -exportArchive \
  -archivePath build/MeetMemento.xcarchive \
  -exportOptionsPlist docs/app-store/ExportOptions.plist \
  -exportPath build/export
```

### 3.3 Validate — **do this before every upload**

```sh
xcrun altool --validate-app \
  -f build/export/MeetMemento.ipa \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"
```

**ITMS errors are returned at validation time, not review time.** Validating
costs nothing and does not consume a build number; discovering `ITMS-91053`
after an upload does. This is the single highest-value addition to the current
process.

### 3.4 Upload

```sh
xcrun altool --upload-app \
  -f build/export/MeetMemento.ipa \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"
```

Xcode 14+ also supports a one-step `xcodebuild -exportArchive -destination upload`,
which is Apple's preferred CI form. Either is fine; validate first regardless.

**Authentication.** `--apiKey`/`--apiIssuer` use the App Store Connect API key
from `06` §6. The `.p8` must live in one of `~/.appstoreconnect/private_keys/`,
`./private_keys/`, or `~/private_keys/` — `altool` finds it by Key ID. **Never in
this repository.**

### 3.5 Processing

The build enters **Processing** — Apple extracts metadata, generates thumbnails,
validates privacy manifests, and ingests dSYMs. **Typically 10–30 minutes**; a
few minutes to a few hours is normal; Apple publishes no SLA. Multi-hour stalls
happen during backend incidents.

---

## 4. `notarytool` is not the App Store upload tool

Stated explicitly because it is a common and expensive confusion:

- **`xcrun notarytool`** notarizes **Mac** software distributed **outside** the
  Mac App Store. It replaced `altool --notarize-app`, which Apple retired in
  November 2023.
- **`xcrun altool --upload-app`** (or `xcodebuild -exportArchive -destination
  upload`) uploads to App Store Connect.

Memento is an iOS app going to the App Store. **`notarytool` has no role here.**

**Transporter.app** (free, Mac App Store) is a GUI fallback if `altool`
misbehaves.

---

## 5. The ITMS playbook

| Code | Means | Fix |
|---|---|---|
| **ITMS-90683** | Missing purpose string. Your code **or a linked SDK** references an API gated by a usage description | Add the named `NS*UsageDescription` to `MeetMemento/Info.plist` with a **specific, user-facing** sentence. Required even if *your* code never calls the API — an SDK's reference is enough. Boilerplate strings also draw Guideline 5.1.1 rejections (`02` §4) |
| **ITMS-91053** | Missing API declaration — a required-reason API used without an approved reason | Add the category and a valid reason code to `NSPrivacyAccessedAPITypes`. See `03` §2 for the code table |
| **ITMS-91054** | Invalid API category | Typo in `NSPrivacyAccessedAPIType`. Use Xcode's plist editor autocomplete |
| **ITMS-91055** | Invalid API reason | The reason code is not valid for that category — **or is valid but unjustified**, which is our current `SystemBootTime`/`35F9.1` situation (`03`) |
| **ITMS-91056** | Invalid privacy manifest | Malformed `PrivacyInfo.xcprivacy`. `plutil -lint` it |
| **ITMS-91061** | Missing SDK privacy manifest | A third-party SDK on Apple's list lacks its manifest. Update to a version that ships one. Would only apply to us via RevenueCat |
| **ITMS-90078** | Missing Push Notification entitlement — the binary registers with APNs but the signature lacks `aps-environment` | Enable Push on the target **and on the App ID**, regenerate the profile, re-archive. Often triggered spuriously by an SDK or by an extension target that links the code without the entitlement |
| **ITMS-90062** | Invalid or non-increasing version string | See §2 |
| **ITMS-90809** | Deprecated API (e.g. UIWebView) | Remove it, including from vendored SDKs |
| **"Missing Compliance"** in App Store Connect | `ITSAppUsesNonExemptEncryption` absent from the **app target's** Info.plist | ✅ Already set to `false`. If it reappears, check for per-configuration Info.plists that lack the key |

**The pattern behind most of these:** the binary's entitlements, the App ID's
capabilities, and the provisioning profile must agree. When they diverge, the
error usually names the entitlement rather than the divergence.

---

## 6. Pre-upload hygiene

These are the things that have gone wrong on this project before, encoded as
checks rather than memory.

| Check | Why | Enforced by |
|---|---|---|
| No `Configuration.storekit`, xcconfig, or internal doc in the app bundle | The Release bundle once shipped SQL migrations, xcconfigs, and internal markdown (`specs/002` finding #7). Directory-level `membershipExceptions` **do not work** — files must be listed individually | `scripts/ci/check_archive_hygiene.sh` |
| No placeholder StoreKit product IDs | `Configuration.storekit` carries `12345678` / `123456789` | same |
| No `com.testing.*` bundle IDs | Sample targets were removed by `specs/002` R4; guard the regression | `scripts/ci/check_store_metadata.sh` |
| Usage strings defined exactly once | `GENERATE_INFOPLIST_FILE = YES` merges `Info.plist` with `INFOPLIST_KEY_*` build settings, and the winner is unpredictable | same |
| `ITSAppUsesNonExemptEncryption` present | Removes the export-compliance prompt from every upload | same |
| Privacy manifest matches the code, both directions | `03` §2 | `scripts/ci/check_privacy_manifest.sh` |
| Dead code and unused frameworks removed | `AuthenticationServices.framework` is still linked with no consumer; `SubscriptionPlan.swift` is dead; `memento://` is unhandled; `GoogleIcon.imageset` is orphaned | `00` C5 |

**Verify on the archive, not the source.** Run `plutil -p` on the archived app's
`Info.plist` and list the bundle contents — several of these only manifest in the
Release product.

---

## 7. Signing for CI

Current: `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = F3NM4HTMW8`, no
`PROVISIONING_PROFILE_SPECIFIER`. Fine for interactive Xcode Organizer uploads on
a machine already signed in; **insufficient for headless CI**, which has no
Apple Account session.

Two ways forward when the pipeline moves to CI:

1. **`xcodebuild -allowProvisioningUpdates`** with `-authenticationKeyPath`,
   `-authenticationKeyID`, and `-authenticationKeyIssuerID` — lets automatic
   signing work headlessly using the API key.
2. **Manual signing** with a checked-in profile and an imported `.p12`, or
   fastlane `match`. More reproducible, more moving parts.

Either way the distribution certificate's private key must be importable on the
runner. The self-hosted macOS runner already used by `ios-build-online.yml` is
the natural home.

---

## Verification

- [ ] `xcodebuild archive` succeeds with signing (requires `00` A1, the PLA).
- [ ] `xcodebuild -exportArchive` produces an `.ipa` using the committed
      `ExportOptions.plist`.
- [ ] `xcrun altool --validate-app` returns **zero ITMS errors**. This is the
      first real proof the binary is submittable, and it closes `specs/002`
      Task 8.
- [ ] `plutil -p` on the **archived** product shows
      `ITSAppUsesNonExemptEncryption => false` and all three usage strings.
- [ ] The archived bundle contains no `.storekit`, `.xcconfig`, `.md`, or
      internal resource.
- [ ] `CURRENT_PROJECT_VERSION` ≥ 3 with `MARKETING_VERSION = 1.0`.
- [ ] The build reaches **Processing** and then a usable state in App Store
      Connect within a few hours.
- [ ] `git ls-files | grep -cE "\.p8$|\.p12$|\.mobileprovision$"` → **0**.
