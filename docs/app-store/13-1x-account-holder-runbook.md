# 13 — 1.x Account Holder runbook (Gate S)

**Prepared 2026-08-17.** Agent-closable work (legal Pages, pending-sync
removal, in-app URLs, review-notes copy) is in the repo. Everything below
requires the **Account Holder** signed into developer.apple.com or App Store
Connect. Do these in order. Do not file Small Business Program or Private
Cloud Compute for this 1.x submit.

**Legal host (A6, done):** `https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/`

Confirm with:

```sh
for p in index.html privacy.html terms.html support.html; do
  printf '%s ' "$p"
  curl -sS -o /dev/null -w '%{http_code}\n' \
    "https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/$p"
done
curl -sS "https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/privacy.html" \
  | grep -ioE 'openai|supabase|gemini' || echo 'privacy: no third-party AI names'
```

All four must be **200**. Privacy must print the empty-grep line.

---

## A — Apple's clock

### A1 — Program License Agreement

1. Open [developer.apple.com/account](https://developer.apple.com/account).
2. Accept the current **Apple Developer Program License Agreement** if a banner
   is waiting. Archive signing has been blocked on this since 2026-07-13.

### A2 — Price path (pick one; 1.x has no IAP)

| Path | What to do | When you can go on sale |
|---|---|---|
| **Free, no IAP** (unblocks fastest) | Pricing and Availability → Price = Free. Skip Paid Apps Agreement. | After App Review + manual release |
| **Paid download, no IAP** | Business → Agreements → **Paid Apps Agreement**, then tax (W-9 or W-8BEN) and banking. Then set the price tier. | Not until tax + banking are Active |

Do **not** add a subscription or RevenueCat for 1.x.

### A3 / A4 — Skip for 1.x

Small Business Program and Private Cloud Compute filings are for Memento 2.0
(Z1). This binary is on-device Foundation Models only.

### A5 — EU DSA trader (1.x default: deselect EU)

Individual enrollment **publishes your address and phone** on EU product pages.

**1.x default:** App Store Connect → Pricing and Availability → App Availability
→ deselect all **27 EU territories**. Mainland China stays excluded (ICP).
This is reversible later without a resubmission.

If you instead want the EU live: Business → Agreements → Compliance → Digital
Services Act, complete trader verification, then include the 27.

You still must **answer** the trader question at account level even if the EU is
off the storefront.

### A6 — GitHub Pages

Enabled 2026-08-17 on `Meet-Memento-AI/Memento-Journal-iOS-AFM`, source `main`
→ `/docs`. No further Settings click unless the four URLs above are not 200.

### A7 — Age rating (expect 9+)

App Store Connect → App Information → Age Rating. Worked answers from `05`:

| Category | Answer |
|---|---|
| Parental controls / content filters | No |
| User-generated content (public) | No — private, on-device, single-user |
| Messaging / strangers | No |
| Web browsing / `WKWebView` | No |
| Advertising | No |
| Location sharing | No |
| Social media | **No** (this is also A8) |
| Mature themes / sexuality / violence / chance | None |
| Medical or Wellness | **Health and wellness topics** (9+). Not treatment information. |

### A8 — Social-media capability

**No.** Required to submit from September 2026.

---

## D — App Store Connect record (paste)

Bundle ID `com.sebastianmendo.MeetMemento`. App Apple ID `6754416850`.
Display name **Memento**. Version **1.0**, build must be **≥ 3**.

| Field | Value |
|---|---|
| D1 Privacy Policy URL | `https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/privacy.html` |
| D2 Support URL | `https://meet-memento-ai.github.io/Memento-Journal-iOS-AFM/support.html` |
| D3 Support email | `contact@sebastianmendo.design` |
| D4 Primary category | **Lifestyle**. Secondary: Productivity. Never Health & Fitness or Medical |
| D5 Copyright | `2026 Sebastian Mendoza` (no ©). Content Rights: No third-party content. License: Apple's standard EULA |
| D6 App Privacy | **Data Not Collected**. Tracking = No. Match `PrivacyInfo.xcprivacy` |
| D7 Review contact | Name + phone (you). Email: `contact@sebastianmendo.design`. Sign-in fields **blank**. Notes: paste `metadata/en-US/review_notes.txt`. Optional: 60–90s video (onboarding → Load Sample Entries → Chat → export) |
| D8 Metadata | Paste `metadata/en-US/{name,subtitle,keywords,promotional_text,description,release_notes}.txt` |
| D9 Screenshots | **iPhone 6.9″ 1320×2868** and **iPad 13″ 2064×2752** (iPad is mandatory; `TARGETED_DEVICE_FAMILY = 1,2`) |
| D10 Price | From A2. Tax category required if paid |
| D11 Territories | All except mainland China and (unless A5 trader is done) the 27 EU |
| D12 Release | **Manually release this version** |

### C8 App Icon

**Skip dark/tinted variants for 1.x.** Light 1024 PNG is valid.

### Screenshot set (minimum)

On an Apple Intelligence iPhone, Appearance Light, then repeat iPad 13″:

1. Journal with sample entries
2. New entry (text or voice)
3. Chat reply with a citation
4. Profile / Settings (Load Sample Entries visible is fine)
5. Optional lock screen

Export PNG at the exact pixel sizes above. No device chrome required if using
Xcode's screenshot sizes; do not put price or competitor names on the shots.

### D6 privacy label clicks

App Privacy → **Data Not Collected** (no linked, tracking, or purchased data).
Do not declare Email, Name, User ID, or User Content — the manifest's
`NSPrivacyCollectedDataTypes` is empty.

---

## Archive (after A1)

Xcode **26 GA** (not 27 beta). Scheme MeetMemento, Release, generic iOS.

```sh
xcodebuild -version   # expect 26.x
xcodebuild \
  -project MeetMemento.xcodeproj \
  -scheme MeetMemento \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/MeetMemento.xcarchive \
  archive
```

Then Organizer → Distribute App → App Store Connect → Upload, or
`xcodebuild -exportArchive` + `xcrun altool --validate-app` per `07`.

Internal TestFlight on a physical Apple Intelligence iPhone: Welcome →
onboarding (skip lock) → Load Sample Entries → write one entry → Chat one
question → airplane-mode journal still saves → Delete Everything returns to
Welcome.

---

## Submit

Press **Submit for Review** only when `00` "Do not press Submit until" is all
evidenced. Do not auto-release.
