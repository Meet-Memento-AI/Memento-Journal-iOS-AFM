---
id: 015
title: Data Layer — SwiftData and CloudKit
tier: P0
status: not-started
effort: 3 sessions
depends_on: [013, 014, 023]
findings: []
source_refs: [REQ-DATA-001, REQ-DATA-002, REQ-DATA-003, REQ-DATA-004, REQ-DATA-005, REQ-DATA-006, REQ-DATA-007, REQ-DATA-008, REQ-DATA-009, REQ-DATA-010, REQ-DATA-011, REQ-DATA-012, REQ-DATA-013, REQ-PLAT-001, REQ-PLAT-002, REQ-PLAT-003, REQ-PLAT-004, DEC-006, DEC-007]
tech_refs: [technology/05-data-swiftdata-cloudkit.md, technology/08-context-frameworks.md]
---

# 015 — Data Layer: SwiftData and CloudKit

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§4 "Platform baseline" and §5 "Data layer" in full. Supersedes spec
[003](003-database-baseline-and-account-deletion.md) (Supabase database baseline —
obsolete).

## Why

This is the foundational subtraction-and-rebuild: delete `supabase/` (Postgres,
pgvector, 6 edge functions, auth) and replace the system of record with SwiftData
(authoritative) + CloudKit private-DB mirroring (replication only, per P2). Every
other 2.0 spec's entities — `Entry`, `Reflection`, `Citation`, `Conversation`,
`Turn` — are defined here. Nothing downstream (indexing, intelligence, capture,
surfaces) can be built until this schema exists.

## Technology References

- `specs/reference/technology/05-data-swiftdata-cloudkit.md` — primary:
  SwiftData `ModelConfiguration`/`ModelContainer` CloudKit-mirroring
  constraints, `NSFileProtection` levels, audio-as-files retention options,
  and the 5-part deletion requirement.
- `specs/reference/technology/08-context-frameworks.md` — `HKStateOfMind`
  read/write API shape for `DEC-007`'s HealthKit write-back decision.

## Current State (evidence)

No `@Model` classes or `import SwiftData` anywhere in `MeetMemento/` (confirmed
2026-07-23). Current persistence is Supabase Postgres via `supabase-swift`, with
plain `Codable` structs in `MeetMemento/Models/` (`Entry.swift`, `JournalEntry.swift`,
`ChatSession.swift`, `Insight.swift`/`UserInsight.swift`, etc.) — see this spec's
Tasks for the mapping from each old model to its new `@Model` equivalent.
`IPHONEOS_DEPLOYMENT_TARGET = 17.0` in `MeetMemento.xcodeproj/project.pbxproj`
(needs raising to 27.0 per `REQ-PLAT-001`).

## Requirements

- [ ] TODO (derive from source doc §5, per its §17 checklist): Swift interface
  contracts for `Entry`/`Reflection`/`Citation`/`Conversation`/`Turn` and their
  supporting enums (`CaptureSource`, `IndexState`, `TrustZone`, `ReflectionKind`,
  `TurnRole`, `ReflectionRating`, `HealthSnapshot`); state machine for
  `indexState` (`.pending` → `.indexed` / `.excluded`); error taxonomy for
  CloudKit mirroring failures with user-facing copy; Given/When/Then acceptance
  criteria for export (`REQ-DATA-012`) and full deletion (`REQ-DATA-013`,
  explicitly: "MUST NOT leave Spotlight entries behind" — a P0 privacy defect if
  violated; write the test asserting all five stores — SwiftData, audio files,
  Spotlight index, cached TTS renders, CloudKit — are empty afterward, per
  `technology/05` §8); resolve `DEC-006` (does HealthKit context enter Z1 prompts
  — default to excluded per the source doc's conservative recommendation unless
  verified otherwise) and `DEC-007` (is "discard after transcription" the right
  audio retention default). App-lock policy detail (`REQ-DATA-004`): use
  `.deviceOwnerAuthentication` (biometrics **with passcode fallback**), not
  `.deviceOwnerAuthenticationWithBiometrics` — a user who fails Face ID three
  times must not be locked out of their own diary (`technology/05` §5). Swift 6
  boundary rule for the whole schema: `@Model` classes are **not `Sendable`** —
  pass `PersistentIdentifier`/`UUID` across actor boundaries and re-fetch, never
  the model object (`technology/09` §1); this constrains every
  `IntelligenceService` and background-task signature downstream. Also check
  `@Attribute(.allowsCloudEncryption)` support for the `transcript` field under
  CloudKit mirroring (V25) — field-level encryption on the most sensitive column
  is worth having if the mirror supports it.

