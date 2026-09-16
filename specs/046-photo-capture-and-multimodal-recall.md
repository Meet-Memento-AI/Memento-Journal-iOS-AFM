---
id: 046
title: Photo Capture and Multimodal Recall
tier: P1
status: draft (2026-09-16) — documents shipped behaviour; `REQ-IMG-005` (multi-photo) and `REQ-IMG-007` (entry photos in retrieval) are the only not-started requirements
effort: 1 session (documentation) + 2 sessions if `REQ-IMG-007` is picked up
depends_on: [015, 017, 018]
findings:
  - photo-subsystem-unspecified
  - entry-photos-invisible-to-retrieval
  - single-photo-cardinality-by-fiat
  - chat-attachment-cap-underived
  - vision-stopgap-until-fm-attachments
mints: [REQ-IMG-001, REQ-IMG-002, REQ-IMG-003, REQ-IMG-004, REQ-IMG-005, REQ-IMG-006, REQ-IMG-007, REQ-IMG-008, REQ-IMG-009]
source_refs: [REQ-CAP-008, REQ-CAP-010, REQ-DATA-003, REQ-POS-001, REQ-PRIV-001, DEC-013, PRES-021, PRES-041]
tech_refs: [technology/01-foundation-models.md, technology/08-context-frameworks.md]
---

# 046 — Photo Capture and Multimodal Recall

**Traceability:** closes the `Attachment` gap left open by
`specs/reference/memento-2.0-architecture-spec.md` §5.2 and partially filled by
spec [015](015-data-layer-swiftdata-cloudkit.md) R1. Takes ownership of photo
capture and storage from spec [018](018-capture-and-voice-output.md) R5, which
specified a different feature that was never built (see that spec's 2026-09-16
amendment). Cited by §1.1's rewritten product definition and §1.3's competitive
table.

**Does not implement:** anything. This spec is written after the fact to
document a subsystem that shipped without one. Every requirement except
`REQ-IMG-005` and `REQ-IMG-007` describes code that already exists; those two
are marked not-started and are the only forward-looking work here.

## Why

The photo subsystem is the second-largest body of un-specified code in the app
and, by the owner's account, the capability users respond to most. It has no
`REQ-` identifier anywhere in the corpus, no owning spec, and no entry in §1.3's
competitive table — so the product's own documents make its competitive argument
about a journal with no photographs in it.

The one requirement that *does* mention entry photos — 018 R5 — specifies
on-device descriptions persisted as searchable metadata. That was never built.
What shipped instead is Vision-based understanding of **chat-turn** attachments,
session-scoped and persisted nowhere. The net effect is backwards: **entry
photos, which users actually accumulate, are invisible to retrieval; chat
photos, which are ephemeral, get all the intelligence.**

This spec records what exists, names the one real gap (`REQ-IMG-007`), and makes
the device-local photo guarantee citable, because §1.3's positioning claim now
rests on it.

## Technology References

- `specs/reference/technology/01-foundation-models.md` — primary: §6 "Vision —
  image input" (✅ VERIFIED that the on-device model accepts `UIImage`/`CGImage`),
  and the `OCRTool` 🔴 NOT FOUND entry that forced the hand-rolled Vision path.
- `specs/reference/technology/08-context-frameworks.md` — Journaling Suggestions,
  which is how `REQ-CAP-008`/`REQ-CAP-010` assumed photos would arrive.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot.

