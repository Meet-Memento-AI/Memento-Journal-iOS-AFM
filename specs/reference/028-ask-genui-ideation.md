# Ask GenUI — ideation

Companion to [spec 028](../028-ask-markdown-and-genui.md). Not a spec. Not a
component inventory. Sketches of what a restrained, data-first reply could
look like inside the existing chat bubble.

The model still writes the sentences. Swift still counts. The UI only shows a
measure when the question was a lookup, and only when the number is real.

---

## Posture

Most turns stay prose. GenUI is the exception: when someone asks *when*,
*how many*, *which*, or *whether it is in the journal at all*.

A computed block reports **content that already exists** — their words, their
dates, a count of matching entries, a span, an absence. It does not score
them, streak them, advise them, or name a pattern the sample cannot carry.

**Show n, or do not show the measure.** Four entries are a list. They are not
a trend line.

**One block per turn.** A count *or* a short list *or* a span. Not a dashboard
in a bubble.

**Their words over our charts.** If the honest artifact is three sentences
they already wrote, show the excerpts. Do not summarise them into a bar.

Today an entry is `title`, `text`, `createdAt`, `updatedAt`, `hasPhoto`.
Everything below that can be counted from those fields (plus retrieval
membership) is fair game now. Mood, topics, place arrive later; those
sketches are marked.

---

## The kit (eight primitives)

These are the only shapes. Use cases below are combinations, not new widgets.

### Measure

One number. A noun. The sample underneath.

```
┌─────────────────────────────┐
│  14                         │
│  entries about work         │
│  14 of 61 · Jan–Aug         │
└─────────────────────────────┘
```

If n is tiny, the number can still show (it is a count, not a claim). What
disappears is any comparison or chart that would turn 3 into a pattern.

### Span

First and last. Nothing in between implied.

```
┌─────────────────────────────┐
│  first          last        │
│  12 Mar  ——·——  2 Aug       │
│  5 entries in between       │
└─────────────────────────────┘
```

### List

Three to five dated excerpts. The existing citation row, in the bubble.

```
  ○  12 Mar
     “I hung up and sat in the car…”
  ○  2 Jan
     “I keep meaning to text her.”
  ○  18 Nov
     “Dinner at hers. Quiet.”
```

Cap at five. “And 9 more” is a link to the sheet, not a sixth row.

### Rank

Closed vocabulary + counts. Sorted. No bars unless n is honest (later).

```
  Work      14
  Sleep      9
  Family     6
  29 matching entries
```

### Pair

Two measures, same unit, same window. For contrast questions only.

```
  weekdays    22
  weekends     9
  31 entries · Jan–Aug
```

### Quote

Their text, verbatim, dated. Not a paraphrase.

```
┌─────────────────────────────┐
│  12 March                   │
│                             │
│  “I hung up and sat in      │
│   the car for a while.”     │
└─────────────────────────────┘
```

### Window

What was searched. Used when the answer is absence, or when retrieval is
narrower than the question sounded.

```
  searched  Mar–Aug  ·  61 entries
  matched   0
```

### Note

Low-n / quiet. Same type as body, quieter color. Not a warning icon.

```
  4 entries — too few to call a pattern.
```

---

## Use cases

Each one: the kind of question, what Swift actually counts, a lo-fi bubble,
when to stay silent instead.

The chrome around every grounded turn is unchanged:

```
Reviewed your journals  ›          ← only if retrieval ran
Heading                            ← only if analytical
Prose (markdown, short)
[ at most one primitive ]
speak  copy  👍  👎  ↻             ← after the stream ends
```

Casual “hey” never grows a primitive.

---

### 1. How many

*“How many times did I write about work this year?”*

**Count:** matching entries in the window.
**Not:** a mood, a lesson, “you write about work too much.”

```
Reviewed your journals  ›

Work, this year

You came back to it often — usually
as pressure, not as a plan.

┌─────────────────────────┐
│  14                     │
│  entries                │
│  14 of 61 · Jan–Aug     │
└─────────────────────────┘
```

n = 2 → still a Measure. Do not add a Pair or a Rank beside it.

---

### 2. The last time

*“When did I last write about my sister?”*

**Count:** max(`createdAt`) in the match set, plus that entry’s excerpt.
**Not:** a relationship summary.

```
Reviewed your journals  ›

You last wrote about her on 12 March,
after the phone call.

┌─────────────────────────┐
│  12 March               │
│                         │
│  “I hung up and sat in  │
│   the car for a while.” │
└─────────────────────────┘
```

