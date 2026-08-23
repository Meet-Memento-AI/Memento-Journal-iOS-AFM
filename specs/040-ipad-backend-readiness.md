---
id: 040
title: iPad Backend Readiness
tier: P1
status: in-progress (2026-08-23)
effort: 2 sessions
depends_on: [015, 023, 027, 038, 039]
findings:
  - live-writes-never-hit-swiftdata
  - this-device-only-dek-blocks-mirror
  - no-selection-ids-for-split-view
  - experience-profile-no-sync-conflict
source_refs: [REQ-DATA-001, REQ-DATA-002, REQ-DATA-003, REQ-DATA-011, REQ-DATA-013, REQ-PRIV-001, REQ-POS-001, REQ-INT-017]
tech_refs: [technology/05-data-swiftdata-cloudkit.md]
---

# 040 — iPad Backend Readiness

**Traceability:** finishes the live write path spec [015](015-data-layer-swiftdata-cloudkit.md)
scaffolded (schema + `JournalContainer` + entitlements) so journals, chats,
reflections, and the experience profile replicate through the user's CloudKit
**private** database. No Memento account. Compact chrome remains
[027](027-navigation-redesign.md) + `ChatHeaderActionCluster`. Ask **channels**
remain [039](039-reply-channels-and-phatic-generation.md). This spec owns
multi-device persistence, the sync allow/deny table, encryption posture for
mirrored rows, legacy import, selection contracts, and device-neutral copy.

**Does not implement:** iPad `NavigationSplitView`, 13″ layout, or hardware
keyboard chrome (follow-on UI spec). WatchOS. Audio CloudKit sync (stays
`REQ-DATA-011` default-off). Any rewrite of `ReplyChannel` / `chat-light@4`.

## Why

CONSTITUTION already says universal iPhone+iPad. Live writes still go to
per-device encrypted files and `LocalChatStore` JSON. The CloudKit container
at launch is empty. A ThisDeviceOnly DEK would make a replica unreadable on
the other device. No published `selectedEntryId` exists for a later split view.

## Requirements

### R1. Live writes through SwiftData + CloudKit private DB
Create, edit, delete, and load for journal entries, chat sessions/turns, and
reflections go through `ModelContext` → `StoredEntry` / `StoredConversation` /
`StoredTurn` / `StoredReflection`. No Memento account. iCloud signed out
degrades to local-only (`JournalContainer` fallback).

**Acceptance:** after a save, a new `ModelContext` on the same container
returns the row. `LocalJournalStorage` is not written for new entries once
legacy import has completed.

### R2. Sync allow / deny
| Replicates (Z1, user's private DB) | Stays on-device (Z0) |
|---|---|
| Entry text, chats, reflections, citations | PIN, biometrics, inactivity timestamp |
| `StoredProfile` (name, about, goals, experience profile, `aiEnabled`, `processOnDeviceOnly`) | Audio files (default), embeddings, TTS, Spotlight |
| | Voice identifier, speech rate, appearance theme |

Conflict policy: CloudKit native last-writer-wins (discharges spec 012 item 10).

### R3. Encryption posture
Mirrored rows MUST NOT be wrapped in the `ThisDeviceOnly` DEK. At rest:
`NSFileProtection` (015 R3) and `@Attribute(.allowsCloudEncryption)` on
`StoredEntry.transcript` when the mirror accepts it. App lock remains a
local gate.

### R4. One-time legacy import
On first launch after this ships: decrypt `EncryptedJournals`, import
`LocalChatStore` and `LocalProfileStore` / experience profile into SwiftData,
set `memento_imported_to_swiftdata`, then delete legacy files. Second launch
is a no-op. The other device only sees mirrored rows.

### R5. Selection contracts
`EntryViewModel.selectedEntryId`, `EntryRoute.edit(UUID)`, `AppNavigationState`
(`primarySection`, settings path). `ChatViewModel.currentSessionId` is the
chat-sidebar selection. `fetchSessions()` can run without the thread view
appearing. `cancelActiveTasks()` on disappear is compact-width only.
`RootPager` and `ChatHeaderActionCluster` stay the compact shell.

### R6. Device-neutral copy
User-facing strings use `DeviceCopy.thisDevice` (idiom-aware) or “this
device.” Forbidden: “nothing leaves your phone” (014 R3).

### R7. Spec 039 compatibility
A synced `ExperienceProfile` is still omitted from `chat-light@4` L1 (038 R6).
Channel is not a TrustZone. No new `ModelRouter` row.

## Out of Scope

- iPad split-view chrome (follow-on spec)
- Audio sync toggle beyond REQ-DATA-011 default-off
- Rewriting 039 / neural TTS / monetization

## Tasks

- [x] 1. Author this spec and amend owning documents (R1–R7).
- [x] 2. `StoredProfile` + live journal/chat/reflection writes (R1–R3).
- [x] 3. Legacy import (R4).
- [x] 4. Sync-status copy + CloudKit five-store deletion (R2, 015 R6).
- [x] 5. Selection contracts (R5).
- [x] 6. Tests listed in Verification.

## Verification

- [ ] `SchemaMirroringComplianceTests` include `StoredProfile` (optional-or-defaulted, no `.unique`, inverses, raw-value enums).
- [ ] Import fixtures: encrypted entries + chat JSON → SwiftData; second run no-op; UUIDs preserved.
- [ ] Create/edit/delete entry and conversation persist across a new `ModelContext` (CloudKit-off / in-memory).
- [ ] Five-store deletion: SwiftData counts zero; CloudKit wipe issued or queued.
- [ ] `EntryRoute.edit(UUID)` resolves from `EntryViewModel`; `selectedEntryId` / `currentSessionId` update without a split-view shell.

**User action:** confirm iCloud container `iCloud.com.sebastianmendo.MeetMemento`
exists for team `F3NM4HTMW8`.

## Regression Guards

CONSTITUTION §1 universal app; §4 rules 2, 7, 8. PRES compact shell including
`ChatHeaderActionCluster`. REQ-PRIV-001, REQ-POS-001, REQ-INT-017. 038 R6
untouched except R5.
