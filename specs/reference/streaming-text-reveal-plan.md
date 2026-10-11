# Streaming text reveal — implementation plan

Status: plan, not started · 2026-10-08

Replaces the snap-to-snapshot typewriter in `AIOutputComponent` with a
per-glyph reveal driven by a schedule stored on the message. Each glyph fades
up out of a soft blur and settles a few points, on a token-like rhythm that
stays smooth whether the model runs ahead of the animation or stalls.

Deployment target is iOS 26.0, so `TextRenderer` (iOS 18) is available.

## What the existing code means for the spec

The source spec assumes an `AsyncSequence` of string deltas and one `Text`
per message. Neither is true here, and the plan adapts to that rather than
building a parallel path:

| Spec assumption | This codebase | Adaptation |
|---|---|---|
| Deltas | `ChatStreamEvent.delta(body:…)` carries the **whole reply so far**, already cut to a stable prefix by `ReplyRenderer.stablePrefix` (whole sentences on journal channels, whole words elsewhere) and rendered. | Turn snapshots into deltas in the view model: append `new.dropFirst(old.count)` when `new.hasPrefix(old)`. Divergence handling below. |
| Text only grows | `strippingReferenceMarkers` can shrink the cleaned body, and `.final` re-renders with `isFinal: true`, so the final body can differ from the last delta. | `StreamSchedule.reconcile(to:)`: keep arrivals for the common prefix, truncate the rest, re-append the new suffix. Arrivals that are already scheduled are only changed when the characters themselves changed. |
| One `Text(AttributedString)` | `MarkdownBodyView` renders a `[MarkdownBlock]` as several `Text`s (headings, paragraphs, list rows with separate marker `Text`s). The parser strips syntax (`### `, `- `, `**`), so displayed characters are not source characters. Headings 1/2 are separate fields. | The schedule indexes **displayed** characters across the flattened reply. Each `Text` gets a `baseIndex` into it. See §3. |
| LLM client off-device | Generation is on-device (Foundation Models); deltas arrive per 33 ms through a coalescer. | Append to the schedule on **every** snapshot with its real receive time. Only publishing to `messages` stays coalesced. |
| Auto-follow bottom | `ChatMessagesView` pins the sent message to the top (beats 1–2, `PinIntent`) and does not follow the reply. | **Decided: pin, then follow.** Keep the pin. Once the revealed reply reaches the composer, follow the bottom gently until the user drags. |

## 1. `StreamSchedule` (new: `withMemento/Components/AIChat/Streaming/StreamSchedule.swift`)

A value type with the fields and constants from the spec: `arrivals: [Double]`,
`start: Date`, `rng: SplitMix64`, cursor `t`, `pendingToken: String`,
`isComplete`, `static let fade = 0.55`.

- `SplitMix64: RandomNumberGenerator` in the same file. Seed it with FNV-1a 64
  over `uuid.uuid`'s 16 bytes, never `hashValue`.
- `append(_ delta: String, receivedAt: Date = .now)` follows the spec exactly:
  - tokens of 2–5 characters that end after a space, with the remainder carried
    into `pendingToken`;
  - 12 ms between characters within a token;
  - 28–70 ms gaps between tokens, or a 6 ms burst with 14% probability;
  - +50 ms pause after `,` and +110 ms after `. : ; ? !`;
  - the network floor `t = max(t, received)`;
  - a backlog factor that ramps from 1 down to 0.25 once lag exceeds 1.5 s
    (linear over lag 1.5 → 4.5 s, then clamped).
- **Pending token flush.** A carried-over partial token is not scheduled until
  more text arrives. Snapshots here always end on a word or sentence boundary,
  so this rarely matters, but `finish()` must schedule any `pendingToken`
  before setting `isComplete`, or the last word never appears.
- `reconcile(to newText: String, receivedAt:)`: an addition the spec doesn't
  cover (see the table above). Common prefix → `arrivals.removeLast(n)` →
  rewind `t` to `max(lastKeptArrival, received)` → `append` the new suffix.
  Changed characters that were already visible re-reveal from the floor, a
  short 0.55 s fade on a few characters rather than a jump. The usual case,
  a pure append, takes the fast path.
- `arrival(at:)`, `duration`, `isSettled(at:)` as in the spec.
- `static func settled(text:)` gives every character an arrival of
  `-.infinity` and sets `isComplete = true`, so a history message never
  animates, whatever `start` is.
- `Equatable`/`Hashable` by `(arrivals.count, isComplete, start)` rather than
  the synthesized versions. `ChatMessage` is `Hashable`, and comparing arrays
  of a few thousand doubles on every diff is wasted work.

## 2. `StreamRenderer: TextRenderer` (new: `…/Streaming/StreamRenderer.swift`)

