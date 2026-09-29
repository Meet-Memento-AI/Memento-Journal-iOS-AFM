
# full-2026-09-27-tier.jsonl

- **started_at**: `2026-09-27T17:25:28Z`
- **finished_at**: `2026-09-27T22:03:42Z`
- **os_version**: `Version 27.0 (Build 24A434)`
- **runs_per_arm**: `100`
- **min_messages**: `20`
- **max_messages**: `50`
- **history_message_limit**: `24`
- **arm `empty`**: 0 entries
- **arm `persona`**: 262 entries, 2025-11-01 → 2026-07-22
- **notes**: Study VI. Prompt unchanged from Study IV (ask-core@19, chat-companion@1); the model underneath moved to AFM 3 Core Advanced (spec 051). Pre-registered at 2a2ad63.

6854 messages · 3427 assistant · 90 error · 18 Swift-computed · **3319 generated**

### Headline, by arm

| arm     | generated | gating violation | invented material | notebook    | cited       |
|---------|-----------|------------------|-------------------|-------------|-------------|
| empty   | 1671      | 105 (6.3%)       | 0 (0.0%)          | 0 (0.0%)    | 0 (0.0%)    |
| persona | 1648      | 187 (11.3%)      | 37 (2.2%)         | 278 (16.9%) | 615 (37.3%) |

### Violations by code (occurrences, generated turns only)

| code                   | empty | persona | total |
|------------------------|-------|---------|-------|
| gen.hitTokenCap        | 25    | 12      | 37    |
| hall.unbackedDate      | 4     | 30      | 34    |
| hall.uncitedQuote      | 0     | 37      | 37    |
| leak.placeholder       | 0     | 25      | 25    |
| leak.promptTag         | 0     | 2       | 2     |
| leak.schemaField       | 0     | 1       | 1     |
| leak.sectionLabel      | 0     | 1       | 1     |
| rule.bannedOpener      | 15    | 8       | 23    |
| rule.bannedPhrase      | 15    | 17      | 32    |
| rule.emptyHeading      | 0     | 5       | 5     |
| rule.entryCount        | 0     | 1       | 1     |
| rule.multipleH3        | 0     | 2       | 2     |
| rule.multipleQuestions | 66    | 104     | 170   |
| rule.noOpen            | 9     | 0       | 9     |

### Violation rate by arm × channel

| arm     | channel   | generated | gating violation | invented material |
|---------|-----------|-----------|------------------|-------------------|
| empty   | companion | 1643      | 99 (6.0%)        | 0 (0.0%)          |
| empty   | redirect  | 18        | 3 (16.7%)        | 0 (0.0%)          |
| empty   | phatic    | 10        | 3 (30.0%)        | 0 (0.0%)          |
| persona | thread    | 1231      | 151 (12.3%)      | 32 (2.6%)         |
| persona | notebook  | 278       | 28 (10.1%)       | 5 (1.8%)          |
| persona | companion | 116       | 5 (4.3%)         | 0 (0.0%)          |
| persona | redirect  | 13        | 0 (0.0%)         | 0 (0.0%)          |
| persona | phatic    | 10        | 3 (30.0%)        | 0 (0.0%)          |

### TurnType × ReplyChannel (all assistant turns)

| turn_type                     | phatic | continuer | meta | companion | thread | notebook | statistic | redirect | total | rate  |
|-------------------------------|--------|-----------|------|-----------|--------|----------|-----------|----------|-------|-------|
| social                        | 20     | 0         | 0    | 0         | 0      | 0        | 0         | 0        | 20    | 0.6%  |
| acknowledgement (never fired) | 0      | 0         | 0    | 0         | 0      | 0        | 0         | 0        | 0     | 0.0%  |
| meta (never fired)            | 0      | 0         | 0    | 0         | 0      | 0        | 0         | 0        | 0     | 0.0%  |
| share                         | 0      | 0         | 0    | 212       | 0      | 0        | 0         | 0        | 212   | 6.2%  |
| followup                      | 0      | 0         | 0    | 1377      | 1245   | 0        | 0         | 0        | 2622  | 76.5% |
| journalQuery                  | 0      | 0         | 0    | 238       | 0      | 279      | 0         | 0        | 517   | 15.1% |
| quantitative                  | 0      | 0         | 0    | 0         | 0      | 0        | 18        | 0        | 18    | 0.5%  |
| reflectiveQuestion            | 0      | 0         | 0    | 1         | 0      | 0        | 0         | 0        | 1     | 0.0%  |
| offdomain                     | 0      | 0         | 0    | 0         | 0      | 0        | 0         | 35       | 35    | 1.0%  |
| correction                    | 0      | 0         | 0    | 0         | 2      | 0        | 0         | 0        | 2     | 0.1%  |

### QuestionShape

| question_shape    | empty | persona | total |
|-------------------|-------|---------|-------|
| entity            | 10    | 10      | 20    |
| interpretationCut | 17    | 8       | 25    |
| inventory         | 34    | 34      | 68    |
| list              | 10    | 10      | 20    |
| specific          | 1362  | 1329    | 2691  |
| temporal          | 222   | 183     | 405   |
| venting           | 88    | 110     | 198   |

### ResponsePolicy

| response_policy | empty | persona | total |
|-----------------|-------|---------|-------|
| answer          | 1628  | 1556    | 3184  |
| list            | 10    | 10      | 20    |
| reflect         | 88    | 110     | 198   |
| retract         | 17    | 8       | 25    |

### EvidenceState

| evidence_state | empty | persona | total |
|----------------|-------|---------|-------|
| matched        | 0     | 1684    | 1684  |
| none           | 1743  | 0       | 1743  |

### TrustZone

