from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "r2-textboom-ppocr-benchmark.py"


def load_module():
    spec = importlib.util.spec_from_file_location("r2_textboom_ppocr_benchmark", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TextBoomPpocrBenchmarkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_char_error_rate_collapses_whitespace(self):
        self.assertEqual(self.mod.char_error_rate("hello world", "hello\nworld"), 0.0)
        self.assertAlmostEqual(self.mod.char_error_rate("hello", "hallo"), 0.2)

    def test_rect_iou_scores_overlap(self):
        left = {"left": 0, "top": 0, "right": 10, "bottom": 10}
        right = {"left": 5, "top": 0, "right": 15, "bottom": 10}

        self.assertAlmostEqual(self.mod.rect_iou(left, right), 1 / 3)

    def test_evaluates_saved_ppocr_predictions(self):
        corpus = {
            "samples": [
                {
                    "id": "browser-shell",
                    "image_size": [200, 120],
                    "expected": [
                        {"text": "Browser shell", "rect": {"left": 10, "top": 10, "right": 110, "bottom": 30}},
                        {"text": "WebGPU available", "rect": {"left": 10, "top": 50, "right": 150, "bottom": 70}},
                    ],
                }
            ]
        }
        predictions = {
            "engine": "ppocrv6-tiny",
            "model": "sample",
            "samples": [
                {
                    "id": "browser-shell",
                    "latency_ms": 88.0,
                    "peak_pss_kb": 123456,
                    "ppocr": [
                        [[[10, 10], [110, 10], [110, 30], [10, 30]], ("Browser shell", 0.99)],
                        [[[10, 50], [150, 50], [150, 70], [10, 70]], ("WebGPU available", 0.98)],
                    ],
                }
            ],
        }

        payload = self.mod.evaluate_corpus(corpus, predictions, self.mod.BenchmarkThresholds(), "unit")

        self.assertEqual(payload["result"], "TEXTBOOM_PPOCR_BENCHMARK_PASS")
        self.assertEqual(payload["summary"]["line_recall"], 1.0)
        self.assertEqual(payload["summary"]["p95_latency_ms"], 88.0)
        self.assertEqual(payload["summary"]["peak_pss_kb"], 123456)

    def test_fails_when_prediction_misses_expected_text(self):
        corpus = {
            "samples": [
                {
                    "id": "miss",
                    "expected": [{"text": "expected", "rect": [0, 0, 20, 10]}],
                }
            ]
        }
        predictions = {
            "samples": [
                {
                    "id": "miss",
                    "ppocr": [[[[0, 0], [20, 0], [20, 10], [0, 10]], ("different", 0.95)]],
                }
            ]
        }

        payload = self.mod.evaluate_corpus(corpus, predictions, self.mod.BenchmarkThresholds(), "unit")

        self.assertEqual(payload["result"], "TEXTBOOM_PPOCR_BENCHMARK_FAIL")
        self.assertEqual(payload["samples"][0]["matched_count"], 0)

    def test_write_report_bundle(self):
        corpus = {"samples": [{"id": "ok", "expected": [{"text": "ok", "rect": [0, 0, 10, 10]}]}]}
        predictions = {"samples": [{"id": "ok", "ppocr": [[[[0, 0], [10, 0], [10, 10], [0, 10]], ("ok", 0.9)]]}]}
        payload = self.mod.evaluate_corpus(corpus, predictions, self.mod.BenchmarkThresholds(), "unit")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.mod.write_json(root / "report.json", payload)
            self.mod.write_markdown(root / "report.md", payload)
            self.mod.write_tsv(root / "report.tsv", payload)
            self.assertIn("TEXTBOOM_PPOCR_BENCHMARK_PASS", (root / "report.md").read_text(encoding="utf-8"))
            self.assertIn("id\tresult", (root / "report.tsv").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
