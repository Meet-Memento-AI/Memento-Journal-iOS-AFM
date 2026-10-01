#!/usr/bin/env python3
"""Unit tests for scripts/eval/judge_convo.py (CQ2)."""
from __future__ import annotations

import csv
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
JUDGE_PATH = REPO / "scripts/eval/judge_convo.py"

spec = importlib.util.spec_from_file_location("judge_convo", JUDGE_PATH)
judge = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(judge)


class JudgeConvoTests(unittest.TestCase):
    def test_dry_run_scores_in_range(self):
        scores = judge.dry_run_scores("run/000#3")
        self.assertEqual(set(scores.keys()), set(judge.CRITERIA))
        for value in scores.values():
            self.assertGreaterEqual(value, 1)
            self.assertLessEqual(value, 5)

    def test_linear_weighted_kappa_perfect(self):
        labels = [3, 4, 5, 2, 3]
        self.assertAlmostEqual(judge.linear_weighted_kappa(labels, labels), 1.0, places=5)

    def test_linear_weighted_kappa_opposite(self):
        a = [1, 1, 5, 5]
        b = [5, 5, 1, 1]
        k = judge.linear_weighted_kappa(a, b)
        self.assertLess(k, 0.2)

    def test_refuse_non_synthetic_path(self):
        with tempfile.NamedTemporaryFile(suffix=".jsonl") as tmp:
            path = Path(tmp.name)
            with self.assertRaises(SystemExit):
                judge.assert_synthetic_jsonl(path)

    def test_extract_turns_from_fixture_jsonl(self):
        path = REPO / "eval-archive/convo-sim/full-2026-09-24-spec051.jsonl"
        if not path.is_file():
            self.skipTest("archive jsonl missing")
        rows = judge.load_jsonl(path)
        turns = judge.extract_scorable_turns(rows)
        self.assertGreater(len(turns), 500)
        sample = turns[0]
        self.assertIn("turn_id", sample)
        self.assertTrue(judge.study_persona_ok(sample["persona_id"]))

    def test_score_cli_dry_run(self):
        path = REPO / "eval-archive/convo-sim/full-2026-09-24-spec051.jsonl"
        if not path.is_file():
            self.skipTest("archive jsonl missing")
        proc = subprocess.run(
            [
                sys.executable,
                str(JUDGE_PATH),
                "score",
                str(path),
                "--limit",
                "2",
                "--dry-run",
            ],
            capture_output=True,
            text=True,
            check=False,
            cwd=REPO,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("turn_id", proc.stdout)
        self.assertIn("q1", proc.stdout)

    def test_calibration_csv_has_100_rows(self):
        csv_path = REPO / "calibration/conversation-quality-100.csv"
        if not csv_path.is_file():
            self.skipTest("calibration csv missing")
        with csv_path.open(newline="") as fh:
            rows = list(csv.DictReader(fh))
        self.assertEqual(len(rows), 100)
        self.assertTrue(all(r.get("turn_id") for r in rows))

    def test_calibrate_dry_run_without_human_labels(self):
        csv_path = REPO / "calibration/conversation-quality-100.csv"
        if not csv_path.is_file():
            self.skipTest("calibration csv missing")
        proc = subprocess.run(
            [
                sys.executable,
                str(JUDGE_PATH),
                "calibrate",
                str(csv_path),
                "--dry-run",
            ],
            capture_output=True,
            text=True,
            check=False,
            cwd=REPO,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Human raters have not filled", proc.stderr)


if __name__ == "__main__":
    unittest.main()
