#!/usr/bin/env python3
"""
Smartisax Fake OTA Server
Mimics ota2.smartisan.com/update.php for testing Smartisan Updater behavior.
"""

import argparse
import hashlib
import json
import logging
import os
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler

logging.basicConfig(
    level=logging.DEBUG,
    format="[%(asctime)s] %(levelname)s: %(message)s",
)
log = logging.getLogger("ota-server")

PORT = 8080
HOST = "0.0.0.0"

PUBLIC_HOST = "127.0.0.1"
MODE = "no-update"
PACKAGE_NAME = "Smartisax_1.0.0_darwin_update.zip"
PACKAGE_PATH = None


def _default_lan_ip():
    """Best-effort LAN IP for printing adb commands; adb reverse should use 127.0.0.1."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def _package_path():
    if PACKAGE_PATH:
        return PACKAGE_PATH
    return os.path.join(os.path.dirname(__file__), "packages", PACKAGE_NAME)


def _package_md5():
    digest = hashlib.md5()
    with open(_package_path(), "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class OTAResponse:
    """Builds the JSON response matching the Smartisan OTA protocol."""

    @staticmethod
    def no_update():
        return {"result": []}

    @staticmethod
    def fake_update():
        """Return a fake update for testing."""
        filepath = _package_path()
        size_mb = os.path.getsize(filepath) / 1024 / 1024
        return {
            "result": [
                {
                    "filename": PACKAGE_NAME,
                    "timestamp": "1718534400",
                    "url": f"http://{PUBLIC_HOST}:{PORT}/package/{PACKAGE_NAME}",
                    "md5sum": _package_md5(),
                    "type": "stable",
                    # SmartisanUpdater treats this OTA protocol field as MB in
                    # its UI and storage preflight, not as raw bytes.
                    "size": f"{size_mb:.1f}",
                    "changes": "这是一个测试更新包",
                    "changesEx": "",
                    "changelogUrl": "",
                    "newfunction": "",
                    "other": "3",
                }
            ]
        }


class RequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        log.info(f"{self.client_address[0]} - {format % args}")

    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, filepath):
        if not os.path.exists(filepath):
            log.warning(f"File not found: {filepath}")
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Length", str(os.path.getsize(filepath)))
        self.end_headers()
        served = 0
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                self.wfile.write(chunk)
                served += len(chunk)
        log.info(f"Served file: {filepath} ({served} bytes)")

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length).decode("utf-8", errors="replace")
        log.info(f"POST {self.path}")
        log.info(f"Request body: {body}")

        try:
            req = json.loads(body)
            method = req.get("method", "")
            params = req.get("params", {})
            log.info(f"Method: {method}, Device: {params.get('device')}, "
                     f"Version: {params.get('version')}, "
                     f"BuildTime: {params.get('buildtime')}")
        except json.JSONDecodeError as e:
            log.warning(f"Invalid JSON: {e}")
            self._send_json({"error": "invalid json"}, 400)
            return

        if self.path == "/update.php" or self.path.endswith("/update.php"):
            if MODE == "fake-update":
                self._send_json(OTAResponse.fake_update())
            else:
                self._send_json(OTAResponse.no_update())
        else:
            self._send_json({"error": "not found"}, 404)

    def do_GET(self):
        log.info(f"GET {self.path}")
        if self.path.startswith("/package/"):
            filepath = os.path.join(
                os.path.dirname(__file__),
                "packages",
                os.path.basename(self.path),
            )
            self._send_file(filepath)
        else:
            self._send_json({"error": "not found"}, 404)


def main():
    global PORT, HOST, PUBLIC_HOST, MODE, PACKAGE_NAME, PACKAGE_PATH

    parser = argparse.ArgumentParser(description="Safe Smartisan OTA mock server")
    parser.add_argument("--host", default=HOST, help="listen host, default: 0.0.0.0")
    parser.add_argument("--port", type=int, default=PORT, help="listen port, default: 8080")
    parser.add_argument(
        "--public-host",
        default="127.0.0.1",
        help="host written into fake package URLs; use 127.0.0.1 with adb reverse",
    )
    parser.add_argument(
        "--mode",
        choices=("no-update", "fake-update"),
        default="no-update",
        help="default is safe and returns {result: []}",
    )
    parser.add_argument(
        "--package-path",
        help="absolute path to the update zip returned in fake-update mode",
    )
    parser.add_argument(
        "--package-name",
        help="filename to advertise to the updater; defaults to the package path basename",
    )
    args = parser.parse_args()

    HOST = args.host
    PORT = args.port
    PUBLIC_HOST = args.public_host
    MODE = args.mode
    if args.package_path:
        PACKAGE_PATH = os.path.abspath(args.package_path)
        PACKAGE_NAME = args.package_name or os.path.basename(PACKAGE_PATH)
    elif args.package_name:
        PACKAGE_NAME = args.package_name

    # Ensure packages directory exists
    os.makedirs(os.path.join(os.path.dirname(__file__), "packages"), exist_ok=True)

    server = HTTPServer((HOST, PORT), RequestHandler)
    log.info(f"Fake OTA server starting on http://{HOST}:{PORT}")
    log.info(f"Mode: {MODE}")
    log.info(f"LAN IP guess: {_default_lan_ip()}")
    log.info(f"Public host in package URLs: {PUBLIC_HOST}")
    log.info("")
    log.info("Safe test with adb reverse:")
    log.info(f"  adb reverse tcp:{PORT} tcp:{PORT}")
    log.info(f"  adb shell am start -n com.smartisanos.updater/.UpdatesCheck"
             f" --es url http://127.0.0.1:{PORT}/update.php")
    log.info("")
    log.info("LAN test without adb reverse:")
    log.info(f"  adb shell am start -n com.smartisanos.updater/.UpdatesCheck"
             f" --es url http://{_default_lan_ip()}:{PORT}/update.php")
    log.info("")
    log.info("Monitor phone log:")
    log.info("  adb logcat -s UpdateCheckService")
    log.info("")
    log.info("Press Ctrl+C to stop.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Shutting down...")
        server.server_close()


if __name__ == "__main__":
    main()
