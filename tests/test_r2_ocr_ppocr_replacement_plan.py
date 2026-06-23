from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "r2-ocr-ppocr-replacement-plan.py"


def load_module():
    spec = importlib.util.spec_from_file_location("r2_ocr_ppocr_replacement_plan", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class OcrPpocrReplacementPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_parse_ranges_handles_singletons_and_ranges(self):
        self.assertEqual(self.mod.parse_ranges("1-3, 5, 8-9"), [(1, 3), (5, 5), (8, 9)])

    def test_token_hits_preserves_requested_order(self):
        hits = self.mod.token_hits("CsOcr calls CSOpenAPI, not LocalPpOcrApi", ("LocalPpOcrApi", "CsOcr", "missing"))
        self.assertEqual(hits, ("LocalPpOcrApi", "CsOcr"))

    def test_current_state_and_status_for_present_legacy(self):
        summary = {"exists": True, "tokens_present": ["CsOcr"]}
        self.assertEqual(self.mod.current_state_from_hits(summary), "legacy_present_in_current_baseline")
        self.assertEqual(self.mod.deletion_gate_status(summary), "TARGET_PENDING_DELETE")

    def test_current_state_and_status_for_absent_legacy(self):
        summary = {"exists": True, "tokens_present": []}
        self.assertEqual(self.mod.current_state_from_hits(summary), "legacy_absent_in_current_baseline")
        self.assertEqual(self.mod.deletion_gate_status(summary), "TARGET_ALREADY_ABSENT")

    def test_missing_evidence_warns(self):
        summary = {"exists": False, "tokens_present": []}
        self.assertEqual(self.mod.current_state_from_hits(summary), "evidence_missing")
        self.assertEqual(self.mod.deletion_gate_status(summary), "WARN_EVIDENCE_MISSING")

    def test_overall_result_warns_only_on_missing_evidence(self):
        rows = [{"status": "TARGET_PENDING_DELETE"}, {"status": "TARGET_ALREADY_ABSENT"}]
        self.assertEqual(self.mod.overall_result(rows), "OCR_PPOCR_REPLACEMENT_PLAN_OFFLINE_PASS")
        rows.append({"status": "WARN_EVIDENCE_MISSING"})
        self.assertEqual(self.mod.overall_result(rows), "OCR_PPOCR_REPLACEMENT_PLAN_OFFLINE_WARN")

    def test_summarize_hits_reports_matching_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a.smali").write_text("new-instance Lcom/smartisanos/textboom/ocr/CsOcr;", encoding="utf-8")
            (root / "b.txt").write_text("CsOcr in ignored suffix", encoding="utf-8")
            summary = self.mod.summarize_hits(root, ("*.smali",), ("CsOcr", "CSOpenAPI"))
        self.assertTrue(summary["exists"])
        self.assertEqual(summary["scanned_files"], 1)
        self.assertEqual(summary["tokens_present"], ["CsOcr"])
        self.assertEqual(summary["tokens_missing"], ["CSOpenAPI"])


if __name__ == "__main__":
    unittest.main()
