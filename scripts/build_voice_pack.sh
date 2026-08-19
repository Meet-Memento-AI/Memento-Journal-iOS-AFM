#!/usr/bin/env bash
#
# build_voice_pack.sh — reproduce MeetMemento/Resources/Voices/ from the base model.
# Spec 030 (bundled model assets) / 031 R5 / DEC-012.
#
# The voice pack ships INSIDE the app binary — there is no download path at
# runtime (REQ-TTS-001/002). This script is the recipe that produced it, kept so
# the artifact can be rebuilt when the model, the precision choice, or the CoreML
# format version changes. A model nobody can rebuild is a model nobody can update.
#
# Shipping configuration (spec 030 R7, and the reason the app clears the App
# Store's 200 MB cellular-prompt threshold):
#
#   VectorEstimator     8-bit k-means palettized   243.73 -> 61.70 MB
#   Vocoder             FP16, untouched             48.39 MB
#   TextEncoder         FP16, untouched             34.51 MB
#   DurationPredictor   FP16, untouched              1.82 MB
#   voice_styles/       F1, F2, M1, M3 only          1.12 MB
#                                                  ---------
#                                                   ~148 MB
#
# The vocoder is deliberately NOT quantized: artifacts land hardest there, as
# ringing and metallic texture, and it is only 48 MB. Quality risk is confined to
# one module at the mildest setting (spec 036, W2 listening protocol).
#
# Only four style vectors are vendored. The base model publishes ten
# (F1-F5, M1-M5); the other six are never copied, so no unshipped voice can
# appear in the picker by accident (spec 033 R1).
#
# Usage:  scripts/build_voice_pack.sh <path-to-base-model-dir>
#
# The base directory is the CoreML export containing {TextEncoder,
# DurationPredictor, VectorEstimator, Vocoder}.mlpackage, config.json, tts.json,
# unicode_indexer.json and voice_styles/. Its provenance and checksums are
# recorded in specs/reference/technology/13-neural-tts-coreml.md.
#
# Requires: Xcode (xcrun coremlcompiler), python3 with coremltools + scikit-learn.
set -euo pipefail

BASE="${1:?usage: build_voice_pack.sh <path-to-base-model-dir>}"
DEST="${DEST:-MeetMemento/Resources/Voices}"
PYTHON="${PYTHON:-python3}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d "$BASE/VectorEstimator.mlpackage" ] || { echo "not a base model dir: $BASE"; exit 1; }

echo "==> verifying base artifact"
"$PYTHON" - "$BASE" <<'PY'
import hashlib, sys, pathlib
base = pathlib.Path(sys.argv[1])
# Pinned SHA-256 of the base weights this recipe was authored against.
# A mismatch is not automatically fatal — the upstream may have republished —
# but it MUST be investigated and this table updated deliberately, never silently.
EXPECTED = {
    "TextEncoder":       "9618a75954419ab1",
    "DurationPredictor": "7f709c544087966d",
    "VectorEstimator":   "593cb7df14efd8d9",
    "Vocoder":           "b45e4c17a45cc4de",
}
bad = False
for graph, want in EXPECTED.items():
    p = base / f"{graph}.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
    got = hashlib.sha256(p.read_bytes()).hexdigest()[:16]
    flag = "ok " if got == want else "MISMATCH"
    if got != want: bad = True
    print(f"    {flag} {graph}: {got}")
if bad:
    print("\n    Base artifact differs from the pinned revision. Investigate before shipping.")
PY

echo "==> palettizing VectorEstimator to 8-bit"
"$PYTHON" - "$BASE" "$STAGE" <<'PY'
import sys, coremltools as ct
from coremltools.optimize import coreml as cto
base, stage = sys.argv[1], sys.argv[2]
m = ct.models.MLModel(f"{base}/VectorEstimator.mlpackage", skip_model_load=True)
cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(mode="kmeans", nbits=8))
cto.palettize_weights(m, cfg).save(f"{stage}/VectorEstimator.mlpackage")
PY

echo "==> compiling to .mlmodelc"
OUT="$STAGE/out"; mkdir -p "$OUT"
xcrun coremlcompiler compile "$STAGE/VectorEstimator.mlpackage"      "$OUT" >/dev/null
xcrun coremlcompiler compile "$BASE/Vocoder.mlpackage"               "$OUT" >/dev/null
xcrun coremlcompiler compile "$BASE/TextEncoder.mlpackage"           "$OUT" >/dev/null
xcrun coremlcompiler compile "$BASE/DurationPredictor.mlpackage"     "$OUT" >/dev/null

echo "==> assembling pack"
# NOTE: file-system-synchronized groups FLATTEN every resource to the bundle
# root — there is no Voices/ subdirectory at runtime. `config.json` is far too
# generic a name to occupy the shared root namespace, so it is scoped here.
cp "$BASE/config.json"           "$OUT/voice_config.json"
cp "$BASE/tts.json"              "$OUT/tts.json"
cp "$BASE/unicode_indexer.json"  "$OUT/unicode_indexer.json"
mkdir -p "$OUT/voice_styles"
for v in F1 F2 M1 M3; do cp "$BASE/voice_styles/$v.json" "$OUT/voice_styles/"; done

# Strip anything check_archive_hygiene.sh would reject. Directory-level exclusion
# does not work with file-system-synchronized groups — every stray .md/.toml/.svg
# would otherwise need an individual membershipExceptions entry.
find "$OUT" \( -name "*.md" -o -name "*.toml" -o -name "*.svg" -o -name "*.sql" \) -delete

rm -rf "${DEST:?}"/*
mkdir -p "$DEST"
cp -R "$OUT/." "$DEST/"

echo "==> done: $(du -sh "$DEST" | cut -f1) in $DEST"
find "$DEST" -maxdepth 1 -mindepth 1 -exec basename {} \; | sort | sed 's/^/    /'
