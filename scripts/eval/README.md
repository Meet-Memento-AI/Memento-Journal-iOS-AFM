# Eval runner (Mac + device)

Local and self-hosted CI commands for on-device Foundation Models work (spec
022, Ask chat 100/100 plan **T5**). Merge CI stays online-only (`CI_ONLINE=1`);
this lane needs Apple Intelligence hardware.

## Prerequisites

1. **Xcode 27+** with the iOS 27 SDK (`xcodebuild -version`).
2. **Git LFS** pulled (`git lfs pull`) so voice weights are not pointer files.
3. **Self-hosted runner** (optional for CI): labels
   `[self-hosted, macOS, ARM64, ios, xcode]` on a Mac in the
   `Meet-Memento-AI/Memento-Journal-iOS-AFM` repo — not a public fork.
4. **Physical iPhone** (recommended for gate proof): Core 8 GB class minimum;
   set `IOS_DEVICE_DESTINATION=platform=iOS,id=<UDID>`. Simulator uses the
   host Mac model — label results accordingly (spec 051 R6).
5. **`fm` CLI** (optional): macOS 27 `fm chat` for quick prompt iteration without
   a full test run (`MEMENTO_EVAL_PROFILE=fm`).

## Profiles

| Profile | Script env | What runs |
|---------|------------|-----------|
| `smoke` | `MEMENTO_EVAL_PROFILE=smoke` | 10× `ConversationSimulation` (`empty` arm) |
| `gate` | `MEMENTO_EVAL_PROFILE=gate` | 50× convo-sim + `ChatEvalGate` |
| `fm` | `MEMENTO_EVAL_PROFILE=fm` | `scripts/eval/fm_chat_smoke.sh` only |

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export IOS_DEVICE_DESTINATION='platform=iOS,id=YOUR_DEVICE_UDID'

MEMENTO_EVAL_PROFILE=smoke scripts/eval/run_mac_eval.sh
```

Artifacts land under `TestResults-device-eval.xcresult` unless
`MEMENTO_EVAL_RESULT` is set. Convo-sim JSONL follows `ConversationSimulation`
rules (`CONVO_SIM_OUT` when set).

## Behavioural device gate (T6)

`scripts/ci/detect_behavioural_change.sh` compares the PR to its base and sets
`required=true` when prompt versions, renderer version, `PromptExperiments`
defaults, `ReplyChannel` caps/temperature, or safety packs change.

On GitHub, `.github/workflows/ios-device-eval.yml` runs the gate job on
**same-repo** pull requests when `required=true`. Other PRs skip the heavy step
and still report green so branch protection can require the check name.

## Analysis (existing)

- `analyze_convo_sim.py`, `export_convo_sim_json.py` — Study pages / metrics
- `import_run.sh` — optional warehouse ingest (spec 043)
