#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/hard-rom/inspect/browser-webview-live-state}"
TS="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT:-${OUT_DIR}/browser-webview-live-state-${TS}.txt}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-browser-webview-live-state-audit.sh

Environment:
  SERIAL       Android serial, default bb12d264
  OUT_DIR      Report directory, default hard-rom/inspect/browser-webview-live-state
  REPORT       Report path override
  ROOT_HELPER  Root wrapper, default tools/r2-root.sh

This script is read-only. It does not reboot, flash, erase misc, write settings,
change packages, clear package caches, delete data, or mutate /data. It only
collects live BrowserChrome/WebView state needed to design stock no-op gates and
modern WebView/browser backports.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
  usage
  exit 0
fi

mkdir -p "$OUT_DIR"
: > "$REPORT"

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

section() {
  log ""
  log "## $*"
}

run_cmd() {
  log "\$ $*"
  "$@" 2>&1 | tr -d '\r' | tee -a "$REPORT" || true
}

adb_device() {
  adb -s "$SERIAL" "$@"
}

adb_shell() {
  adb_device shell "$@" 2>&1 | tr -d '\r'
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

log "# R2 Browser/WebView Live State Audit"
log "timestamp=${TS}"
log "serial=${SERIAL}"
log "report=${REPORT#${ROOT_DIR}/}"
log "boundary=read-only; no reboot, no flash, no settings write, no package mutation, no package-cache clear, no /data cleanup"

section "adb"
run_cmd adb devices -l
if ! adb_available; then
  log "result=DEVICE_NOT_AVAILABLE"
  log "report=${REPORT}"
  exit 1
fi

section "device props"
adb_shell 'printf "sys.boot_completed=%s\n" "$(getprop sys.boot_completed)";
printf "ro.boot.slot_suffix=%s\n" "$(getprop ro.boot.slot_suffix)";
printf "init.svc.bootanim=%s\n" "$(getprop init.svc.bootanim)";
printf "ro.boot.verifiedbootstate=%s\n" "$(getprop ro.boot.verifiedbootstate)";
printf "ro.build.version.sdk=%s\n" "$(getprop ro.build.version.sdk)";
printf "ro.build.fingerprint=%s\n" "$(getprop ro.build.fingerprint)";
printf "ro.product.cpu.abi=%s\n" "$(getprop ro.product.cpu.abi)";
printf "ro.product.cpu.abilist=%s\n" "$(getprop ro.product.cpu.abilist)"' | tee -a "$REPORT"

section "root status"
if [ -x "$ROOT_HELPER" ]; then
  run_cmd "$ROOT_HELPER" cmd 'id; getenforce; getprop ro.boot.slot_suffix'
else
  log "missing_root_helper=${ROOT_HELPER}"
fi

section "WebViewUpdateService"
adb_shell 'cmd webviewupdate getCurrentWebViewPackage 2>/dev/null || true;
cmd webviewupdate 2>&1 | sed -n "1,120p" || true;
dumpsys webviewupdate 2>/dev/null | sed -n "1,220p" || true' | tee -a "$REPORT"

section "WebView settings"
adb_shell 'for ns in global secure system; do
  for key in \
    webview_provider \
    webview_multiprocess \
    webview_fallback_logic_enabled \
    webview_data_reduction_proxy_key; do
      value="$(settings get "$ns" "$key" 2>/dev/null || true)"
      printf "%s.%s=%s\n" "$ns" "$key" "$value"
  done
done' | tee -a "$REPORT"

section "package paths and package state"
adb_shell 'for pkg in \
  com.android.webview \
  com.android.browser \
  com.google.android.webview \
  com.google.android.trichromelibrary \
  com.google.android.webview.beta \
  com.android.chrome \
  com.android.settings; do
    echo "### package ${pkg}"
    pm path "$pkg" 2>/dev/null | sed -n "1,40p"
    dumpsys package "$pkg" 2>/dev/null | grep -E "Package \\[|versionCode=|versionName=|targetSdk=|codePath=|resourcePath=|legacyNativeLibraryDir=|primaryCpuAbi=|secondaryCpuAbi=|dataDir=|pkgFlags=|privateFlags=|sharedUserId=|enabled=|stopped=|hidden=|suspended=|firstInstallTime=|lastUpdateTime=" | sed -n "1,120p"
done' | tee -a "$REPORT"

section "runtime file paths and mtimes"
adb_shell 'for path in \
  /product/app/webview \
  /product/app/webview/webview.apk \
  /system/app/BrowserChrome \
  /system/app/BrowserChrome/BrowserChrome.apk \
  /system/app/BrowserChrome/oat \
  /system/app/BrowserChrome/oat/arm64 \
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.odex \
  /system/app/BrowserChrome/oat/arm64/BrowserChrome.vdex; do
    echo "### path ${path}"
    ls -ldZ "$path" 2>/dev/null || true
    stat -c "stat path=%n mode=%a uid=%u gid=%g size=%s mtime_epoch=%Y mtime=%y" "$path" 2>/dev/null || true
done' | tee -a "$REPORT"

section "default browser resolver"
adb_shell 'echo "### resolve https";
cmd package resolve-activity --brief \
  -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d https://example.com 2>&1 | sed -n "1,80p" || true;
echo "### query https";
cmd package query-activities \
  -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d https://example.com 2>&1 | sed -n "1,160p" || true;
echo "### browser launcher";
cmd package query-activities \
  -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER \
  com.android.browser 2>&1 | sed -n "1,120p" || true;
echo "### WebView settings action";
cmd package resolve-activity --brief \
  -a android.settings.WEBVIEW_SETTINGS 2>&1 | sed -n "1,80p" || true' | tee -a "$REPORT"

section "package cache and Smartisan icon redirection"
if [ -x "$ROOT_HELPER" ]; then
  run_cmd "$ROOT_HELPER" cmd 'for path in \
    /data/system/package_cache \
    /data/system/icon \
    /data/system/icon/com.android.browser \
    /data/system/icon/com.android.webview \
    /data/system/redirection_policy.xml; do
      echo "### path ${path}"
      ls -ldZ "$path" 2>/dev/null || true
      stat -c "stat path=%n mode=%a uid=%u gid=%g size=%s mtime_epoch=%Y mtime=%y" "$path" 2>/dev/null || true
    done
    echo "### package_cache matching browser/webview"
    ls -la /data/system/package_cache 2>/dev/null | grep -Ei "browser|webview|BrowserChrome|com.android.browser|com.android.webview" || true
    echo "### icon browser subtree"
    find /data/system/icon/com.android.browser -maxdepth 2 -type f -o -type d 2>/dev/null | sort | sed -n "1,120p" || true
    echo "### redirection policy browser/webview lines"
    grep -Ei "browser|webview|BrowserChrome|com.android.browser|com.android.webview" /data/system/redirection_policy.xml 2>/dev/null | sed -n "1,120p" || true'
else
  log "missing_root_helper=${ROOT_HELPER}"
fi

section "current window and keyguard"
adb_shell 'dumpsys window | grep -E "mCurrentFocus|mFocusedApp|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen" | sed -n "1,100p"' | tee -a "$REPORT" || true

section "recent Browser/WebView logs"
adb_shell 'logcat -d -t 500 2>/dev/null | grep -Ei "WebView|webviewupdate|chromium|BrowserChrome|com.android.browser|com.android.webview|ResourcesManagerSmt|AssetManagerSmt|PackageCacher|package_cache|redirection|BigBang|Boom" | tail -n 180' | tee -a "$REPORT" || true

section "summary"
slot="$(adb_shell 'getprop ro.boot.slot_suffix 2>/dev/null || true' | tail -n 1)"
boot_completed="$(adb_shell 'getprop sys.boot_completed 2>/dev/null || true' | tail -n 1)"
webview_provider="$(adb_shell 'settings get global webview_provider 2>/dev/null || true' | tail -n 1)"
webview_path="$(adb_shell 'pm path com.android.webview 2>/dev/null | tr "\n" " " || true' | tail -n 1)"
browser_path="$(adb_shell 'pm path com.android.browser 2>/dev/null | tr "\n" " " || true' | tail -n 1)"
https_resolver="$(adb_shell 'cmd package resolve-activity --brief -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d https://example.com 2>/dev/null | tail -n 1 || true' | tail -n 1)"
keyguard_line="$(adb_shell 'dumpsys window 2>/dev/null | grep -E "isKeyguardShowing|mShowingLockscreen" | head -n 1 || true' | tail -n 1)"

log "slot=${slot}"
log "sys.boot_completed=${boot_completed}"
log "global.webview_provider=${webview_provider}"
log "com.android.webview.path=${webview_path}"
log "com.android.browser.path=${browser_path}"
log "https.resolver=${https_resolver}"
log "keyguard=${keyguard_line}"
log "result=PASS_READ_ONLY"
log "report=${REPORT}"
