from __future__ import annotations

import importlib.util
import io
import json
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "r2-textboom-ppocr-corpus-template.py"


def load_module():
    spec = importlib.util.spec_from_file_location("r2_textboom_ppocr_corpus_template", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def png_header(width: int, height: int) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", width, height)


def jpeg_header(width: int, height: int) -> bytes:
    return b"\xff\xd8\xff\xc0" + struct.pack(">H", 17) + b"\x08" + struct.pack(">HH", height, width) + (b"\x00" * 10)


class TextBoomPpocrCorpusTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_reads_png_and_jpeg_sizes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            png = root / "screen.png"
            jpg = root / "camera.jpg"
            png.write_bytes(png_header(1080, 2340))
            jpg.write_bytes(jpeg_header(720, 1280))

            self.assertEqual(self.mod.read_png_size(png), (1080, 2340))
            self.assertEqual(self.mod.read_jpeg_size(jpg), (720, 1280))

    def test_builds_template_and_preserves_expected_labels(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            image = root / "browser page.png"
            image.write_bytes(png_header(200, 100))
            preserved = {
                "browser-page": [
                    {"text": "Browser", "rect": {"left": 1, "top": 2, "right": 30, "bottom": 12}}
                ]
            }

            payload = self.mod.build_corpus([image], "unit", "fixture", preserved)

            self.assertEqual(payload["samples"][0]["id"], "browser-page")
            self.assertEqual(payload["samples"][0]["image_size"], [200, 100])
            self.assertEqual(payload["samples"][0]["expected"], preserved["browser-page"])

    def test_main_writes_corpus_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            image = root / "one.png"
            out = root / "corpus.json"
            image.write_bytes(png_header(10, 20))

            with redirect_stdout(io.StringIO()):
                rc = self.mod.main([str(image), "--out", str(out), "--label", "unit"])

            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(rc, 0)
            self.assertEqual(payload["label"], "unit")
            self.assertEqual(payload["samples"][0]["image_size"], [10, 20])


if __name__ == "__main__":
    unittest.main()
