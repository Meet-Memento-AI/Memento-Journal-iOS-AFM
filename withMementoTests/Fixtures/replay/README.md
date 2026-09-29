# Renderer replay gate (T2 / MEM-324)

Warehoused Study VI assistant turns (`study-vi-turns.jsonl`) plus a small
`raw-samples.json` set for true `ReplyRenderer.render` replay.

## Rendered-only until T1

Study VI rows carry **post-renderer** `text` only. `rawBody` arrives with
[T1 harness counters](https://linear.app/memento-ai/issue/MEM-322) on future
synthetic runs. Until then, the gate re-scores the rendered bubble with
`ChatEvalScoring.scoreGeneratedReply` and pins counts in
`baseline-violation-counts.json`.

## Regenerate

```bash
python3 scripts/eval/regen_renderer_replay_fixtures.py
python3 scripts/eval/regen_renderer_replay_fixtures.py --check   # merge CI
```

After a deliberate scorer change on macOS:

```bash
REGEN_RENDERER_REPLAY_BASELINE=1 xcodebuild test -scheme withMemento \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:withMementoTests/RendererReplayTests/test_regenerateRendererReplayBaseline
```

Source archive: `eval-archive/convo-sim/full-2026-09-27-tier.jsonl` (Study VI).
