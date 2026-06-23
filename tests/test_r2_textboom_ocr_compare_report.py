from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "r2-textboom-ocr-compare-report.py"


def load_module():
    spec = importlib.util.spec_from_file_location("r2_textboom_ocr_compare_report", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TextBoomOcrCompareReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_text_metrics_collapses_whitespace(self):
        metrics = self.mod.text_metrics("Runtime WebView", "Runtime\nWebView")

        self.assertEqual(metrics.edit_distance, 0)
        self.assertEqual(metrics.char_error_rate, 0.0)

    def test_prefix_cer_ignores_extra_predicted_lines(self):
        cer = self.mod.prefix_char_error_rate("Runtime WebView", "Runtime\nWebView\nExtra line")

        self.assertEqual(cer, 0.0)

    def test_partial_summary_when_csocr_raw_is_blocked(self):
        ppocr = {
            "imageboom": {
                "id": "imageboom",
                "status": "OK",
                "line_count": 2,
                "latency_ms": 940,
                "peak_pss_kb": 77247,
                "text": "Runtime\nWebView",
            }
        }
        csocr = {
            "imageboom": {
                "id": "imageboom",
                "status": "CSOCR_RESULT_CODE_1",
                "response_code": 4003,
                "raw_response_size": 0,
                "line_count": 0,
                "latency_ms": 813,
                "camscanner_total_pss_kb": 223771,
                "text": "",
            }
        }
        ui = {
            "imageboom": {
                "id": "imageboom",
                "token_count": 2,
                "total_size_text": "共 223 字",
                "text": "Runtime WebView",
            }
        }

        rows = self.mod.build_rows(ppocr, csocr, ui)
        summary = self.mod.summarize(rows)

        self.assertEqual(summary["ppocr_ok_count"], 1)
        self.assertEqual(summary["csocr_raw_ok_count"], 0)
        self.assertEqual(summary["csocr_raw_blocked_count"], 1)
        self.assertEqual(rows[0]["ui_vs_ppocr_cer"], 0.0)


if __name__ == "__main__":
    unittest.main()
