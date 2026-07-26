# Data Layer — SwiftData, CloudKit, Protection

**Imports:** `import SwiftData`, `import CloudKit`, `import LocalAuthentication`
**Role in Memento:** the device is the system of record. There is no server-side representation of any journal entry, anywhere, ever.

---

## 1. Principle before API

**P2 — the device is the system of record.** SwiftData on-device is authoritative. CloudKit is a replication and durability mechanism, not a backend. An agent that starts designing "sync conflict resolution with the server" has misunderstood the architecture: there is no server.

---

## 2. Store configuration

✅ **VERIFIED** — API surface confirmed against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25. From `SwiftData.swiftmodule` interface:

```swift
// ModelConfiguration (@available macOS 14, iOS 17, …)
public init(_ name: String? = nil, schema: Schema? = nil,
    isStoredInMemoryOnly: Bool = false, allowsSave: Bool = true,
    groupContainer: ModelConfiguration.GroupContainer = .automatic,
    cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .automatic)

// ModelConfiguration.CloudKitDatabase — exactly three forms:
public static var automatic: ModelConfiguration.CloudKitDatabase { get }
public static var none: ModelConfiguration.CloudKitDatabase { get }
public static func `private`(_ privateDBName: String) -> ModelConfiguration.CloudKitDatabase
```

So the planned call stands:

```swift
let configuration = ModelConfiguration(
    schema: schema,
    cloudKitDatabase: .private("iCloud.com.yourorg.memento")
)

let container = try ModelContainer(for: schema, configurations: configuration)
```

**Private database only.** No public database. No shared database. No custom `CKRecord` schema outside SwiftData's mirroring. (Confirmed at the API level too: `CloudKitDatabase` exposes only `.automatic` / `.none` / `.private(_:)` — there is no public/shared-database case in SwiftData's mirroring surface.)

### CloudKit mirroring constraints — these bite

When a SwiftData model mirrors to CloudKit, the schema requirements are stricter than plain SwiftData:

- **All properties must be optional or have a default value.** CloudKit has no concept of a required field on an existing record. (Runtime constraint — not expressed in the interface; unchanged.)
- **`@Attribute(.unique)` is not supported** on mirrored entities. Enforce uniqueness in application logic instead. ✅ API note (iOS 27.0 SDK): `Schema.Attribute.Option.unique` still exists and compiles — the *rejection is at mirroring runtime*, not the type checker, so this failure mode remains silent-at-compile-time.
- **All relationships must have inverses.** A one-directional relationship will fail to mirror. ✅ API note (iOS 27.0 SDK): the macro is `@attached(peer) public macro Relationship(_ options: Schema.Relationship.Option..., deleteRule: Schema.Relationship.DeleteRule = .nullify, minimumModelCount: Int? = 0, maximumModelCount: Int? = 0, originalName: String? = nil, inverse: AnyKeyPath? = nil, hashModifier: String? = nil)` — `inverse:` is *optional at the API level* (`DeleteRule`: `.noAction`/`.nullify`/`.cascade`/`.deny`), so again the compiler will not save you; the mirror will.
- **`@Attribute(.allowsCloudEncryption)`** — ✅ the option EXISTS, verified against iOS 27.0 SDK (build 24A5390e), 2026-07-25: `public static var allowsCloudEncryption: Schema.Attribute.Option { get }` (`@available(macOS 14, iOS 17, …)`), and the `@Attribute` macro accepts it: `@attached(peer) public macro Attribute(_ options: Schema.Attribute.Option..., originalName: String? = nil, hashModifier: String? = nil)`. There is **no container- or configuration-level encryption knob** — `ModelConfiguration`/`ModelContainer` expose nothing encryption-related; the attribute option is the entire surface. The CloudKit backing (`CKRecord.encryptedValues`, iOS 15+) documents hard limits that apply to a mirrored transcript field: encryption **cannot be added to a field that already exists in the schema** (new fields only), and **encrypted fields cannot be indexed, queried, or sorted on**. 🔴 Still open (behavioral, V25): confirm on-device that the option actually round-trips through SwiftData's mirror for the transcript field — the interface proves the spelling, not the mirroring behavior.

New in the iOS 27 interface, for awareness when modeling: `Schema.Attribute.Option.codable` (`@available(iOS 27, …)`) and `Schema.Attribute.isCodable`.

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

✅ **Constants verified at header level** against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25 — `Foundation/NSFileManager.h` ships exactly five protection classes, unchanged:

```objc
NSFileProtectionNone                                    // ios(4.0)
NSFileProtectionComplete                                // ios(4.0)
NSFileProtectionCompleteUnlessOpen                      // ios(5.0)
NSFileProtectionCompleteUntilFirstUserAuthentication    // ios(5.0)
NSFileProtectionCompleteWhenUserInactive                // ios(17.0), unavailable on macOS
```

```swift
// Minimum
NSFileProtectionCompleteUntilFirstUserAuthentication

// Preferred if background tasks allow
NSFileProtectionComplete
```

The header's own doc comment on `.complete` confirms the risk this section flags: *"The file is stored in an encrypted format on disk and cannot be read from or written to while the device is locked or booting."* Neither the SwiftData nor the CloudKit module interface says anything about protection classes (searched both, zero hits), so there is no framework-level carve-out to rely on.

🔴 **Still open — behavioral, header reading cannot close it (V5):** whether `BGProcessingTask` execution overlaps locked periods in practice, and therefore whether `.complete` starves weekly generation, is an on-device test. If `.complete` blocks background generation, either:

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