| # | Problem | Evidence | Severity |
|---|---|---|---|
| 1 | **Entry photos are invisible to retrieval.** `EntryRetriever`, `PassageChunker`, `EmbeddingService`, `SearchJournalPolicy`, `RetrievalPolicy` and `EntrySpotlightIndexer` contain zero image references. No entry photo is ever described, OCR'd, indexed or retrievable. | grep across `MeetMemento/Services/` | **P1 — the one real gap** |
| 2 | Vision runs **only** on chat-turn attachments, only for the current conversation, and nothing is persisted from it. | `ChatImageUnderstanding.swift`; `ChatService.swift:515-545` (`sessionUserImages`, `rememberUserImages`/`forgetSessionUserImages`); `IntelligenceService.swift:124-125` — *"the store itself stays text-only"* | P1 |
| 3 | **One photo per entry, enforced independently at three layers** — none of them documented. | `PhotoStorage.swift:60-61` (*"single photo per entry, so a save always replaces rather than appends"*); `MementoDataStore.swift:56-68`; `PhotoAction.swift` (`set(Data)`, singular) | P2 |
| 4 | The SwiftData schema models attachments as **to-many**, which no write path can populate. `fileAssetID` is the entry's UUID, not the attachment's, so a second attachment has nowhere to store bytes. | `JournalSchema.swift:78-79`, `:96-104` | P2 |
| 5 | Chat allows **3** photos per message. The number has no derivation in any document. | `ChatInputField.swift:108` (`maxAttachments = 3`) | P3 |
| 6 | `ChatImageUnderstanding` is an explicit stopgap for the iOS 26 SDK; the real path is compiled but unreachable. | `ChatImageUnderstanding.swift:7-13`; `FoundationModelsIntelligenceService.swift:1283-1297` (`canAttachImagesToModel`, `#if compiler(>=6.3)` + `@available(iOS 27.0, *)`), `:1300-1318` (`decodedAttachments`) | P2 |
| 7 | `PRES-041` freezes the chat composer as a three-state field **with no attachment affordance**, while the shipped composer has a 112pt photo row inside the same glass. | `reference/frontend-preservation-contract.md:76`; `ChatInputField.swift:106-107,250-265,331-345` | P2 |
| 8 | `docs/app-store/01-review-guidelines-digest.md:493-495` asserts the app requests "no location, photos" and treats photo permissions as hypothetical future work from 018 R5 — while `Info.plist:36` already ships `NSCameraUsageDescription`. | those two files | **P1 — review accuracy** |

## Requirements

**Traceability:** R1 → `REQ-CAP-008`/`REQ-CAP-010` (capture, extended beyond
Journaling Suggestions); R2 → `REQ-DATA-003` (file protection); R3 → new;
R4 → `REQ-PRIV-001`, `REQ-POS-001`; R5 → §5.2's `attachments` array;
R6 → `PRES-041`; R7 → 018 R5's original intent; R8 → `technology/01` §6.

