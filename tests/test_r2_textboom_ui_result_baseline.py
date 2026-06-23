from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "r2-textboom-ui-result-baseline.py"


def load_module():
    spec = importlib.util.spec_from_file_location("r2_textboom_ui_result_baseline", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class TextBoomUiResultBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_parse_bounds_and_normalize_token(self):
        self.assertEqual(self.mod.parse_bounds("[1,2][30,40]"), self.mod.Bounds(1, 2, 30, 40))
        self.assertEqual(self.mod.normalize_token("英文分号"), ";")
        self.assertIsNone(self.mod.parse_bounds("bad"))

    def test_extracts_ocr_tokens_without_titlebar_actions(self):
        xml = """<?xml version="1.0" encoding="UTF-8"?>
<hierarchy>
  <node resource-id="com.smartisanos.textboom:id/titlebar_center_text" text="大爆炸" bounds="[0,0][100,20]" />
  <node resource-id="com.smartisanos.textboom:id/right_view1" content-desc="保存" bounds="[90,0][100,20]" />
  <node resource-id="" content-desc="Runtime" bounds="[10,30][80,50]" />
  <node resource-id="" content-desc="英文分号" bounds="[82,30][90,50]" />
  <node resource-id="" content-desc="Android" bounds="[10,60][90,80]" />
  <node resource-id="com.smartisanos.textboom:id/total_size" text="共 12 字" bounds="[0,20][100,30]" />
</hierarchy>
"""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            xml_path = root / "result.xml"
            out = root / "baseline.json"
            xml_path.write_text(xml, encoding="utf-8")

            payload = self.mod.build_baseline(xml_path, "unit", image_size=[100, 80])
            rc = self.mod.main([str(xml_path), "--out", str(out), "--sample-id", "unit"])

            self.assertEqual(rc, 0)
            self.assertEqual(payload["sample"]["title"], "大爆炸")
            self.assertEqual(payload["sample"]["total_size_text"], "共 12 字")
            self.assertEqual([token["text"] for token in payload["sample"]["tokens"]], ["Runtime", "英文分号", "Android"])
            self.assertEqual(payload["sample"]["normalized_text"], "Runtime; Android")
            self.assertEqual(json.loads(out.read_text(encoding="utf-8"))["sample"]["id"], "unit")


if __name__ == "__main__":
    unittest.main()