`elapsed: Double`, `schedule: StreamSchedule`, `baseIndex: Int`,
`reduceMotion: Bool`. Implements the spec's loop: lines → runs → glyphs with a
running index starting at `baseIndex`; a fast path that draws the whole run
when its last glyph has finished; ease `1 − (1 − p)³`; opacity, blur
`(1−e)·5` and `translateBy(y: (1−e)·4)` while `e < 1`.

- **Glyph ↔ character mapping.** Count glyphs, not characters. Clamp the index
  to `arrivals.count - 1`, so a ligature or emoji mismatch degrades to a
  slightly early or late fade and never crashes or hides text. Add a test
  string with emoji, ZWJ sequences and "fi" to confirm.
- **Reduce Motion:** no blur or offset. Opacity uses the arrival of the
  glyph's token start (store a parallel `tokenStarts: [Double]` on the
  schedule) with a 0.15 s linear fade, so whole tokens appear together.
- `animatableData` isn't needed. The `TimelineView` drives `elapsed`.

## 3. `StreamingText` and the Markdown path

New `…/Streaming/StreamingText.swift`:
`StreamingText(attributed: AttributedString, schedule:, baseIndex:)` wraps
`TimelineView(.animation(paused: settled))` around
`Text(attributed).textRenderer(StreamRenderer(...))`. Settle detection uses
`.task(id: SettleKey(count, isComplete))` that sleeps until
`start + duration` and then flips `@State settled`. It sets
`.accessibilityLabel` to the full current text.

**The index map** is the part that needs care.

- Add `RichTextParser.displayedCharacterCount(of block:)` (marker text +
  runs).
- `MarkdownBodyView` computes a running `baseIndex` per block. List markers
  (`•`, `1.`) take the index of their row's first character, so they fade in
  with the row.
- Heading 1 and heading 2 come first in the flattened order: `[h1 | h2 | body]`.
  This mirrors the existing `displayedCount` layout.
- The schedule therefore runs over the **displayed** text, not the raw body.
  The view model builds it from the same flattening, through a static
  `AIOutputContent.displayedText` that calls the parser. The parser is pure,
  and the cost per snapshot is one parse of the stable prefix, which the view
  already does.
- Streaming parse: keep the `ParseCache` and closed-prefix logic in
  `shownBodyBlocks`. It now parses the full `content.body`, not a typewriter
  prefix, because the renderer hides glyphs that haven't arrived yet.

`MarkdownBodyView` swaps `styledText`'s `Text(attr)` for `StreamingText`
whenever a schedule is supplied, and removes `dissolveCount`,
`dissolveMinOpacity`, `applyDissolve` and the caret. The fading leading edge
replaces the caret. Fact cards (`InsightFactSection`) and `CitationLink` stay
outside the schedule and keep their existing opacity transitions.

## 4. Integration

### `ChatMessage` / `AIOutputContent`
- Add `var schedule: StreamSchedule?` to `ChatMessage`. `nil` means settled
  and static. Add a `schedule` parameter to `aiMessage(...)`. History
  (`ChatViewModel.swift:850`), cache restores and the UI-test seed pass `nil`.
  That satisfies "history never animates" without allocating a settled
  schedule per row.
- `isNew` stays, because user bubbles and the send choreography use it. It no
  longer gates assistant text. Remove `markMessageSeen`, `markAllMessagesSeen`'s
  assistant role and `onAnimationComplete`. A recycled row now resumes from
  `start` instead of replaying.

### `ChatViewModel.performSend`
- Keep a local `var schedule: StreamSchedule?` in the task.
- On the first non-empty delta, set `schedule = StreamSchedule(messageID:
  assistantId, start: .now)`, per the spec.
- On **every** `.delta`: `schedule.reconcile(to: displayedText, receivedAt:
  .now)`. This happens before coalescing, so arrival floors are the real
  receive times. `applyPendingDelta` then publishes the body together with the
  current `schedule` value.
- `.final`: reconcile to the final rendered text, then `finish()`.
- `defer` (error or cancel): if a schedule exists, `finish()` it and publish
  it, alongside the existing `isStreaming = false` flip. First apply any
  `pendingDelta`, which also fixes the lost-tail bug from the review.
- Safety and refusal replies (`isDesignedEmptyState`) and crisis cards: no
  schedule, so they show instantly. Authored copy shouldn't drip in.
- Narration is unchanged. `NarrationCoordinator` keeps reading
  `body`/`isStreaming`, because TTS should follow the model and not the visual
  reveal.

### New `isSettled` gating
Add `ChatMessage.isRevealSettled(at:)` (`schedule == nil ||
schedule.isSettled(at:)`). The view model keeps
`@Published private(set) var revealingMessageID: UUID?`, set when the first
schedule is published and cleared by a `Task.sleep(until: start + duration)`
after `finish()`. The task is tracked and cancelled with `sendGeneration`,
like the other tracked tasks. These gate on it instead of `isStreaming` or
`isLoading`:
- `AIOutputComponent.showsActionBar` (copy, thumbs, redo, read aloud);
- `AIChatFooter isSending` (`AIChatView.swift:475`). The composer stays dimmed
  until the reveal settles, not only until the first token;