One Quote is enough. A List of three is for “what have I written about her,”
not for “when did I last.”

---

### 3. When it started

*“When did I first mention the job?”*

**Count:** min(`createdAt`) in the match set.

```
Reviewed your journals  ›

The first time it shows up is 4 January.

┌─────────────────────────┐
│  4 Jan  ——·——  2 Aug    │
│  first mention · still  │
│  appearing              │
│  14 entries in between  │
└─────────────────────────┘
```

If there is only one match, skip Span. Show the Quote.

---

### 4. What is in there

*“What have I written about sleep?”*

**Count:** top matches, dated, their words.
**Not:** an inventory of every hit.

```
Reviewed your journals  ›

Sleep

A few nights, written down the next
morning.

  ○  2 Aug
     “Up at 4 again. The street was quiet.”
  ○  11 Jul
     “I slept through for the first time.”
  ○  3 Jun
     “Tea at 1am. I pretended it was fine.”

  3 of 9  ·  show all ›
```

Five rows max. The rest live in the existing citations sheet.

---

### 5. Show me those (follow-up)

*After a count or a theme: “show me.”*

**Count:** reuse the previous match set. No new retrieval story.

```
  ○  2 Aug    Up at 4 again.
  ○  11 Jul   I slept through.
  ○  3 Jun    Tea at 1am.
  ○  19 May   The neighbour’s dog.
  ○  8 Apr    I gave up on the mask.

  5 of 9  ·  show all ›
```

No heading. No recap paragraph. The list *is* the reply. This is the
restraint test: can we shut up.

---

### 6. Nothing there

*“What did I say about climbing?”*

**Count:** 0 in the window. The window is the artifact.

```
I don’t find anything about climbing.

┌─────────────────────────┐
│  searched  Mar–Aug      │
│  61 entries             │
│  matched   0            │
└─────────────────────────┘

Write about it once and I can
reflect it back.
```

Do not suggest related topics. Do not fill from world knowledge. Absence is
content.

---

### 7. Not since

*“Have I written about her lately?”*

**Count:** days/weeks since max(`createdAt`) of matches, if any.
**Careful:** this is a fact about the corpus, not a nudge to write.

```
Reviewed your journals  ›

Nothing about her since 12 March.

┌─────────────────────────┐
│  12 Mar      last entry │
│  5 months    since      │
│  4 entries   before that│
└─────────────────────────┘
```

If they have never written about her, this collapses to use case 6. Do not
say “you should reach out.”

---

### 8. A month

*“What did I write in March?”*

**Count:** entries with `createdAt` in that calendar month, oldest first.

```
Reviewed your journals  ›

March

Six entries. A lot of the job, and
one dinner.

  ○  4 Mar    The all-hands ran long.
  ○  12 Mar   I hung up and sat in the car.
  ○  19 Mar   Dinner at hers. Quiet.
  ○  23 Mar   I left before the cake.
  ○  28 Mar   Sunday. Nothing to say.

  5 of 6  ·  show all ›
```

If the month has one entry, Quote. If it has none, Window. If it has thirty,
still five rows + sheet — never a wall.

---

### 9. This week, last year

*“What was I writing about this time last year?”*

**Count:** entries in the same calendar week, previous year.
**n will often be 0 or 1.** That is fine.

```
Reviewed your journals  ›

This week last year

One entry. You were packing.

┌─────────────────────────┐
│  14 Aug 2025            │
│                         │
│  “Last box. I keep      │
│   finding mugs I don’t  │
│   remember buying.”     │
└─────────────────────────┘
```

0 matches → Window (“searched 11–17 Aug 2025 · 0”). Do not stretch the window
to “find something.”

---

### 10. Weekdays and weekends

*“Do I write more on weekends?”*

**Count:** match-set split by weekday. Same unit both sides.

```
Reviewed your journals  ›

More on weekdays. Weekends, when
they appear, are shorter.

┌─────────────────────────┐
│  weekdays          22   │
│  weekends           9   │
│  31 entries · Jan–Aug   │
└─────────────────────────┘
```

If either side is under the low-n line, drop the Pair. Show two Measures, or
just say it in prose with the two numbers and the Note.

```
  4 weekend entries — too few to compare.
```

---

### 11. Which months

*“Which months did I write about the job?”*

**Count:** matching entries bucketed by month. Presence, not intensity as a
feeling.

