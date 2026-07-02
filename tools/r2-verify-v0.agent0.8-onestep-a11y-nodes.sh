#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUGFS="${DEBUGFS:-/opt/homebrew/opt/e2fsprogs/sbin/debugfs}"
JAVA_BIN="${JAVA_BIN:-/opt/homebrew/opt/openjdk/bin/java}"
APKTOOL="${APKTOOL:-${ROOT_DIR}/third_party/apktool/apktool_3.0.2.jar}"
SIGCHECK="${SIGCHECK:-${ROOT_DIR}/tools/r2-apk-signature-boundary-check.sh}"

export VARIANT="v0.agent0.8-onestep-a11y-nodes"
export EXPECTED_VERSION_CODE="59"
export EXPECTED_VERSION_NAME="0.7.8"
export EXPECTED_NATIVE_SYSTEM_WEBRTC_LIBS="1"
export EXPECTED_PORTAL_VARIANT_MARKER="v0.agent0.8-onestep-a11y-nodes"
export EXPECTED_SOFTWARE_BITMAP_FRAME_PUMP="0"
export EXPECTED_BITMAP_COPY_FRAME_PUMP="1"
export EXPECTED_WEBRTC_SESSION_CONTROL="1"
export EXPECTED_WEBRTC_INPUT_CHANNEL="1"
export EXPECTED_WEBRTC_TOUCH_OVERLAY="1"
export EXPECTED_WEBRTC_QUALITY_TUNE="1"
export EXPECTED_WEBRTC_QUALITY_REASON_MARKER="portal6g_rvfc_media_tail"
export EXPECTED_WEBRTC_BITRATE_TUNE="1"
export EXPECTED_WEBRTC_DEFAULT_UI="1"
export EXPECTED_WEBRTC_RUNTIME_TUNING="1"
export EXPECTED_WEBRTC_RUNTIME_REASON_MARKER="portal6g_rvfc_media_tail"
export EXPECTED_WEBRTC_RUNTIME_MAX_FPS="90"
export EXPECTED_WEBRTC_CAPTURE_PROBE="1"
export EXPECTED_MANAGE_MEDIA_PROJECTION="1"
export EXPECTED_PROJECTION_PERMISSION_POLICY="1"
export EXPECTED_PROJECTION_BINDER_TRANSACT="1"
export EXPECTED_WEBRTC_FRAME_CONTINUITY_REPAIR="1"
export EXPECTED_WEBRTC_FRAME_TIMESTAMP_RETAIN="1"
export EXPECTED_WEBRTC_TOUCH_PHOTON_MARKER="1"
export EXPECTED_WEBRTC_MOVE_STREAM_INPUT="1"
export EXPECTED_WEBRTC_LATENCY_FOLLOW_RATE="1"
export EXPECTED_WEBRTC_DUAL_MOVE_CHANNEL="1"
export EXPECTED_WEBRTC_LATEST_FRAME_QUEUE="1"
export EXPECTED_WEBRTC_INPUT_FRAME_BOOST="1"
export EXPECTED_WEBRTC_DUAL_PHASE_INPUT_BOOST="1"
export EXPECTED_WEBRTC_MARKER_BURST_BOOST="1"
export EXPECTED_WEBRTC_MARKER_BURST_RESCHEDULE="1"
export EXPECTED_WEBRTC_PRESENTATION_CADENCE="1"
export EXPECTED_WEBRTC_QUIET_PRESENTATION="1"
export EXPECTED_WEBRTC_PRESENTER_MODE="1"
export EXPECTED_WEBRTC_PRESENTATION_TRANSPORT_PACING="1"
export EXPECTED_WEBRTC_VIDEO_PRIMARY_ROI_PROBE="1"
export EXPECTED_WEBRTC_MARKER_DRAW_SYNC="1"
export EXPECTED_WEBRTC_DRAW_URGENT_BOOST="1"
export EXPECTED_WEBRTC_BOOST_TOKEN_RETAIN="1"
export EXPECTED_WEBRTC_EVENT_TIME_INPUT="1"
export EXPECTED_WEBRTC_INPUT_PRIORITY_FRAME="1"
export EXPECTED_WEBRTC_VISIBLE_SCREENBOX="1"
export EXPECTED_WEBRTC_DISPLAY_WAKE_GUARD="1"
export EXPECTED_WEBRTC_ENCODER_TRANSPORT_BURST="1"
export EXPECTED_WEBRTC_ENCODER_TRANSPORT_REASON_MARKER="portal6g_rvfc_media_tail"
export EXPECTED_WEBRTC_PRESENTATION_TAIL_CADENCE="1"
export EXPECTED_WEBRTC_MEDIA_CALLBACK_TAIL_REPAIR="1"
export EXPECTED_SERVICES_JAR_SHA256="3c2775dca94a7893901d89e095d2ac1932687e5b92795dc8b4dcb5d72b67f909"
export OFFLINE_RESULT_NAME="PASS_OFFLINE_IMAGE_V0AGENT08_ONESTEP_A11Y_NODES"
export READ_ONLY_RESULT_NAME="PASS_READ_ONLY_V0AGENT08_ONESTEP_A11Y_NODES"

