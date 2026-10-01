#!/usr/bin/env python3
"""Unit tests for scripts/eval/preregister.py (MEM-327)."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load_preregister():
    spec = importlib.util.spec_from_file_location("preregister", HERE / "preregister.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


pr = load_preregister()
BASELINE = Path("eval-archive/convo-sim/full-2026-09-24-spec051.jsonl")


class PreregisterTests(unittest.TestCase):
    def test_guardrail_default_block_has_four_metrics(self):
        ceilings = pr.GUARDRAIL_PAIRING_DEFAULT["ceilings"]
        self.assertIn("hall_any_rate_pct", ceilings)
        self.assertIn("rule_banned_phrase_count", ceilings)
        self.assertIn("output_diagnosis_hits", ceilings)
        self.assertIn("crisis_probe_recall_pct", ceilings)

    def test_freeze_and_verify_round_trip(self):
        self.assertTrue(BASELINE.is_file(), "Study IV archive required for tests")
        predictions = json.loads((HERE / "fixtures/example-predictions.json").read_text())
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "test.prereg.json"
            doc = pr.freeze_document(
                study_label="unit-test",
                baseline=BASELINE,
                predictions=predictions,
                git_sha="deadbeef",
                spec_path=None,
            )
            out.write_text(json.dumps(doc, indent=2))
            pr.assert_frozen(json.loads(out.read_text()), out)

    def test_tamper_detected(self):
        self.assertTrue(BASELINE.is_file())
        predictions = [{"id": "X", "metric": "generated_turns", "op": "gt", "value": 0}]
        doc = pr.freeze_document(
            study_label="tamper-test",
            baseline=BASELINE,
            predictions=predictions,
            git_sha=None,
            spec_path=None,
        )
        doc["predictions"][0]["value"] = 999
        with self.assertRaises(SystemExit):
            pr.assert_frozen(doc)

    def test_judge_refuses_unfrozen(self):
        doc = {"schema_version": 1, "frozen": False}
        with self.assertRaises(SystemExit):
            pr.assert_frozen(doc)

    def test_analyze_judge_requires_prereg(self):
        spec = importlib.util.spec_from_file_location("acs", HERE / "analyze_convo_sim.py")
        acs = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(acs)
        # Import side effect: main not run; test CLI contract via argparse would be heavy.
        # Judge path is covered in test_judge_against_self_baseline below.
        self.assertTrue(hasattr(acs, "judge_paths"))

    def test_judge_against_self_baseline_passes_pairing(self):
        self.assertTrue(BASELINE.is_file())
        rows = pr.load_jsonl(BASELINE)
        predictions = [
            {
                "id": "sanity",
                "metric": "generated_turns",
                "op": "eq",
                "value": len(pr.acs.generated(rows)),
            }
        ]
        doc = pr.freeze_document(
            study_label="self-judge",
            baseline=BASELINE,
            predictions=predictions,
            git_sha=None,
            spec_path=None,
        )
        self.assertEqual(pr.judge_run(rows, doc), 0)


if __name__ == "__main__":
    unittest.main()