```
Reviewed your journals  ›

The job

It shows up in spring, then thins out.

  Jan  ███  4
  Feb  ███  4
  Mar  ████ 5
  Apr  █    1
  May  ·    0
  Jun  █    1

  15 entries · 2026
```

The bar is a **count of entries**, labelled with the number. Empty months
stay as `·  0` so May is visible as absence, not as a skipped row that hides
the hole.

If the year only has two months of data, this is a List, not a year strip.

---

### 12. Together

*“Do work and sleep show up together?”*

**Count:** entries matching A, matching B, matching both. Three numbers.

```
Reviewed your journals  ›

Work and sleep

They overlap more than they sit apart.

┌─────────────────────────┐
│  both              7    │
│  work only         7    │
│  sleep only        2    │
│  16 entries · Jan–Aug   │
└─────────────────────────┘
```

“More than” is allowed only as a reading of 7 vs 7 vs 2. If `both` is 1, the
block is a Quote from that one entry, plus the Note.

---

### 13. Ranked aboutness

*“What do I keep coming back to?”*

**Count:** closed ThemeCatalog (or retrieval clusters mapped onto it),
frequency in the window. **Not** free-form model tags.

```
Reviewed your journals  ›

What keeps coming back

Work, sleep, and family. In that order,
in this window.

  Work      14
  Sleep      9
  Family     6

  29 matching entries · Jan–Aug
```

Three rows. Not ten. Not a word cloud. Chips are optional under the rank,
same three words, tappable as the next question — not as therapy prompts.

n small → List of excerpts instead of a rank (a rank of 4 is a costume).

---

### 14. Their sentence

*“What did I actually say about leaving?”*

**Count:** one best-matching excerpt, verbatim. The data *is* the sentence.

```
Reviewed your journals  ›

Leaving

You said it once, plainly.

┌─────────────────────────┐
│  23 March               │
│                         │
│  “I left before the     │
│   cake. I didn’t want   │
│   to make a speech.”    │
└─────────────────────────┘
```

Do not decorate with a count of 1. The Quote is the measure. A second Quote
only if they asked “what else.”

---

### 15. Two moments, same thread

*“Has how I talk about the job changed?”*

We do **not** answer “changed.” We put two dated excerpts next to each other
and let them read.

```
Reviewed your journals  ›

The job, early and late

  ○  4 Jan
     “I think this role could be
      the one that sticks.”

  ○  2 Aug
     “I am tired of proving I am
      easy to work with.”
```

Two Quotes. No arrow labelled “growth.” No valence. If they want a reading,
they can ask a follow-up; the next turn may stay prose.

---

### 16. Long and short

*“Are my entries getting shorter?”*

**Count:** median character/word length in two windows, or a Pair of medians.
Length is a property of the text they wrote — not a productivity score.

```
Reviewed your journals  ›

Length

Recent ones are shorter.

┌─────────────────────────┐
│  Jan–Mar      420 words │
│  Jun–Aug      180 words │
│  median · 31 entries    │
└─────────────────────────┘
```

Never “you should write more.” If windows are uneven, say so in the n line.
If n < threshold, Note only.

---

### 17. With a photo

*“Which entries have photos?”*

**Count:** `hasPhoto == true`, dated. Content: they attached a picture.

```
Reviewed your journals  ›

Photos

Four entries carry a picture.

  ○  2 Aug    The street at 4am
  ○  19 Mar   Dinner
  ○  1 Jan    The desk
  ○  28 Dec   Walk home

  4 of 61
```

No thumbnails in the bubble (privacy, layout, speakability). The row opens
the entry, where the photo already lives.

---

### 18. A quiet stretch

*“Did I write in May?”*

**Count:** entries in that window = 0, adjacent months as context — still
counts, not a streak break.

```
I don’t find any entries in May.

┌─────────────────────────┐
│  Apr   4                │
│  May   0                │
│  Jun   2                │
└─────────────────────────┘
```

No “you fell off.” No calendar flame. Three numbers. If they did not ask
about May, do not volunteer a quiet stretch.

---

### 19. Before and after a day they named

*“How much did I write after the move?”*

**Count:** split the corpus (or the match set) on a date *they uttered*.
We do not infer “the move” as an event type.

```
Reviewed your journals  ›

After 14 August 2025

┌─────────────────────────┐
│  before            40   │
│  after             21   │
│  split on the date you  │
│  named                  │
└─────────────────────────┘
```

If we cannot parse a date from the question, do not guess. Ask in prose, or
Window.

---

### 20. How often, as spacing

*“How often do I write about sleep?”*

