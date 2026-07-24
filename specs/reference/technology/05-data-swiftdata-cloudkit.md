# Data Layer — SwiftData, CloudKit, Protection

**Imports:** `import SwiftData`, `import CloudKit`, `import LocalAuthentication`
**Role in Memento:** the device is the system of record. There is no server-side representation of any journal entry, anywhere, ever.

---

## 1. Principle before API

**P2 — the device is the system of record.** SwiftData on-device is authoritative. CloudKit is a replication and durability mechanism, not a backend. An agent that starts designing "sync conflict resolution with the server" has misunderstood the architecture: there is no server.

---

## 2. Store configuration

🟡 **LIKELY** (stable API since iOS 17)

```swift
let configuration = ModelConfiguration(
    schema: schema,
    cloudKitDatabase: .private("iCloud.com.yourorg.memento")
)

let container = try ModelContainer(for: schema, configurations: configuration)
```

**Private database only.** No public database. No shared database. No custom `CKRecord` schema outside SwiftData's mirroring.

### CloudKit mirroring constraints — these bite

When a SwiftData model mirrors to CloudKit, the schema requirements are stricter than plain SwiftData:

- **All properties must be optional or have a default value.** CloudKit has no concept of a required field on an existing record.
- **`@Attribute(.unique)` is not supported** on mirrored entities. Enforce uniqueness in application logic instead.
- **All relationships must have inverses.** A one-directional relationship will fail to mirror.
- **No `@Attribute(.allowsCloudEncryption)` assumptions** — 🔴 verify current support for field-level encryption attributes and whether they apply to Memento's transcript field.

An agent adding a new model property must check all four. The failure mode is silent: the container fails to initialize, or mirroring stops, and it is not obvious why.

---

## 3. Entity overview

Full definitions live in the architecture spec §5.2. Summary for orientation:

| Entity | Role | Notes |
|---|---|---|
| `Entry` | A journal entry | Canonical `transcript` regardless of voice or text source |
| `Reflection` | Generated artifact | Carries `zone`, `modelIdentifier`, `promptVersion`, `citations`, `audioAssetID` |
| `Citation` | Grounding link | `entryID` + optional `quotedSpan` — mandatory, not decorative |
| `Conversation` / `Turn` | Ask surface history | `Turn.wasDegraded` records Z1→Z0 fallback |

**Key fields an agent will be tempted to skip and must not:**

- `Reflection.zone` — persisted trust zone. The UI renders it. Not optional.
- `Reflection.promptVersion` + `modelIdentifier` — without these, evaluation cannot attribute regressions.
- `Entry.excludedFromIndex` — per-entry opt-out from Spotlight donation.
- `Entry.salience` — drives which entries make it into a context-limited weekly reflection.
- `Turn.wasDegraded` — degradation must be disclosed, and disclosure must survive app restart.

---

## 4. Data protection

🟡 **LIKELY**

```swift
// Minimum
NSFileProtectionCompleteUntilFirstUserAuthentication

// Preferred if background tasks allow
NSFileProtectionComplete
```

🔴 **UNVERIFIED and worth resolving:** `NSFileProtectionComplete` makes the store unreadable while the device is locked. Memento schedules weekly reflection generation via `BGProcessingTask`, which may run while locked. If `.complete` blocks background generation, either:

- accept `.completeUntilFirstUserAuthentication`, or
- schedule generation to require unlock and generate on next foreground launch instead.

Test this explicitly. Do not assume.

Audio files in the app container need the same protection class applied at the file level.

---

## 5. App lock

🟡 **LIKELY**

```swift
import LocalAuthentication

let context = LAContext()
try await context.evaluatePolicy(
    .deviceOwnerAuthentication,   // biometrics with passcode fallback
    localizedReason: "Unlock your journal"
)
```

Use `.deviceOwnerAuthentication`, not `.deviceOwnerAuthenticationWithBiometrics` — the former falls back to passcode, which is what a journal wants. A user who fails Face ID three times should not be locked out of their own diary.

**Default: on.** For a private journal this is the correct default, unlike most apps.

Lock state must gate Spotlight result visibility if journal content is donated to a system-visible index — see `03-spotlight-retrieval.md` §8.

---

## 6. Audio store

Original audio lives as **files in the app container**, not as SwiftData blobs. Large binary data in a mirrored store is a sync performance disaster.

- Format: compressed AAC or Opus, quality sufficient for re-transcription. 🔴 Confirm codec availability and target file sizes.
- `Entry.audioAssetID` references the file; the file system holds the bytes.
- **Retention setting, three values:** discard after transcription (**default**), keep 30 days, keep forever.
- **Audio does not sync to CloudKit by default.** Separate, disclosed toggle.

Rationale for the default: audio is the highest-sensitivity artifact Memento holds and the largest storage consumer. Most users want the words, not the recording. Making "keep forever" the default would be a defensible product choice for a different product; for this one it is not.

---

## 7. Export

Full export to **Markdown and JSON**, including reflections and citations, generated entirely on-device, delivered via share sheet or Files.

This is not a nice-to-have. It is the structural guarantee behind "your words are yours" and it belongs in the **free tier** (REQ-MON-003 — never hold a user's own words hostage).

---

## 8. Deletion — P0 correctness

"Delete everything" MUST remove, and MUST report completion for:

1. SwiftData store
2. Audio files in the container
3. **Core Spotlight index entries**
4. Cached TTS audio renders
5. CloudKit records

Partial deletion that leaves Spotlight entries behind is a **P0 privacy defect** — the user believes their journal is gone while their words remain in a system index.

Write a test that asserts all five are empty afterward.

---

## 9. Migration from v1.3

🔴 If any TestFlight users exist on the Supabase-backed build, they need a one-time on-device export/import path before the server is decommissioned. If the user count is zero, document that and skip. Do not build migration infrastructure for zero users.
