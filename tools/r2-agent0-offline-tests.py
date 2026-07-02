#!/usr/bin/env python3
"""Offline contract checks for Smartisax Agent v0.agent0-vision-loop."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "apps" / "SmartisaxShell" / "src" / "com" / "smartisax" / "browser"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"error: {message}")


def extract_json_object(text: str) -> str:
    start = text.find("{")
    require(start >= 0, "missing json object")
    in_string = False
    escaped = False
    depth = 0
    for index, char in enumerate(text[start:], start=start):
        if escaped:
            escaped = False
            continue
        if char == "\\" and in_string:
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]
    raise SystemExit("error: unclosed json object")


def validate_action(raw: str) -> dict:
    action = json.loads(extract_json_object(raw))
    if isinstance(action.get("action"), dict):
        action = action["action"]
    action_type = action.get("type") or action.get("action")
    aliases = {"onestep": "one_step", "sidebar": "one_step", "one_step_mode": "one_step"}
    action_type = aliases.get(str(action_type), action_type)
    require(action_type in {"click_node", "tap", "swipe", "key", "wait", "one_step", "finish", "ask_user"}, "action allowlist")
    for key in ("x", "y", "x1", "y1", "x2", "y2"):
        if key in action:
            require(0 <= int(action[key]) <= 10000, f"{key} normalized range")
    if action_type == "key":
        require(action.get("key") in {"BACK", "HOME"}, "key allowlist")
    if action_type == "one_step":
        operation = action.get("operation") or action.get("mode") or action.get("state")
        operation = {"open": "enter", "show": "enter", "right": "enter",
                     "close": "exit", "hide": "exit", "off": "exit"}.get(operation, operation)
        require(operation in {"enter", "exit"}, "one_step operation allowlist")
    if action_type == "click_node":
        require(str(action.get("nodeId", "")).startswith("n"), "click_node node id")
    return action


def main() -> None:
    runtime = (SRC / "SmartisaxAgentRuntime.java").read_text(encoding="utf-8")
    config = (SRC / "SmartisaxAgentConfig.java").read_text(encoding="utf-8")
    providers = (SRC / "SmartisaxAgentProviders.java").read_text(encoding="utf-8")
    capture = (SRC / "SmartisaxScreenCapture.java").read_text(encoding="utf-8")
    one_step = (SRC / "SmartisaxOneStepController.java").read_text(encoding="utf-8")
    accessibility = (SRC / "SmartisaxAccessibilityService.java").read_text(encoding="utf-8")
    input_controller = (SRC / "SmartisaxInputController.java").read_text(encoding="utf-8")
    shell_ts = (ROOT / "apps" / "SmartisaxShell" / "assets-src" / "shell.ts").read_text(encoding="utf-8")

    require("static final int MAX_STEPS = 5" in runtime, "max step cap")
    require("uploadsScreenOnlyAfterManualStart" in runtime, "manual screenshot policy marker")
    require("storesScreenshots" in runtime and "false" in runtime, "no screenshot persistence marker")
    require("POST_ACTION_OBSERVE_DELAY_MS" in runtime, "post-action observation delay")
    require("finish_requires_verified_screen_change" in runtime, "finish gate after UI action")
    require("finishTargetVerification" in runtime, "target-aware finish policy marker")
    require("finish_target_verified" in runtime, "target-aware finish accepted reason")
    require("settings_target_visible" in runtime, "Settings target finish marker")
    require("foregroundPackageMatched" in runtime, "foreground target verification marker")
    require("accessibilityWindowMatched" in runtime, "accessibility window target marker")
    require("accessibilityPackageNodeMatched" in runtime, "accessibility package target marker")
    require("coordinate_edge_guard" in runtime, "edge coordinate guard")
    require("screen_freshness_guard" in runtime, "pre-action screen freshness guard")
    require("screen_changed_before_action" in runtime, "pre-action reobserve reason")
    require("skipped_reobserve_screen_changed" in runtime, "screen-changed reobserve status")
    require("coordinate_guard_after_screen_change_reobserve" in runtime, "coordinate guard reobserve reason")
    require("skipped_coordinate_guard_reobserve" in runtime, "coordinate guard reobserve status")
    require("MAX_REOBSERVE_SKIPS = 2" in runtime, "bounded reobserve skips")
    require("visualDistance" in runtime and "changedCells" in runtime, "material screen-change diff")
    require("repeated_tap_no_screen_change" in runtime, "repeated tap no-change pause")
    require("repeated_key_no_screen_change" in runtime, "repeated key no-change pause")
    require("repeated_node_no_screen_change" in runtime, "repeated node no-change pause")
    require("postActionCheck" in runtime, "post-action check status")
    require('"one_step"' in runtime and "SmartisaxOneStepController.handle" in runtime, "one_step runtime action")
    require('"click_node"' in runtime and "SmartisaxAccessibilityService.clickNode" in runtime, "click_node runtime action")
    require("accessibilityTree" in runtime and "accessibilityTree" in providers, "accessibility tree step prompt")
    require("android.accessibilityservice.AccessibilityService" in (ROOT / "apps" / "SmartisaxShell" / "AndroidManifest.xml").read_text(encoding="utf-8"), "accessibility service manifest")
    require("canRetrieveWindowContent" in (ROOT / "apps" / "SmartisaxShell" / "res" / "xml" / "smartisax_accessibility_service.xml").read_text(encoding="utf-8"), "accessibility service config")
    require("AccessibilityNodeInfo.ACTION_CLICK" in accessibility, "accessibility click execution")
    require("ENABLED_ACCESSIBILITY_SERVICES" in accessibility, "accessibility auto-enable attempt")
    require("MAX_NODES = 120" in accessibility, "accessibility compact tree bound")
    require("FLAG_RETRIEVE_INTERACTIVE_WINDOWS" in accessibility, "interactive window retrieval flag")
    require("getWindows()" in accessibility, "accessibility getWindows collection")
    require("android_accessibility_active_plus_windows" in accessibility, "active plus windows tree source marker")
    require("windowCount" in accessibility and "rootCount" in accessibility, "accessibility window/root summary")
    require("IWINDOW_MANAGER_REQUEST_ZOOM = 2001" in one_step, "One Step WindowManager transact code")
    require("PROGRAMMATIC_WAIT_MS" in one_step and "programmaticRetry" in one_step, "One Step bind wait retry")
    require("one_step_visibility_recovery_home_exit_enter" in one_step, "One Step visibility recovery marker")
    require("RECOVERY_HOME_SETTLE_MS" in one_step and "RECOVERY_ENTER_WAIT_MS" in one_step, "One Step recovery wait bounds")
    require("one_step_state_guard" in runtime, "One Step state guard")
    require("one_step_enter_not_visible" in one_step, "One Step enter failure reason")
    require("side_bar_zoom_type" in one_step and "sidebar_switch_status" in one_step, "One Step state feedback")
    require("right_edge_swipe" in one_step and "back_key" in one_step, "One Step gesture fallback")
    require("mimo-v2.5" in config, "MiMo V2.5 model default")
    require("deepseek-v4-flash" in config, "DeepSeek model default")
    require("https://api.xiaomimimo.com/v1/chat/completions" in config, "MiMo API URL")
    require("https://api.deepseek.com" in config, "DeepSeek API base URL")
    require("image/jpeg" in capture and "Base64.NO_WRAP" in capture, "JPEG base64 observation")
    require("MessageDigest.getInstance(\"SHA-256\")" in capture, "observation fingerprint")
    require("visualSignature" in capture and "materiallyDifferent" in capture, "visual signature material-change detector")
    require("KEYCODE_BACK" in input_controller and "KEYCODE_HOME" in input_controller, "key injection allowlist")
    require("Never request shell, root, adb, fastboot" in providers, "provider safety prompt")
    require("prefer click_node" in providers, "provider accessibility node preference")
    require("Use one_step with operation enter" in providers, "provider one_step enter prompt")
    require("systemState.oneStep.visible" in providers, "provider one_step state prompt")
    require("foreground.isSmartisaxShell" in providers, "provider Smartisax Shell foreground prompt")
    require("foreground/accessibility state already confirms the target app is visible" in providers, "provider target-aware finish prompt")
    require('"isSettings"' in one_step, "foreground Settings state marker")
    require("gear-shaped Settings icon" in providers, "provider Settings via One Step prompt")
    require("never return HOME again" in providers, "provider repeated HOME no-change prompt")
    require("postActionCheck.screenChanged=true" in providers, "provider finish-after-observe prompt")
    require("networkPreflight" in providers, "provider network preflight")
    require("provider_network_dns_unavailable" in providers, "provider DNS failure marker")
    require("provider_request_timeout" in providers, "provider timeout marker")
    require("setConnectTimeout(6000)" in providers, "provider connect timeout bound")
    require("setReadTimeout(20000)" in providers, "provider read timeout bound")
    require("paused_provider_error" in runtime, "provider error transcript pause")
    require("provider_network_guard" in runtime, "provider network guard marker")
    require("providerRequestGuard" in runtime, "provider request guard policy marker")
    require("formatResult" in shell_ts and "post-check:" in shell_ts, "visible Agent step result transcript")
    require("one_step(" in shell_ts and "one-step:" in shell_ts, "visible One Step transcript")
    require("click_node(" in shell_ts and "A11y" in shell_ts, "visible accessibility transcript/status")
    require("roots /" in shell_ts and "windows" in shell_ts, "visible accessibility window/root status")

    validate_action('```json\n{"type":"tap","x":5000,"y":2500,"confidence":0.7}\n```')
    validate_action('{"action":{"type":"swipe","x1":5000,"y1":8000,"x2":5000,"y2":2000,"durationMs":450}}')
    validate_action('{"type":"key","key":"BACK","confidence":0.9}')
    validate_action('{"type":"one_step","operation":"enter","confidence":0.8}')
    validate_action('{"type":"sidebar","mode":"close","confidence":0.8}')
    validate_action('{"type":"click_node","nodeId":"n1234567890","confidence":0.9}')
    try:
        validate_action('{"type":"shell","command":"rm -rf /"}')
    except SystemExit:
        pass
    else:
        raise SystemExit("error: shell action was not rejected")

    print("PASS_AGENT0_OFFLINE_TESTS")


if __name__ == "__main__":
    main()