**Count:** median days between consecutive matches. A cadence fact, **not**
a streak.

```
Reviewed your journals  ›

Sleep

Four times, a few weeks apart.

┌─────────────────────────┐
│  every ~18 days         │
│  4 entries · Mar–Aug    │
│  11, 22, 19, 21 days    │
│  between                │
└─────────────────────────┘
```

If there are two matches, skip cadence — show Span. “Every ~18 days” from
n=2 is a costume.

---

### 21. Searched vs shown (transparency)

When retrieval ran and the question was broad.

**Count:** corpus size, retrieved size, cited size.

```
Reviewed your journals  ›

March

…

┌─────────────────────────┐
│  looked at    61        │
│  matched       6        │
│  showing       5        │
└─────────────────────────┘
```

Use rarely. It is for “what did you look at,” not as a footer on every turn.
The citation link already covers ordinary grounding.

---

### 22. Too few

*Any comparison or rank whose n is below the line.*

The primitive is the Note. Optionally a List, never a Pair or Rank.

```
Reviewed your journals  ›

Anxious weeks

You wrote it down four times.

  ○  2 Aug    Up at 4 again.
  ○  11 Jul   I slept through.
  ○  3 Jun    Tea at 1am.
  ○  8 Apr    I gave up on the mask.

  4 entries — too few to call a pattern.
```

This is the same question as a future mood chart. Until n is enough, this
*is* the chart.

---

### 23. Time of day (light)

*“Do I write at night?”*

**Count:** `createdAt` hour buckets. Only if we are willing to treat capture
time as “when they wrote,” which dictation-at-morning-about-the-night will
get wrong. Ideation only; easy to lie.

```
┌─────────────────────────┐
│  morning (5–11)     8   │
│  afternoon         12   │
│  evening           18   │
│  night (0–4)        4   │
│  by time saved · 42     │
└─────────────────────────┘
```

Caption must say **time saved**, not “when you felt it.” If that caption
feels dishonest, kill the use case.

---

### 24. Later — mood mix

Needs closed mood labels on entries (2.0 reflection). Until then, do not
approximate from prose.

```
Reviewed your journals  ›

March, as tagged

  tense    5
  tired    3
  calm     1

  9 entries with a mood · Mar
```

Same Rank primitive. Chart only when Patterns already draws this and n
clears the line. Chat inlines that view; it does not invent a second one.

---

### 25. Later — place, if they opted in

*“Did I write about home or away?”*

Only with coarse place strings they allowed. Never coordinates.

```
  home      11
  away       3
  14 entries with a place · Jan–Aug
```

If most entries have no place, Window: “14 of 61 have a place.” Do not
treat missing as “home.”

---

## Choosing, with restraint

A turn gets a primitive only if all of these hold:

1. The question is a lookup (when / how many / which / whether).
2. Swift can answer with a count, a date, a span, an excerpt, or zero.
3. n is shown.
4. There is at most one block.
5. The block would still be true if the model said nothing.
6. Nothing in the block advises, scores, streaks, or predicts.

Otherwise: markdown prose, or the Window.

Rough mapping:

| They ask | Primitive | Kill if |
|---|---|---|
| how many | Measure | — |
| last / first | Quote or Span | — |
| what have I written | List | more than 5 without a sheet link |
| show me | List, no prose | recap paragraph sneaks back |
| is X in there (no) | Window | related-topic suggestions |
| lately | Span + since | “you should write” |
| this month / last year | List or Quote | widened window to avoid 0 |
| more on weekends | Pair | either side below low-n |
| keep coming back | Rank (closed vocab) | free-form tags, or n too small |
| what did I say | Quote | paraphrase |
| has it changed | two Quotes | a valence arrow |
| shorter lately | Pair of medians | treated as a productivity score |
| photos | List | thumbnails in the bubble |
| a quiet month | Window + neighbours | shame copy |
| after [date] | Pair | inferred event, not their date |
| how often | cadence | n < 3 |
| mood / place | Rank | field does not exist yet |

---

## What this is not

- A generated screen. The composer, history, empty state stay as they are.
- GitHub-style heatmaps, streaks, “days since last entry” as a prod.
- Advice chips, coping cards, mood wheels before writing.
- Word clouds, markdown tables, ASCII spark lines as a substitute for Measure.
- The monthly Patterns dashboard, shrunk.
- A second Insights visual language (the old purple cards) inside chat.

The bubble should still read as Memento talking, with a number or three of
their own sentences sitting quietly underneath — only when they asked to see
the record.
