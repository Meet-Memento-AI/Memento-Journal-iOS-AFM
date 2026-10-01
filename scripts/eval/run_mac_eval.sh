#!/usr/bin/env bash
# T5 — self-hosted Mac eval runner (spec 022 / Ask 100 plan phase 0).
#
# Profiles (MEMENTO_EVAL_PROFILE):
#   smoke  — 10 conversations (gate calibration; ~15–25 min on Core hardware)
#   gate   — 50-conversation device-gate slice (pre-registered thresholds: T4/T8)
#   fm     — fm CLI only (no xcodebuild)
#
# Issue categories (for logs / xcresult triage — map to EvalIssueCategory in tests):
#   convo_sim | chat_eval | fm_cli | intelligence_service
#
# Examples:
#   MEMENTO_EVAL_PROFILE=smoke IOS_DEVICE_DESTINATION='platform=iOS,id=…' \
#     scripts/eval/run_mac_eval.sh
#
#   MEMENTO_EVAL_PROFILE=gate \
#     scripts/eval/run_mac_eval.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

PROFILE="${MEMENTO_EVAL_PROFILE:-smoke}"
SCHEME="${MEMENTO_EVAL_SCHEME:-withMemento}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

DEST="${IOS_DEVICE_DESTINATION:-${IOS_SIM_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}}"
RESULT="${MEMENTO_EVAL_RESULT:-TestResults-device-eval.xcresult}"

git_sha="$(git rev-parse HEAD)"
git_branch="$(git rev-parse --abbrev-ref HEAD)"
dirty="clean"
if ! git diff-index --quiet HEAD --; then dirty="dirty"; fi

echo "eval_runner profile=$PROFILE dest=$DEST sha=$git_sha branch=$git_branch tree=$dirty"

if [[ "$PROFILE" == "fm" ]]; then
  exec bash scripts/eval/fm_chat_smoke.sh
fi

case "$PROFILE" in
  smoke)
    export TEST_RUNNER_CONVO_SIM=1
    export TEST_RUNNER_CONVO_SIM_RUNS=10
    export TEST_RUNNER_CONVO_SIM_ARMS=empty
    export TEST_RUNNER_CONVO_SIM_LABEL="device-smoke"
    export TEST_RUNNER_CONVO_SIM_GIT_SHA="$git_sha"
    export TEST_RUNNER_CONVO_SIM_GIT_BRANCH="$git_branch"
    export TEST_RUNNER_CONVO_SIM_GIT_DIRTY="$dirty"
    ONLY=(
      -only-testing:withMementoTests/ConversationSimulation
    )
    ;;
  gate)
    export TEST_RUNNER_CONVO_SIM=1
    export TEST_RUNNER_CONVO_SIM_RUNS=50
    export TEST_RUNNER_CONVO_SIM_ARMS=empty
    export TEST_RUNNER_CONVO_SIM_LABEL="device-gate"
    export TEST_RUNNER_CONVO_SIM_GIT_SHA="$git_sha"
    export TEST_RUNNER_CONVO_SIM_GIT_BRANCH="$git_branch"
    export TEST_RUNNER_CONVO_SIM_GIT_DIRTY="$dirty"
    ONLY=(
      -only-testing:withMementoTests/ConversationSimulation
      -only-testing:withMementoTests/ChatEvalGate
    )
    ;;
  *)
    echo "Unknown MEMENTO_EVAL_PROFILE=$PROFILE (use smoke|gate|fm)" >&2
    exit 2
    ;;
esac

# Unset merge-lane skip so generation runs when the model is available.
unset CI_ONLINE
unset TEST_RUNNER_CI_ONLINE

rm -rf "$RESULT"
set -x
xcodebuild \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -resultBundlePath "$RESULT" \
  -parallel-testing-enabled NO \
  -skip-testing:withMementoUITests \
  "${ONLY[@]}" \
  test
set +x

echo "OK   xcodebuild finished · categories=convo_sim,chat_eval · result=$RESULT"
bash scripts/eval/fm_chat_smoke.sh || true