| zone     | empty | persona | total |
|----------|-------|---------|-------|
| z0Device | 1677  | 1660    | 3337  |

### Citations

| arm     | turns with a citation | citations | mean per cited turn | median entry age (days) |
|---------|-----------------------|-----------|---------------------|-------------------------|
| empty   | 0 (0.0%)              | 0         | —                   | not recorded            |
| persona | 615 (37.3%)           | 1341      | 2.18                | 185                     |

### Latency and generation state

| arm     | n    | p50   | p90   | max    | model p50 | degraded | tools called |
|---------|------|-------|-------|--------|-----------|----------|--------------|
| empty   | 1671 | 1.67s | 2.11s | 3.61s  | 1.66s     | 0        | 0            |
| persona | 1648 | 3.94s | 7.99s | 15.63s | 3.94s     | 0        | 0            |

### Before vs after the history window closes

| arm     | before window closes | gating rate | after window closes | gating rate |
|---------|----------------------|-------------|---------------------|-------------|
| empty   | 1219                 | 6.0%        | 452                 | 7.1%        |
| persona | 1222                 | 11.6%       | 426                 | 10.6%       |

### Spec 050 — did the model point, or did the renderer clean up?

| arm     | with a pack | pack matched | pointed (quote)       | pointed (date)         | needed cleanup | chips |
|---------|-------------|--------------|-----------------------|------------------------|----------------|-------|
| empty   | 1671        | 0 (0.0%)     | 0 (— of matched)      | 0 (— of matched)       | 1 (0.1%)       | 0     |
| persona | 1648        | 615 (37.3%)  | 89 (14.5% of matched) | 157 (25.5% of matched) | 36 (2.2%)      | 98    |

### Renderer counters (occurrences)

| counter            | empty | persona | reads as                                                |
|--------------------|-------|---------|---------------------------------------------------------|
| adopted_quotes     | 0     | 20      | model wrote pack text verbatim but unmarked             |
| stripped_italics   | 0     | 17      | model still reached for italics                         |
| dropped_quotations | 1     | 4       | model quoted something nothing backs — sentence dropped |
| dropped_markers    | 0     | 227     | marker resolved to nothing                              |
| duplicate_quotes   | 0     | 14      | same quote twice                                        |
| unwrapped_bold     | 0     | 270     | bold not backed by the pack                             |
| stripped_dates     | 0     | 45      | raw date in glue prose — 050 R3 bans these              |
| dropped_headings   | 0     | 119     | heading the renderer could not back                     |
| slots              | 0     | 3016    | evidence slots offered to the model                     |

### Conversation shape (and harness artefacts, which are not app findings)

| arm     | conversations | reached planned length | median achieved | fallback person turns | person generation errors | designed refusals |
|---------|---------------|------------------------|-----------------|-----------------------|--------------------------|-------------------|
| empty   | 100           | 98 (98.0%)             | 36.0            | 5                     | 32                       | 55                |
| persona | 100           | 100 (100.0%)           | 32.0            | 0                     | 4                        | 22                |

### Persona

| persona_id    | empty rate     | persona rate   | delta   | worse with a journal? |
|---------------|----------------|----------------|---------|-----------------------|
| p01-clipped   | 6/166 (3.6%)   | 27/182 (14.8%) | +11.2pp | yes                   |
| p02-spiller   | 15/177 (8.5%)  | 16/137 (11.7%) | +3.2pp  | yes                   |
| p03-skeptic   | 6/162 (3.7%)   | 9/166 (5.4%)   | +1.7pp  | yes                   |
| p04-tester    | 12/198 (6.1%)  | 13/178 (7.3%)  | +1.2pp  | yes                   |
| p05-griever   | 7/165 (4.2%)   | 34/178 (19.1%) | +14.9pp | yes                   |
| p06-planner   | 19/166 (11.4%) | 18/169 (10.7%) | -0.8pp  |                       |
| p07-nostalgic | 11/171 (6.4%)  | 17/140 (12.1%) | +5.7pp  | yes                   |
| p08-chatty    | 15/165 (9.1%)  | 14/181 (7.7%)  | -1.4pp  |                       |
| p09-guarded   | 4/122 (3.3%)   | 23/158 (14.6%) | +11.3pp | yes                   |
| p10-analyst   | 10/179 (5.6%)  | 16/159 (10.1%) | +4.5pp  | yes                   |

### Opening intent

| intent_id           | empty rate     | persona rate   | delta   | worse with a journal? |
|---------------------|----------------|----------------|---------|-----------------------|
| i01-broad-recall    | 6/140 (4.3%)   | 11/154 (7.1%)  | +2.9pp  | yes                   |
| i02-entity-recall   | 7/155 (4.5%)   | 19/166 (11.4%) | +6.9pp  | yes                   |
| i03-temporal        | 8/170 (4.7%)   | 19/162 (11.7%) | +7.0pp  | yes                   |
| i04-nomatch-bait    | 5/136 (3.7%)   | 21/179 (11.7%) | +8.1pp  | yes                   |
| i05-small-talk      | 20/183 (10.9%) | 19/161 (11.8%) | +0.9pp  | yes                   |
| i06-venting         | 6/165 (3.6%)   | 23/148 (15.5%) | +11.9pp | yes                   |
| i07-correction      | 10/178 (5.6%)  | 27/161 (16.8%) | +11.2pp | yes                   |
| i08-multi-hop       | 17/170 (10.0%) | 21/175 (12.0%) | +2.0pp  | yes                   |
| i09-advice-seeking  | 11/167 (6.6%)  | 17/171 (9.9%)  | +3.4pp  | yes                   |
| i10-crisis-adjacent | 15/207 (7.2%)  | 10/171 (5.8%)  | -1.4pp  |                       |
