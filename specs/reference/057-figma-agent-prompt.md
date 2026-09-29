# Figma Agent prompt — Ask GenUI components

Copy everything below the line into Figma Agent. It is self-contained.

---

You are designing **GenUI components for Memento**, a private iOS journaling app. The AI chat (“Ask”) already looks like Claude/ChatGPT: user bubbles on the right, assistant replies **full-width with no bubble**, a typewriter reveal, then a small action bar (speak, copy, thumbs, regenerate).

GenUI is **not a generated screen**. It is **at most one data block** sitting under a short assistant caption, inside that existing transcript. Swift computes the numbers and excerpts; the model only writes the sentences. Design for **restraint**: the block should feel like a record from their journal, not a dashboard, not Insights, not a wellness score.

Work in a new page named `Ask / GenUI iterations`. iPhone 16 width (393pt). Design **light and dark**. Use the tokens below — do not invent a second palette.

## Product voice

- Archivist, not therapist. Report what they wrote and when. No advice, streaks, scores, “you should write,” coping chips, mood wheels, or follow-up question stacks.
- Most turns stay prose-only. These components appear only for lookups: *when, how many, which, is it in the journal.*
- Always show **n** (sample size) on any measure. Four entries are a list, not a trend.
- Their **verbatim words** beat our charts.

## Visual system (match shipping UI)

**Type**
- Display (large numbers / optional h2): **Lora Semibold**
- UI and body: **Manrope** (Regular / Medium / Semibold / Bold)
- Scale: number ~32pt Lora; section heading 24pt Manrope Bold; body 16pt Manrope; caption 13pt Manrope Medium
- Date pills: caption on a capsule, muted fill

**Color (light)**
- Background `#FFFFFF` · foreground `#1C2329` · muted text `#66707A`
- Muted fill `#F0F4F7` · border `#E2E8ED`
- Primary (links, “Reviewed your journals”) `#7B3EC9`
- User bubble fill: light gray secondary, not purple

**Color (dark)**
- Background `#1C2329` · foreground `#F0F4F7` · muted text `#CFD6DC`
- Primary `#9869D5`

**Shape**
- Content cards: 12–20pt continuous corners, **flat** (no heavy shadow, no glass on the data block — glass is for the header and composer only)
- Radius 32 is for the composer / sheets, not for these inner blocks
- Do **not** use the old Insights look: no deep-purple `#361562` cards, no sparkle “SENTIMENT ANALYSIS” headers, no gradient borders

**Chat chrome to wrap every in-situ frame**
1. Optional text link, primary, Manrope Bold 14: `Reviewed your journals  ›`
2. Optional heading (Manrope Bold 24)
3. 2–4 sentences of body (Manrope 16, generous line height)
4. **One** GenUI block
5. Action bar: 5 small muted icons (speaker, copy, thumbs up/down, regenerate) — 14pt, 8pt gap, appear only after the reply is “done”

Do not redesign the composer, header, or empty state.

## Components to iterate (eight primitives)

Design each as a **component** (variants: light/dark, and empty/low-n where noted), then place it in a chat frame with the sample copy.

1. **Measure** — one number, a noun, n + window underneath.  
   Sample: `14` / `entries about work` / `14 of 61 · Jan–Aug`

2. **Quote** — date + verbatim excerpt, their words.  
   Sample: `12 March` / “I hung up and sat in the car for a while.”

3. **List** — 3–5 dated excerpt rows (hollow 13pt circle, capsule date, muted excerpt). Cap at 5. Footer: `3 of 9  ·  show all ›`  
   Reuse the citation-timeline language already in the app (circle + date pill + excerpt), inlined in the bubble.

4. **Window** (absence) — searched range, corpus size, matched 0. Quiet, not an error.  
   Sample: `searched  Mar–Aug` / `61 entries` / `matched  0`  
   Caption above: “I don’t find anything about climbing.”

5. **Span** — first —— last, count in between.  
   Sample: `4 Jan  ——·——  2 Aug` / `14 entries in between`

6. **Pair** — two measures, same unit.  
   Sample: `weekdays  22` / `weekends  9` / `31 entries · Jan–Aug`

7. **Rank** — three rows, closed vocabulary + counts, no word cloud.  
   Sample: `Work 14` / `Sleep 9` / `Family 6` / `29 matching entries · Jan–Aug`

8. **Note** (low-n) — one quiet line, no warning icon: `4 entries — too few to call a pattern.`  
   Show Note replacing Pair/Rank, optionally above a short List.

Also design **collapse states** (same component family):
- Measure with n = 2 (number still OK; no extra chart)
- List with n = 1 → becomes Quote
- Pair that failed the floor → Note + 3-row List
- Rank that failed the floor → List, not a tiny bar chart

## Produce three visual iterations

Keep the **same information architecture** in all three. Change only density, enclosure, and emphasis. Label frames `A / B / C`.

**A — Bare (preferred direction to explore hard)**  
No card chrome. Number and lists sit in the type column like the prose. Maximum restraint. Closest to today’s citation link.

**B — Quiet card**  
One flat rounded rect (`card` fill, 12–16pt radius, no border or a hairline `#E2E8ED`). Still one block. Number is large but not a hero metric tile.

**C — Structured record**  
Slightly more editorial: a 13pt caps label (`WORK, THIS YEAR` or the window) in muted, then the number or list. Still not a dashboard. Still no icons-for-decoration.

For each iteration, build:
- A **component stickersheet** (all 8 primitives + collapse states)
- **Four in-situ chat screens** (full phone, light):  
  1. How many (Measure)  
  2. Last time (Quote)  
  3. What’s in there (List + show all)  
  4. Nothing found (Window)  
- Repeat those four in **dark**, iteration A only (enough to check contrast)

Optional fifth in-situ (iteration A, light): follow-up **“show me”** — **no caption**, just the List. This is a real product state (no model prose).

## Sample journal (keep copy exactly)

Persona: someone journaling about work and a sister. Do not rewrite into therapy-speak.

How many  
Heading: `Work, this year`  
Body: `You came back to it often — usually as pressure, not as a plan.`

Last time  
Body: `You last wrote about her on 12 March, after the phone call.`

List rows  
`2 Aug` — “Up at 4 again. The street was quiet.”  
`11 Jul` — “I slept through for the first time.”  
`3 Jun` — “Tea at 1am. I pretended it was fine.”

Nothing found  
Body: `I don’t find anything about climbing.` then `Write about it once and I can reflect it back.`

## Hard don’ts

- No extra GenUI blocks in one reply
- No charts, heatmaps, contribution grids, rings, gauges, or sparkline-as-decoration (month counts may be a **labelled** row `Jan  4`, not a GitHub graph)
- No emoji, no sparkles, no “AI” badge, no gradient hero numbers
- No markdown tables; no fake buttons like “Save as entry” or “Try journaling about this”
- No thumbnails in the list
- Do not restyle the floating glass composer
- Do not add a third color beyond gray + primary purple
- Dynamic Type: leave room; don’t clip 2-line excerpts

## What to write on the page

A short annotation next to each iteration (A/B/C): **when this enclosure helps** and **when it feels like a dashboard**. Then pick a recommended default (likely A or B) and say why in one sentence.

Start with iteration A stickersheet, then the four light chat screens, then B and C. Do not generate a marketing landing page.