## Out of Scope

- Core Spotlight donation itself — spec 016 (this spec only defines `indexState`
  as a field on `Entry`; the donation pipeline is 016's).
- The `IntelligenceService` that populates `title`/`summary`/`moodLabels`/etc. at
  save time — spec 017 (this spec defines the fields; 017 fills them).
- Actual Xcode project changes (deployment target, entitlements) — tracked as a
  task here but the mechanical pbxproj/xcconfig edits happen during this spec's
  execution, not during this specs-authoring pass.

## Tasks
- [ ] 1. Map each pre-2.0 model (`Entry.swift`, `JournalEntry.swift`,
      `ChatSession.swift`, `Insight.swift`/`UserInsight.swift`) to its 2.0
      `@Model` replacement; document what's dropped vs. carried forward. The
      `userId` fields on every pre-2.0 model are **dropped** — there are no
      accounts (spec 023); by the time this spec deletes `supabase/`, no UI
      code calls auth, so the deletion surface here is services and data only.
      The "Delete everything" Settings entry point is owned by spec 023 R4
      (PRES-085); this spec extends its mechanics to the full five-store
      deletion per `REQ-DATA-013`.
- [ ] 2. Define full `@Model` schema per source doc §5.2.
- [ ] 3. Configure `ModelConfiguration` + CloudKit private-DB mirroring
      (`REQ-DATA-001`, `REQ-DATA-002`).
- [ ] 4. Set Data Protection class on the store file (`REQ-DATA-003`) —
      ⚠️ VERIFY item 10 (interaction with `BGProcessingTask` while locked).
- [ ] 5. Implement HealthKit read-only integration + optional write-back
      (`REQ-DATA-006`, `REQ-DATA-007`) — resolve `DEC-006` first;
      ⚠️ VERIFY item 11 (App Review guidance on HealthKit data in prompts).
- [ ] 6. Implement audio store (`REQ-DATA-009`–`011`) — resolve `DEC-007`;
      ⚠️ VERIFY item 15 (codec availability/file sizes).
- [ ] 7. Implement export (`REQ-DATA-012`) and full deletion (`REQ-DATA-013`).
- [ ] 8. Raise `IPHONEOS_DEPLOYMENT_TARGET` to 27.0, enable Swift 6 strict
      concurrency = complete (`REQ-PLAT-001`, `REQ-PLAT-002`).
- [ ] 9. Verify offline operation end-to-end per `REQ-PLAT-003`.
- [ ] 10. Delete `supabase/` per the source doc's §14.1 deletion manifest, as
      cross-checked in spec 013's R7.

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include the source doc's §16 verification-queue items 10, 11, 15
      each marked confirmed or outstanding.

## Regression Guards
`CONSTITUTION.md` §2 *Security*: PIN/Keychain/encryption/biometrics are unaffected
by this rewrite and MUST still hold after this spec lands. The retired RLS
guarantee's replacement (`REQ-DATA-003`, Data Protection class) must be verified
before this spec can close. `CONSTITUTION.md` §4 rule 2 (SwiftData schema
versioning) and rule 7 (Data Protection / CloudKit re-verify) apply to every task
in this spec. Preservation contract: PRES-020…026 (journal list/editor/local-first
behavior) and PRES-085 ("Your Data" section incl. Delete Everything and the new
Export row, ATTACH-06) must survive the storage swap — the user-visible journal
experience is identical before and after this spec, only the store changes.