- starter and suggestion chips, if they show after a reply.

`AILoadingState` keeps its current trigger (`isLoading` until the first
token).

### `ChatMessagesView`
- Assistant rows: `.transition(.identity)` on insertion, and the existing
  removal stays.
- **Pin, then follow.** A new `PinIntent` stage after `.holding`. While
  `revealingMessageID != nil` and the user hasn't dragged (the existing
  `onScrollPhaseChange` already drops the pin on `.interacting`): when
  `transcriptEndY` passes the bottom of the viewport, `scrollTo(bottomAnchorID,
  anchor: .bottom)` with `.easeOut(0.25)`, at most every 150 ms. Content grows
  in token-sized steps, so this reads as a glide and not a judder. It reuses
  the correction-budget guard so a scroll can't feed back into layout. Reduce
  Motion uses a non-animated scroll. Narration's `followTail` clock is
  untouched.

### `AIOutputComponent` cleanup
Delete the drain loop, `displayedCount`, the `t*` mirrors, `revealStep`,
`shouldSleepAfterReveal`, `catchUpThreshold`, `baseTickNanos`, the dissolve
constants and `contentIdentity`'s streaming key. It becomes a mostly stateless
view that passes `schedule` through to `MarkdownBodyView` and the heading
`Text`s.

## 5. Verification

### Unit tests (replace `AIOutputTypewriterTests` with `StreamScheduleTests`)
- **Determinism:** same UUID and same deltas give identical arrivals.
- **Append-only:** after `append(b)`, `arrivals[0..<a.count]` is unchanged.
- **Tokens:** never cross a space, 12 ms spacing within a token, and
  punctuation pauses.
- **Floor:** no arrival is earlier than its `receivedAt`.
- **Backlog:** a 300-character burst at `t=0` settles within about 2 s, and no
  gap between consecutive arrivals is ever negative.
- **`finish()`:** flushes `pendingToken`.
- **`settled(text:)`:** `isSettled(at: .distantPast)`.
- **`reconcile`:** a shrink keeps prefix arrivals and re-schedules only the
  changed tail.
- **Index map:** for each block in a fixture reply, `baseIndex` plus its count
  equals the next block's `baseIndex`, and the total equals
  `displayedText.count`.
- **`ChatStreamingTests`:** a mocked stream ending in error leaves a finished,
  settled-in-time schedule, and the last pending snapshot is applied.

### Mock stream (DEBUG only, `AIChatView+Previews.swift` + `MockChatService`)
A `StreamRevealPreviewSource` emitting cumulative snapshots: random 1–8
character growth, 10–300 ms delays, one 2 s stall and one 300-character burst.
A preview row and a `-StreamRevealDemo` launch argument for the simulator.

### Manual checks (simulator; previews where they suffice)
1. Visible text never flickers or restarts, including when a snapshot
   shrinks.
2. The 2 s stall resumes smoothly, with the floor visible as no pop.
3. The burst catches up in about 2 s or less.
4. Scroll a streaming row off-screen and back: it resumes mid-stream.
5. Open a history session: everything shows instantly.
6. The action bar and composer enable only after the last glyph settles.
7. The pin holds, the follow starts when the reply reaches the composer, and
   a drag stops it.
8. Reduce Motion: token-wise opacity only.
9. VoiceOver reads the full current text.
10. Instruments: no `TimelineView` updates after the reply settles.

Build with the project's usual `xcodebuild` scheme and run the test target
before handing off.

## Order of work

1. `SplitMix64`, `StreamSchedule` and its tests. Pure, no UI.
2. `StreamRenderer`, `StreamingText` and a preview fed by the mock source,
   on a single paragraph.
3. Markdown index map and the `MarkdownBodyView` swap, plus headings.
4. `ChatMessage.schedule` and the `performSend` wiring (including the
   pending-delta fix).
5. `isSettled` gating for the action bar and composer.
6. Pin-then-follow scrolling.
7. Delete the old typewriter and dissolve, and update or remove the stale
   tests.
8. Full verification pass.

## Risks

- **Index drift between the schedule and `Text` glyphs** when the parser and
  the attributed flattening disagree on whitespace or markers. The index-map
  test is the guard, and clamping keeps any drift cosmetic.
- **Sentence-granular channels** deliver text in whole-sentence lumps of
  100+ characters. The backlog cap smooths this, but the first sentence on a
  grounded turn begins later than on a casual one. That is the existing
  latency, now visible as rhythm rather than a jump.
- **Composer gated on settle** adds up to about 2 s before the next send after
  a long reply. If that feels slow, a tap on the composer could fast-forward
  the schedule (set `start` back by `duration`). Left out of scope until
  someone feels it.