SYSTEM_IMG="${ROOT_DIR}/hard-rom/build/system-otatrust-${VARIANT}.img"
EXPECTED_SYSTEM_SHA256="59513487018c33383f24c9f163238192f82a596c65d3b89db6ed8a93b0c5ffdc"
EXPECTED_SIDEBAR_SHA256="2ceb4dca8d6e9b2c709cf19064b064d3376e24a12190592ca3cf969cdf6206af"
SIDEBAR_IMAGE_PATH="/system/priv-app/Sidebar/Sidebar.apk"
RAW="${ROOT_DIR}/reverse/smartisan-8.5.3-rom-static/raw"
FW_ANDROID="${RAW}/system/system/framework/framework-res.apk"
FW_SMARTISAN="${RAW}/system/system/framework/framework-smartisanos-res/framework-smartisanos-res.apk"

latest_offline_report() {
  find "${ROOT_DIR}/hard-rom/inspect/${VARIANT}" -maxdepth 1 -type f -name "verify-${VARIANT}-offline-image-*.txt" -exec stat -f '%m %N' {} \; 2>/dev/null \
    | sort -rn \
    | sed -n '1s/^[0-9][0-9]* //p'
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

need_file() {
  [ -f "$1" ] || {
    echo "error: missing file: $1" >&2
    exit 1
  }
}

need_executable() {
  [ -x "$1" ] || {
    echo "error: missing executable: $1" >&2
    exit 1
  }
}

if [ "${1:-}" != "--offline-image" ]; then
  "${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh" "$@"
  exit $?
fi

"${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh" "$@"

report="$(latest_offline_report)"
[ -n "$report" ] || {
  echo "error: missing ${VARIANT} offline report after base verifier" >&2
  exit 1
}

{
  echo
  echo "## agent0.8 extra offline checks"
  decode_dir="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify/smartisax-apk-decoded"
  [ -d "$decode_dir" ] || {
    echo "error: missing decoded Smartisax APK: ${decode_dir}" >&2
    exit 1
  }
  grep -R -q 'SmartisaxAgentRuntime' "$decode_dir" || { echo "error: Agent runtime missing from dex" >&2; exit 1; }
  grep -R -q 'SmartisaxAgentProviders' "$decode_dir" || { echo "error: Agent providers missing from dex" >&2; exit 1; }
  grep -R -q 'SmartisaxAccessibilityService' "$decode_dir" || { echo "error: Accessibility service missing from dex" >&2; exit 1; }
  grep -R -q 'SmartisaxOneStepController' "$decode_dir" || { echo "error: One Step controller missing from dex" >&2; exit 1; }
  grep -R -q 'SmartisaxScreenCapture' "$decode_dir" || { echo "error: shared screen capture helper missing from dex" >&2; exit 1; }
  grep -R -q 'mimo-v2.5' "$decode_dir" || { echo "error: MiMo model marker missing" >&2; exit 1; }
  grep -R -q 'deepseek-v4-flash' "$decode_dir" || { echo "error: DeepSeek model marker missing" >&2; exit 1; }
  grep -R -q 'https://api.xiaomimimo.com/v1/chat/completions' "$decode_dir" || { echo "error: MiMo API marker missing" >&2; exit 1; }
  grep -R -q 'https://api.deepseek.com' "$decode_dir" || { echo "error: DeepSeek API marker missing" >&2; exit 1; }
  grep -R -q '/api/agent/status' "$decode_dir" || { echo "error: read-only agent status route missing" >&2; exit 1; }
  grep -R -q 'v0.agent0.8-onestep-a11y-nodes' "$decode_dir" || { echo "error: agent0.8 variant marker missing" >&2; exit 1; }
  grep -R -q 'one_step_visibility_recovery_home_exit_enter' "$decode_dir" || { echo "error: One Step visible-state recovery marker missing" >&2; exit 1; }
  grep -R -q 'accessibilityTree' "$decode_dir" || { echo "error: accessibilityTree prompt marker missing" >&2; exit 1; }
  grep -R -q 'getWindows' "$decode_dir" || { echo "error: Accessibility getWindows marker missing" >&2; exit 1; }
  grep -R -q 'android_accessibility_active_plus_windows' "$decode_dir" || { echo "error: Accessibility active+windows marker missing" >&2; exit 1; }
  grep -R -q 'windowCount' "$decode_dir" || { echo "error: Accessibility window count marker missing" >&2; exit 1; }
  grep -R -q 'provider_network_guard' "$decode_dir" || { echo "error: provider network guard marker missing" >&2; exit 1; }
  grep -R -q 'provider_network_dns_unavailable' "$decode_dir" || { echo "error: provider DNS failure marker missing" >&2; exit 1; }
  grep -R -q 'provider_request_timeout' "$decode_dir" || { echo "error: provider timeout marker missing" >&2; exit 1; }
  grep -R -q 'paused_provider_error' "$decode_dir" || { echo "error: provider error transcript marker missing" >&2; exit 1; }
  grep -R -q 'click_node' "$decode_dir" || { echo "error: click_node action marker missing" >&2; exit 1; }
  grep -R -q 'performAction' "$decode_dir" || { echo "error: Accessibility click marker missing" >&2; exit 1; }
  grep -R -q 'enabled_accessibility_services' "$decode_dir" || { echo "error: Accessibility auto-enable marker missing" >&2; exit 1; }
  grep -R -q 'accessibility_action_guard' "$decode_dir" || { echo "error: Accessibility action guard marker missing" >&2; exit 1; }
  grep -R -q 'one_step' "$decode_dir" || { echo "error: one_step action marker missing" >&2; exit 1; }
  grep -R -q 'screen_freshness_guard' "$decode_dir" || { echo "error: screen freshness guard marker missing" >&2; exit 1; }
  grep -R -q 'visualSignature' "$decode_dir" || { echo "error: visual signature marker missing" >&2; exit 1; }
  grep -q 'android.accessibilityservice.AccessibilityService' "${decode_dir}/AndroidManifest.xml" || { echo "error: Accessibility service manifest entry missing" >&2; exit 1; }
  grep -q 'canRetrieveWindowContent' "${decode_dir}/res/xml/smartisax_accessibility_service.xml" || { echo "error: Accessibility config missing" >&2; exit 1; }
  grep -q 'data-agent-action="start"' "${decode_dir}/assets/shell/index.html" || { echo "error: Shell Agent start UI missing" >&2; exit 1; }
  grep -q 'click_node(' "${decode_dir}/assets/shell/shell.js" || { echo "error: Shell click_node transcript missing" >&2; exit 1; }
  grep -q 'A11y' "${decode_dir}/assets/shell/shell.js" || { echo "error: Shell accessibility status missing" >&2; exit 1; }
  if grep -R -q '/api/input' "$decode_dir"; then
    echo "error: forbidden HTTP input route regressed" >&2
    exit 1
  fi

  need_file "$SYSTEM_IMG"
  [ "$(sha256_one "$SYSTEM_IMG")" = "$EXPECTED_SYSTEM_SHA256" ] || {
    echo "error: system image hash mismatch for ${SYSTEM_IMG}" >&2
    exit 1
  }
  need_executable "$DEBUGFS"
  need_file "$APKTOOL"
  need_file "$FW_ANDROID"
  need_file "$FW_SMARTISAN"
  need_executable "$SIGCHECK"

  sidebar_verify_dir="${ROOT_DIR}/hard-rom/work/${VARIANT}/verify/sidebar-apk"
  framework_dir="${sidebar_verify_dir}/frameworks"
  dumped_sidebar="${sidebar_verify_dir}/Sidebar.apk"
  decoded_sidebar="${sidebar_verify_dir}/decoded"
  rm -rf "$sidebar_verify_dir"
  mkdir -p "$framework_dir"
  "$DEBUGFS" -R "dump ${SIDEBAR_IMAGE_PATH} ${dumped_sidebar}" "$SYSTEM_IMG" >/dev/null 2>&1
  need_file "$dumped_sidebar"
  [ "$(sha256_one "$dumped_sidebar")" = "$EXPECTED_SIDEBAR_SHA256" ] || {
    echo "error: Sidebar APK hash mismatch" >&2
    exit 1
  }
  unzip -t "$dumped_sidebar" >/dev/null
  "$SIGCHECK" "$dumped_sidebar" > "${sidebar_verify_dir}/signature.txt"
  grep -q '^apk_sig_block_magic=present$' "${sidebar_verify_dir}/signature.txt" || { echo "error: Sidebar APK sig block missing" >&2; exit 1; }
  grep -q '^keytool_status=1$' "${sidebar_verify_dir}/signature.txt" || { echo "error: expected Sidebar digest-boundary keytool status" >&2; exit 1; }
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$framework_dir" "$FW_ANDROID" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" if -p "$framework_dir" "$FW_SMARTISAN" >/dev/null
  "$JAVA_BIN" -jar "$APKTOOL" d -p "$framework_dir" -f -o "$decoded_sidebar" "$dumped_sidebar" >/dev/null
  grep -q 'package="com.smartisanos.sidebar"' "${decoded_sidebar}/AndroidManifest.xml" || { echo "error: Sidebar package identity changed" >&2; exit 1; }
  grep -q 'android:sharedUserId="android.uid.system"' "${decoded_sidebar}/AndroidManifest.xml" || { echo "error: Sidebar sharedUserId changed" >&2; exit 1; }
  grep -q 'coreApp="true"' "${decoded_sidebar}/AndroidManifest.xml" || { echo "error: Sidebar coreApp flag changed" >&2; exit 1; }
  grep -q 'com.smartisanos.sidebar.SidebarService' "${decoded_sidebar}/AndroidManifest.xml" || { echo "error: SidebarService missing" >&2; exit 1; }
  grep -q 'com.smartisanos.sidebar.storage.SidebarCallProvider' "${decoded_sidebar}/AndroidManifest.xml" || { echo "error: Sidebar call provider missing" >&2; exit 1; }
  grep -q 'com.smartisanos.sidebar.storage.db.SidebarSyncProvider' "${decoded_sidebar}/AndroidManifest.xml" || { echo "error: Sidebar sync provider missing" >&2; exit 1; }
  grep -R -q 'smartisax:onestep:app' "${decoded_sidebar}/smali" || { echo "error: Sidebar Agent app node marker missing" >&2; exit 1; }
  grep -R -q 'bindSmartisaxAgentAccessibility' "${decoded_sidebar}/smali" || { echo "error: Sidebar Agent bind helper missing" >&2; exit 1; }
  grep -R -q 'setContentDescription' "${decoded_sidebar}/smali" || { echo "error: Sidebar contentDescription setter missing" >&2; exit 1; }
  grep -R -q 'setImportantForAccessibility' "${decoded_sidebar}/smali" || { echo "error: Sidebar importantForAccessibility setter missing" >&2; exit 1; }
  grep -R -q 'setOnClickListener' "${decoded_sidebar}/smali" || { echo "error: Sidebar click listener bind missing" >&2; exit 1; }
  listener_smali="${decoded_sidebar}/smali/com/smartisanos/sidebar/toparea/view/AppListAdapter\$AgentAppClickListener.smali"
  [ -f "$listener_smali" ] || { echo "error: Sidebar Agent click listener smali missing" >&2; exit 1; }
  grep -q 'dismissAllDialog' "$listener_smali" || { echo "error: Sidebar Agent click listener does not dismiss dialogs" >&2; exit 1; }
  grep -q 'openUI(Landroid/content/Context;)Z' "$listener_smali" || { echo "error: Sidebar Agent click listener does not open AppItem UI" >&2; exit 1; }
  grep -q 'Tracker;->onEvent' "$listener_smali" || { echo "error: Sidebar Agent click listener lost app tracking call" >&2; exit 1; }
  grep -q 'getPackageName' "$listener_smali" || { echo "error: Sidebar Agent click listener lost package binding" >&2; exit 1; }

  "${ROOT_DIR}/tools/r2-agent0-offline-tests.py"
  echo "sidebar_agent_onestep_a11y_nodes=ok"
  echo "agent08_extra_offline_checks=ok"
} 2>&1 | tee -a "$report"