### R1. Capture sources — camera and library, both first-class (`REQ-IMG-001`)
An entry accepts a photograph from the device camera or the photo library, and
**a photograph alone is a complete entry** — `hasContent` is satisfied by a photo
with no text (`AddEntryView.swift:875-880`, *"An attached photo is content in its
own right"*).

- Camera: `CameraCapturePicker` (a `UIViewControllerRepresentable` over
  `UIImagePickerController`, `sourceType = .camera`). Callers MUST check
  `isSourceTypeAvailable(.camera)` and `AVCaptureDevice` authorization and
  present the two distinct failure states — "Camera Unavailable" and "Camera
  Access Required" (`AddEntryView.swift:1076-1098`, `:352`, `:357`).
  `NSCameraUsageDescription` ships (`Info.plist:36`).
- Library: `PhotosPicker` with `matching: .images`. The picker MUST stay
  deferred (`DeferredLibraryPicker`, `AddEntryView.swift:1236-1246`) — attaching
  it at the editor root initialized PhotoKit on every editor open and cost the
  §9.1 400ms budget.
- **No `NSPhotoLibraryUsageDescription`.** `PhotosPicker` is an out-of-process
  picker and needs no library-read entitlement; adding one would widen the
  declared permission surface for nothing. Holds unless a future spec leaves
  `PhotosPicker` for a direct `PHAsset` read.

**Acceptance (Given/When/Then):**
- Given an entry with a photo and no text, when saved, then it persists as a
  normal entry and renders in the timeline with the photo as its backdrop.
- Given a device with no camera or with camera access denied, when the camera
  action is taken, then the matching alert is shown and the library path remains
  available.
- Given the entry editor opened cold, when it appears, then PhotoKit has not been
  initialized.

### R2. Storage — encrypted, device-local, thumbnail-split (`REQ-IMG-002`)
Photo bytes are stored as encrypted files, **never inlined into the entry
envelope and never in SwiftData**. Two sibling directories under `Documents/`:
`EncryptedPhotos` (the ≤1600px original) and `EncryptedPhotoThumbs` (a
downsampled thumb plus its precomputed average-colour sample).

- Filenames are fully derived from the entry UUID
  (`"\(entryId.uuidString).encrypted"`), so no path is ever persisted.
- Writes use `[.atomic, .completeFileProtection]` (`REQ-DATA-003`).
- Storage normalization is 1600px long edge at JPEG q0.7
  (`ImageProcessor.swift:17,19`); thumbs are ImageIO-downsampled to 400px
  (`PhotoThumbnailCache.swift:23`).
- The persisted thumb is a `PersistedThumbnailEnvelope` — JPEG **plus** the
  baked backdrop sample — JSON-encoded then encrypted, so a list paint never
  decrypts a full-size original (`PhotoThumbnailCache.swift:170-181,228-234`).
- The split exists for a measured reason and MUST NOT be collapsed: the entry
  envelope is decrypted for every entry on every list load *and* on the AI-chat
  context hot path (`PhotoStorage.swift:10-14`).

**Acceptance:** Given a list paint of N entries with photos, when thumbnails
render, then `fullFileDecodeCount` is 0 — the existing test-observable counter at
`PhotoThumbnailCache.swift:39`, exercised by `PhotoThumbnailCacheTests.swift`.

### R3. Cardinality — one photo per entry today (`REQ-IMG-003`)
Exactly one photo per entry. This is enforced independently at three layers and
any change must address all three: the UUID-derived filename with overwrite-on-save
(`PhotoStorage.swift:52-73`), the `if row.attachments?.isEmpty` insert guard
(`MementoDataStore.swift:56-68`), and `PhotoAction.set(Data)`'s single payload.

`PhotoAction` is deliberately a tri-state rather than `Data?`, so that "editing an
entry whose photo is untouched this session" and "explicitly cleared it" do not
collapse to the same value — the save path only touches `PhotoStorage` when
something actually changed.

**Acceptance:** Given an entry that already has a photo, when a new photo is set,
then the old file is replaced rather than orphaned, and no second attachment row
is created.

### R4. Photo bytes never leave the device (`REQ-IMG-004`; `REQ-PRIV-001`, `REQ-POS-001`)
**The strongest privacy fact in the app, and §1.3's positioning claim now depends
on it.** The CloudKit private mirror carries `StoredAttachment` metadata only —
`id`, `kind = "photo"`, `fileAssetID` — and never the JPEG. The bytes are
encrypted with the device DEK, which is `ThisDeviceOnly` and is never mirrored.

Photographs are also **Z0 permanently**. Image understanding has never had a Z1
path (source doc §7.2; spec 017 R2's row reads *"none — no Z1 path exists"*), and
`DEC-013`'s constraint on re-enabling PCC does **not** extend to images under any
future reversal.

**Acceptance (Given/When/Then):**
- Given an entry with a photo, when the CloudKit private DB is inspected, then no
  record contains image bytes.
- Given the image-understanding path, when routed under any configuration, then
  no code path yields a Z1 zone for it (asserted by spec 017 R2's router test —
  cited, not duplicated).
- Given a second device signed into the same iCloud account, when it syncs, then
  the entry arrives with `hasPhoto == true` and no image — a **known and accepted
  consequence**, disclosed rather than hidden.

### R5. Multi-photo entries (`REQ-IMG-005`) — **not started**
Entries SHOULD support multiple photographs. People experience a moment as
several frames, not one, and the single-photo cap is a storage-layer artifact
rather than a product decision.

Implementing this MUST break the UUID-derived filename convention in R2 — key
files by `attachment.id` rather than `entry.id` — and MUST populate the to-many
`attachments` relationship the schema already declares. It is therefore a
migration, not a feature toggle, and it touches the CloudKit mirror shape.

**Status: not-started.** Recorded so the constraint is visible before someone
attempts it casually.

**Acceptance:** deferred until scheduled.

### R6. Chat attachments — bounded, library-only, session-scoped (`REQ-IMG-006`)
The Ask composer accepts up to **3** photographs per message, library-sourced
only (no camera in chat), rendered as a 112pt thumb row inside the same glass as
the input, each with a remove affordance and VoiceOver labels ("Attach photo",
"N of 3 photos attached").

- Photos-only sends are allowed (`canSend` is `!isTextEmpty || !attachedPhotos.isEmpty`);
  when the user sends photos with no text, the pipeline substitutes prompt copy
  rather than sending an empty turn (`ChatViewModel.swift:362-367`).
- Bytes live in an in-memory `sessionUserImages` map keyed by conversation and
  are reattached to recent turns via `historyWithImages(for:)`, so follow-ups can
  still see earlier photos. **They are never persisted** — `StoredTurn` has no
  attachment relationship and the store stays text-only.
- Any turn carrying an image is bumped off the cheapest reply channels
  (`ReplyChannel.resolve(turn:hasImages:)`) — spec 039's photo rule, which this
  spec is the missing authorization for.
- **`PRES-041` is amended by this requirement**: the preservation contract
  describes a composer with no attachment affordance and must be updated to
  include the thumb row.

**Acceptance:** Given 3 attached photos, when a fourth is picked, then it is
rejected at both `remainingAttachmentSlots` and `appendPreparedPhoto`. Given a
conversation is left, then `forgetSessionUserImages` clears the bytes.

> The cap of 3 has no recorded derivation. It is plausible as a context-budget
> guard but is not traceable to one. Left as-is and flagged rather than
> rationalized after the fact.

### R7. Entry photos in retrieval (`REQ-IMG-007`) — **not started** (inherits 018 R5's intent)
An entry's photograph SHOULD contribute to what the journal can recall. This is
018 R5's original and correct intent — *a photo you took should be findable by
what is in it* — and it remains unbuilt.

The shape 018 R5 specified (generate a description at attachment time, persist
it, donate it to the Spotlight index) is **no longer the right shape**, for two
reasons recorded elsewhere in this pass: retrieval is `EntryRetriever` over
`NLEmbedding` passages, not the Spotlight index (`DEC-002` Plan B), and
`StoredAttachment` has no field to hold a description.

The tractable version under the current architecture: generate an on-device
description at save time, persist it as part of the entry's indexed text so it
chunks and embeds like any other passage, and let `EntryRetriever` rank it with
no special-casing. That requires a schema field and a migration, which is why it
is scoped here rather than asserted as done.

**Status: not-started.** It is the single highest-value gap this spec records.

**Acceptance:** deferred until scheduled. When taken up, the acceptance from 018
R5 still applies: description generation MUST degrade silently on devices without
Apple Intelligence — attachment capability never gates on the model.

### R8. Image understanding — the interim mechanism, and its exit (`REQ-IMG-008`)
On the iOS 26 SDK the on-device model cannot take image `Attachment`s, so
`ChatImageUnderstanding` produces a **text reading** of each attached photo for
the Ask prompt: `VNClassifyImageRequest` (confidence ≥ 0.2, top 8),
`VNRecognizeTextRequest` (accurate, language-corrected, top 12 snippets), and
`VNDetectFaceRectanglesRequest` (count only). Photos are labelled
`this-message-photo-N` / `earlier-turn-N-photo-M` so the model can address them.

This is the **only** `import Vision` in the app and it deliberately does not
import `FoundationModels` — it is prompt input, not a second intelligence
importer, and must not become one (**P3**, spec 017 R1).

**The exit is already built and gated.** `canAttachImagesToModel`
(`FoundationModelsIntelligenceService.swift:1283-1297`) switches to real
`UIImage` attachments under `#if compiler(>=6.3)` + `@available(iOS 27.0, *)`;
`:2022-2038` carries distinct instruction copy for all three states (real
attachments / Vision reading / no image understanding on this device).

**When the toolchain moves, this is the highest-leverage change in the app.**
The capability users respond to most is currently running on a caption
approximated from labels and OCR, not on multimodal reasoning.

**Acceptance:** Given a build on the iOS 27 SDK, when a photo is attached to a
chat turn, then `decodedAttachments` supplies the image to the model and
`ChatImageUnderstanding` is not invoked. Given a build on the iOS 26 SDK, then
the Vision reading is used and the instruction copy matches that state.

### R9. Presentation and accessibility (`REQ-IMG-009`)
A photo entry uses its photograph as a full-bleed card backdrop with tokenized
blur, brightness lift, saturation, and an optional scrim (`PRES-021`).

- The scrim is **solved, not chosen**: `JournalBackdropContrast.swift` samples the
  cover to 16×16, averages sRGB, and picks the lightest scrim putting white type
  at WCAG AA 4.5:1.
- Increase Contrast raises a floor; **Reduce Transparency zeroes blur entirely.**
- The editor backdrop is pre-baked to a ≤512px bitmap off the main thread
  (`JournalBackdropRenderer.swift:24,51-101`) because a live `.blur` on a
  screen-sized layer under four Liquid Glass surfaces stalls the editor on device.
- The backdrop is decorative: `.accessibilityHidden(true)`, with the excerpt
  VoiceOver-only.

**Acceptance:** Given any cover image, when a card renders, then measured contrast
for its title and excerpt is ≥ 4.5:1. Given Reduce Transparency, then blur radius
is 0.

## Out of Scope

- **Journaling Suggestions** as a capture route — spec 018 R4 owns it, and it
  remains unbuilt. R1 here documents the direct camera/library paths that shipped
  instead.
- **Audio attachments** — spec 015 R5 owns the asset-store pattern this reuses.
- **The chat composer's non-photo states** — `PRES-041` and spec 027.
- **Entry tagging and computed insights over photos** — spec 045.
- Changing `lint_forbidden_phrases.py` or any other CI script.

## Tasks

- [x] 1. Document capture sources, storage, cardinality (R1–R3).
- [x] 2. Make the device-local photo guarantee citable by §1.3 (R4).
- [x] 3. Document chat attachments and authorize spec 039's photo rule (R6).
- [x] 4. Document the Vision interim and its SDK-gated exit (R8).
- [x] 5. Document the contrast/accessibility solve (R9).
- [ ] 6. Amend `PRES-041` to include the attachment row (R6).
- [ ] 7. Correct `docs/app-store/01-review-guidelines-digest.md:493-495` (Current State row 8).
- [ ] 8. `REQ-IMG-005` multi-photo — not started, needs scheduling.
- [ ] 9. `REQ-IMG-007` entry photos in retrieval — not started, highest-value gap.

## Verification

- [ ] `grep -rn "PhotosPicker\|CameraCapturePicker" MeetMemento/Views MeetMemento/Components` — both capture routes present, library picker deferred.
- [ ] `PhotoThumbnailCacheTests.swift` passes; `fullFileDecodeCount == 0` on a list paint.
- [ ] `grep -rln "import Vision" MeetMemento/` returns exactly one file.
- [ ] `grep -rn "image\|photo" MeetMemento/Services/Intelligence/EntryRetriever.swift` returns nothing — R7 is honestly marked not-started.
- [ ] No `StoredAttachment` field carries image bytes; CloudKit records inspected on a second device show `hasPhoto` with no image (R4).
- [ ] `grep -rn "no location, photos" docs/` returns nothing (Task 7).
- [ ] Spec 018 R5's task checkbox is still unchecked and points here.

## Regression Guards

CONSTITUTION §2 *Security* — entry encryption and file protection extend to
photos and thumbs; `REQ-DATA-003`'s protection class must hold for both
directories. **P2** — photo bytes are device-local; do not add them to the
CloudKit mirror. **P3** — `ChatImageUnderstanding` must never import
`FoundationModels` (`check_single_intelligence_importer.sh`). **P4**/`REQ-POS-001`
— §1.3's claim that photographs never leave the device depends on R4 and must be
re-verified if the storage path changes. `PRES-021` (card backdrop), `PRES-041`
(composer, amended by R6). `DEC-013` — images are Z0 permanently and are not
covered by any future PCC opt-in.
