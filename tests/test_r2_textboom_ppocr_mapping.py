from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "r2-textboom-ppocr-mapping.py"


def load_module():
    spec = importlib.util.spec_from_file_location("r2_textboom_ppocr_mapping", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TextBoomPpocrMappingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_maps_classic_paddleocr_pair_to_textboom_line(self):
        result = [
            [
                [[10, 20], [80, 18], [82, 42], [9, 45]],
                ("  Smartisan\rOS  ", 0.97),
            ]
        ]

        lines = self.mod.map_ppocr_to_textboom_json(result, image_size=(100, 80))

        self.assertEqual(lines, [{"text": "SmartisanOS", "rect": {"left": 9.0, "top": 18.0, "right": 82.0, "bottom": 45.0}, "score": 0.97}])

    def test_maps_to_ocrinfo_field_names(self):
        result = [
            [
                [[10, 20], [80, 18], [82, 42], [9, 45]],
                ("  Smartisan\rOS  ", 0.97),
            ]
        ]

        lines = self.mod.map_ppocr_to_ocrinfo_json(result, image_size=(100, 80))

        self.assertEqual(lines, [{"mText": "SmartisanOS", "mRect": {"left": 9.0, "top": 18.0, "right": 82.0, "bottom": 45.0}, "score": 0.97}])

    def test_maps_batched_paddleocr_shape_in_reading_order(self):
        result = [
            [
                [[[40, 50], [80, 50], [80, 70], [40, 70]], ("second", 0.93)],
                [[[5, 10], [70, 10], [70, 25], [5, 25]], ("first", 0.91)],
            ]
        ]

        lines = self.mod.map_ppocr_to_textboom_json(result)

        self.assertEqual([line["text"] for line in lines], ["first", "second"])

    def test_maps_current_dict_result_shape(self):
        result = {
            "rec_texts": ["一小步", "Big Bang"],
            "rec_scores": [0.88, 0.95],
            "dt_polys": [
                [[2, 3], [30, 3], [30, 20], [2, 20]],
                [[1, 30], [50, 30], [50, 45], [1, 45]],
            ],
        }

        lines = self.mod.map_ppocr_to_textboom_json(result)

        self.assertEqual([line["text"] for line in lines], ["一小步", "Big Bang"])
        self.assertEqual(lines[1]["score"], 0.95)

    def test_clamps_boxes_to_bitmap_bounds(self):
        result = [[[-10, -5, 120, -4, 121, 40, -9, 41], ("edge", 0.9)]]

        lines = self.mod.map_ppocr_to_textboom_json(result, image_size=(100, 30))

        self.assertEqual(lines[0]["rect"], {"left": 0.0, "top": 0.0, "right": 100.0, "bottom": 30.0})

    def test_filters_empty_text_and_low_confidence(self):
        result = [
            [[[0, 0], [10, 0], [10, 10], [0, 10]], ("", 0.99)],
            [[[0, 20], [10, 20], [10, 30], [0, 30]], ("weak", 0.30)],
            [[[0, 40], [10, 40], [10, 50], [0, 50]], ("keep", 0.80)],
        ]

        lines = self.mod.map_ppocr_to_textboom_json(result, min_score=0.5)

        self.assertEqual([line["text"] for line in lines], ["keep"])

    def test_keeps_lines_without_score(self):
        result = [{"text": "no score", "points": [[1, 2], [5, 2], [5, 6], [1, 6]]}]

        lines = self.mod.map_ppocr_to_textboom_json(result, min_score=0.9)

        self.assertEqual(lines[0]["text"], "no score")
        self.assertIsNone(lines[0]["score"])


if __name__ == "__main__":
    unittest.main()
