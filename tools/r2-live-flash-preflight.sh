#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERIAL="${SERIAL:-bb12d264}"
ROOT_HELPER="${ROOT_HELPER:-${ROOT_DIR}/tools/r2-root.sh}"

variant="${1:-v0.12-framework-res-noop}"
report_required_regex_extra=""

die() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

need_file() {
  [ -f "$1" ] || die "missing file: $1"
}

need_executable() {
  [ -x "$1" ] || die "missing executable: $1"
}

sha256_one() {
  shasum -a 256 "$1" | awk '{print $1}'
}

check_hash() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  need_file "$path"
  actual="$(sha256_one "$path")"
  if [ "$actual" != "$expected" ]; then
    die "${label} hash mismatch: actual=${actual} expected=${expected} path=${path}"
  fi
  printf 'OK   %-22s %s  %s\n' "$label" "$actual" "$path"
}

latest_report() {
  local dir="$1"
  local pattern="$2"
  find "$dir" -maxdepth 1 -type f -name "$pattern" -exec stat -f '%m %N' {} \; 2>/dev/null \
    | sort -rn \
    | sed -n '1s/^[0-9][0-9]* //p'
}

check_report() {
  local label="$1"
  local dir="$2"
  local pattern="$3"
  local required_regex="$4"
  local report
  report="$(latest_report "$dir" "$pattern")"
  if [ -z "$report" ]; then
    die "missing offline PASS report for ${label}: ${dir}/${pattern}"
  fi
  if ! grep -Eq "$required_regex" "$report"; then
    die "latest offline report is missing required evidence for ${label}: ${report}"
  fi
  if [ -n "${report_required_regex_extra:-}" ] && ! grep -Eq "$report_required_regex_extra" "$report"; then
    die "latest offline report is missing extra required evidence for ${label}: ${report}"
  fi
  printf 'OK   %-22s %s\n' "${label} evidence" "$report"
}

adb_available() {
  adb devices | awk 'NR > 1 {print $1, $2}' | grep -q "^${SERIAL} device$"
}

print_device_state() {
  echo
  echo "## live device read-only state"
  if adb_available; then
    adb -s "$SERIAL" shell \
      'getprop sys.boot_completed; getprop ro.boot.slot_suffix; getprop init.svc.bootanim; getprop ro.boot.verifiedbootstate; getprop ro.build.fingerprint' \
      | tr -d '\r'
    echo
    "$ROOT_HELPER" status || warn "root status command failed"
  else
    warn "adb device ${SERIAL} is not online; skipping live adb state"
    adb devices -l || true
  fi

  if fastboot devices | awk '{print $1}' | grep -q "^${SERIAL}$"; then
    echo
    echo "## fastboot read-only state"
    fastboot -s "$SERIAL" getvar current-slot 2>&1 || true
    fastboot -s "$SERIAL" getvar unlocked 2>&1 || true
    fastboot -s "$SERIAL" getvar is-userspace 2>&1 || true
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  tools/r2-live-flash-preflight.sh [variant]

Variants:
  v0.12-framework-res-noop       next recommended framework-res no-op live gate
  v0.10-framework-locale-prune   language hard-prune candidate, only after v0.12 live PASS
  v0.11-native-darkmode          native Settings/SystemUI dark-mode behavior candidate
  v0.11.1-native-darkmode-settings-row native dark-mode candidate with reachable R2 Settings row
  v0.26a-launcher-entry-hide  hide VideoPlayer, ScreenRecorder, and QuickSearch launcher entries
  v0.26a.1-launcher-entry-hide-v2cert v2-cert fix after v0.26a package cert collection failure
  v0.26a.2-launcher-entry-hide-v2cert-cachebump v0.26a.1 plus package-cache invalidating directory mtimes
  v0.26b-sara-launcher-entry-hide-v2cert-cachebump hide Sara/VoiceAssistant launcher entry on top of v0.26a.2
  v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump hide Sidebar/One Step launcher entry on top of v0.26b
  v0.27-cloud-service-debloat hard-remove Smartisan cloud service ROM packages on top of v0.26c
  v0.28-wallet-handshaker-debloat hard-remove Wallet and HandShaker ROM packages on top of v0.27
  v0.29-sidebar-topbar-hide delete stock One Step topbar controls while preserving the blank topbar slot on top of v0.28
  v0.31-webview-stock-near-noop stock WebView provider near-noop gate on top of v0.29
  v0.32-browserchrome-stock-near-noop stock BrowserChrome near-noop gate on top of v0.29
  v0.33-system-b-grow-noop dynamic system_b partition/footer growth gate on top of v0.31
  v0.34-system-b-ext4-grow-fec FEC-preserving system_b ext4 capacity gate on top of v0.33
  v0.35-webview-m150-system-provider M150 WebView system-provider candidate on top of v0.34
  v0.35.1-webview-m150-browserchrome-deodex v0.35 follow-up removing BrowserChrome oat/vdex
  v0.35.2-webview-m150-clean-product-residue v0.35.1 follow-up removing old product WebView residue
  v0.36-smartisax-shell-debloat retired; flashed/booted but Smartisax APK failed Android 11 arsc alignment parse
  v0.36.1-smartisax-shell-debloat-arsc-align v0.36 follow-up with Smartisax resources.arsc stored and 4-byte aligned
  v0.37a-textboom-live-system-base TextBoom v3.2.2 live APK promoted byte-for-byte into /system for OCR-backend groundwork
  v0.37b-textboom-live-system-libs-deodex v0.37a follow-up adding TextBoom system libs and removing stale TextBoom oat/vdex
  v0.39-sidebar-font-ocr-deleted Sidebar/One Step font OCR code-deletion candidate on top of the live TextBoom/WebView baseline
  v0.40-textboom-ppocr-noop-adapter TextBoom LocalPpOcrApi no-op adapter gate on top of live-verified v0.39
  v0.41-textboom-ppocr-runtime-adapter TextBoom LocalPpOcrApi PP-OCRv6 small ONNX Runtime/OpenCV runtime adapter on top of v0.39
  v0.41.1-textboom-ppocr-runtime-arm32-libs v0.41 ABI fix adding 32-bit ORT/OpenCV libs for TextBoom app_process32
  v0.42-textboom-ppocr-preview-path v0.41.1 follow-up moving TextBoom preview image storage to app-specific external .boom
  v0.42.1-textboom-ppocr-preview-media-path v0.42 follow-up moving TextBoom preview image storage to Android/media after Android/data failed live
  v0.42.2-textboom-ppocr-preview-save-before-ocr v0.42.1 follow-up saving preview bitmap before PP-OCR starts
  v0.43a-textboom-csocr-intsig-delete v0.42.2 follow-up deleting TextBoom legacy CsOcr/Intsig/ocr_key
  v0.43b-textboom-csocr-intsig-delete-manifest-retained v0.43a repair retaining AndroidManifest.xml/ocr_key
  v0.43c-textboom-force-arm32-abi v0.43b ABI-control gate removing TextBoom APK/system arm64 libs
  v0.43d-textboom-codepath-arm32-abi v0.43c follow-up moving TextBoom to a fresh system app codePath to force ABI rescan
  v0.43e-textboom-codepath-arm64-runtime-repair v0.43d repair restoring target arm64 runtime libs
  v0.pm0-services-jar-noop PackageManager services.jar no-op framework gate on top of v0.43e
  v0.pm1-pms-cache-allowlist first narrow PackageManager policy: bypass package parser cache for Smartisax-managed system package paths
  v0.kg1-smartisax-skip-keyguard disable non-secure Keyguard after boot through services.jar on top of v0.pm1
  v0.usb1-no-smartisan-cdrom disable Smartisan transfer-tool virtual CD-ROM by removing mass_storage from vendor USB configs
  v0.usb2-physical-cdrom-iso-delete physically remove and free-only zero the inert Smartisan transfer-tool ISO
  v0.wadb1-smartisax-priv-wireless-adb move Smartisax to /system/priv-app and add the wireless ADB control permission whitelist
  v0.wadb2-smartisax-wireless-adb-current-wifi fix Smartisax wireless ADB by resolving the current Wi-Fi BSSID inside system_server
  v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache repair Smartisax hidden-API reflection and priv-app PackageManager cache bypass
  v0.wadb2.2-smartisax-wireless-adb-binder-transact repair Smartisax wireless ADB with raw Binder transact calls instead of hidden API reflection
  v0.portal1-smartisax-lan-portal-noop Smartisax LAN Device Portal noop: pairing/status only, no file/screen APIs
  v0.portal2-smartisax-remote-screen-control Smartisax LAN Device Portal remote screen PNG stream plus pointer input control
  v0.portal2.1-smartisax-remote-screen-control-privapi repair portal screen/input with privileged SurfaceControl/InputManager APIs
  v0.portal2.2-smartisax-remote-screen-control-bufferfix repair portal screenshot by converting SurfaceControl ScreenshotGraphicBuffer to Bitmap
  v0.portal2.3-smartisax-framebuffer-grant narrow services.jar policy granting READ_FRAME_BUFFER only to Smartisax
  v0.portal3b-h264-http-stream-prototype Smartisax LAN Portal H.264 Annex-B HTTP stream prototype
  v0.portal3c-h264-webcodecs-playback Smartisax LAN Portal MP4/video browser playback plus WebCodecs diagnostic over H.264
  v0.portal4b-mp4-control-polish Smartisax LAN Portal Start Live MP4/control polish plus retained WebRTC/RTP diagnostics
  v0.portal4c-session-hardening Smartisax LAN Portal pairing/session hardening on top of the MP4 fallback baseline
  v0.portal5a-native-webrtc-runtime Smartisax LAN Portal native Android libwebrtc DTLS/SRTP runtime gate on top of v0.portal4c
  v0.portal5b-native-webrtc-system-libs Smartisax LAN Portal v0.portal5a repair installing libwebrtc as external system app native libraries
  v0.portal5c-webrtc-software-bitmap-frames Smartisax LAN Portal v0.portal5b repair converting HARDWARE screenshots to software I420 frames
  v0.portal5d-webrtc-bitmap-copy-frames Smartisax LAN Portal v0.portal5c repair using Bitmap.copy for HARDWARE screenshot frames
  v0.portal5e-webrtc-h264-session-control Smartisax LAN Portal v0.portal5d follow-up defaulting browser WebRTC to H264 and adding session cleanup
  v0.portal5f-webrtc-datachannel-input Smartisax LAN Portal v0.portal5e follow-up removing HTTP /api/input and moving remote input to WebRTC DataChannel
  v0.portal5g-webrtc-touch-quality Smartisax LAN Portal v0.portal5f follow-up mapping touch overlay input to display coordinates and raising WebRTC frame-pump quality
  v0.portal5h-webrtc-bitrate-quality Smartisax LAN Portal v0.portal5g follow-up defaulting Portal UI to WebRTC and setting explicit H264 sender bitrate
  v0.portal5i-webrtc-runtime-tuning Smartisax LAN Portal v0.portal5h follow-up adding browser-side runtime WebRTC width/fps/bitrate tuning up to 1080p/30fps
  v0.portal5j-projection-texture-probe Smartisax LAN Portal v0.portal5i follow-up adding MediaProjection texture capture probe and 1080p60 runtime tuning target
  v0.portal5j.1-projection-permission-grant v0.portal5j repair granting Smartisax-only MediaProjection signature permissions through services.jar policy
  v0.portal5j.2-projection-binder-transact v0.portal5j.1 repair replacing blocked IMediaProjectionManager Stub reflection with raw Binder transact token creation
  v0.24-cleaner-apk-only-locale-prune latest eleven APK-only language-prune candidate
  v0.25-settings-noop-on-v0.24  SettingsSmartisan no-op gate rebased on live-verified v0.24
  systemui-certprobe-noop-on-v0.24 SmartisanSystemUI no-op gate rebased on live-verified v0.24
  v0.22-all-apk-only-locale-prune combined ten APK-only language-prune candidate
  v0.6-settings-noop             SettingsSmartisan no-op live gate
  systemui-certprobe-noop        SmartisanSystemUI no-op live gate

This script is read-only. It checks expected sparse-image hashes, rollback
readiness, latest offline PASS reports, verifier scripts, and current adb or
fastboot state. It never flashes, reboots, erases misc, or changes /data.
USAGE
}

case "$variant" in
  -h|--help|help)
    usage
    exit 0
    ;;
  v0.12|v0.12-framework-res-noop)
    variant="v0.12-framework-res-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.12-framework-res-noop-exact-current.sparse.img"
    image_hash="d5c63890f27f6609b09667cc0bee0dd4b55c5c335abeb530650c16fbce9d94d9"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.12-framework-res-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.12-framework-res-noop"
    report_pattern="verify-v0.12-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0[[:space:]]+sparse_slice=26c9255a0ec2b397b7c88292d82916ce611c5c08f60dd7a7305476f74bf77fa0'
    live_verify="tools/r2-verify-v0.12-framework-res-noop.sh --read-only"
    gate_note="recommended next live gate before any framework/product language hard-prune flash"
    ;;
  v0.10|v0.10-framework-locale-prune)
    variant="v0.10-framework-locale-prune"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.10-framework-locale-prune-exact-current.sparse.img"
    image_hash="62f5006f0c55c71bb405c0b300aa286579bb49a4687c5511a29bf85f98b28cae"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.10-framework-locale-prune.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.10-framework-locale-prune"
    report_pattern="verify-v0.10-offline-image-*.txt"
    report_required_regex='product_b[[:space:]]+image=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2[[:space:]]+sparse_slice=78eb6f500ccf0a719629db206dd140aaf5dd45a5861caee5c829fe024ddd19b2'
    live_verify="tools/r2-verify-v0.10-framework-locale-prune.sh --read-only"
    gate_note="RED language hard-prune candidate; use only after v0.12 live PASS"
    ;;
  v0.11|v0.11-native-darkmode|v0.11-native-darkmode-integration)
    variant="v0.11-native-darkmode"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.11-native-darkmode-exact-current.sparse.img"
    image_hash="a0afc5b979db769137a01d581848b3d30f653197665f5ce0958b4b2809a05ebb"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.11-native-darkmode.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.11-native-darkmode"
    report_pattern="verify-v0.11-native-darkmode-offline-image-*.txt"
    report_required_regex='system_ext_b[[:space:]]+image=0d5990969cf74e5c0073e1819862688bf20a406d4d41dd8242175f4ac5575aae[[:space:]]+sparse_slice=0d5990969cf74e5c0073e1819862688bf20a406d4d41dd8242175f4ac5575aae'
    live_verify="tools/r2-verify-v0.11-native-darkmode.sh --read-only"
    gate_note="native dark-mode behavior candidate; both SettingsSmartisan and SmartisanSystemUI no-op gates are live-proven, but this behavior image is not live-tested yet"
    ;;
  v0.11.1|v0.11.1-native-darkmode-settings-row)
    variant="v0.11.1-native-darkmode-settings-row"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.11.1-native-darkmode-settings-row-exact-current.sparse.img"
    image_hash="2f1a4d8b8579551bf04246d00099f15c5c5a42146336cd6a00d129bbcffb8fa0"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.11.1-native-darkmode-settings-row"
    report_pattern="verify-v0.11.1-native-darkmode-settings-row-offline-image-*.txt"
    report_required_regex='system_ext_b[[:space:]]+image=3f994cb1a7f2e82af007969ce7035e0ded83da90a0bef20f6142ac7e303c4f6a[[:space:]]+sparse_slice=3f994cb1a7f2e82af007969ce7035e0ded83da90a0bef20f6142ac7e303c4f6a'
    live_verify="tools/r2-verify-v0.11.1-native-darkmode-settings-row.sh --read-only"
    gate_note="native dark-mode follow-up candidate; fixes v0.11 SettingsSmartisan brightness-row reachability on Darwin/R2 while keeping the live-proven UiMode/SystemUI behavior"
    ;;
  v0.26a|v0.26a-launcher-entry-hide)
    variant="v0.26a-launcher-entry-hide"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26a-launcher-entry-hide-exact-current.sparse.img"
    image_hash="8f540a3437f3b53e09b18bf0b69c29545e1ee7f5ae10385e184369131271df8e"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.26a-launcher-entry-hide.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.26a-launcher-entry-hide"
    report_pattern="verify-v0.26a-launcher-entry-hide-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=2d11d0fe070e0742cb78d5ed32c4a0a112dedfcaa258539852fa6e51c0450284[[:space:]]+sparse_slice=2d11d0fe070e0742cb78d5ed32c4a0a112dedfcaa258539852fa6e51c0450284'
    live_verify="tools/r2-verify-v0.26a-launcher-entry-hide.sh --read-only"
    gate_note="manifest-only launcher entry hide for VideoPlayer, ScreenRecorderSmartisan, and QuickSearchBoxSmartisan on top of live-verified v0.11.1; not flashed or live-verified yet"
    ;;
  v0.26a.1|v0.26a.1-launcher-entry-hide-v2cert)
    variant="v0.26a.1-launcher-entry-hide-v2cert"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26a.1-launcher-entry-hide-v2cert-exact-current.sparse.img"
    image_hash="bf5d8aacddfc5a2844a00f05ea7ce905ef98cba58b53e6434bb63fb41bfe69d9"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.26a-launcher-entry-hide.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.26a.1-launcher-entry-hide-v2cert"
    report_pattern="verify-v0.26a.1-launcher-entry-hide-v2cert-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=92336395dea0f70b9c4252a963595aa4cef442945d633f69f75cf13e90df98e7[[:space:]]+sparse_slice=92336395dea0f70b9c4252a963595aa4cef442945d633f69f75cf13e90df98e7'
    live_verify="tools/r2-verify-v0.26a.1-launcher-entry-hide-v2cert.sh --read-only"
    gate_note="v2 signing-block carrier fix for the v0.26a manifest-only launcher entry hide; v0.26a booted but PackageManager rejected the edited APKs during certificate collection"
    ;;
  v0.26a.2|v0.26a.2-launcher-entry-hide-v2cert-cachebump)
    variant="v0.26a.2-launcher-entry-hide-v2cert-cachebump"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26a.2-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img"
    image_hash="a96006fcd6c53b82aa3638411e01a36ce0bb92b02737aa5351fdd8827578e792"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.26a.2-launcher-entry-hide-v2cert-cachebump"
    report_pattern="verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=5282661df53643800601e816882b31113b96991340d701c1598feefa89285ae7[[:space:]]+sparse_slice=5282661df53643800601e816882b31113b96991340d701c1598feefa89285ae7'
    live_verify="tools/r2-verify-v0.26a.2-launcher-entry-hide-v2cert-cachebump.sh --read-only"
    gate_note="v0.26a.1 v2 signing-block carrier fix plus package directory mtime bump so PackageCacher ignores stale pre-ROM ParsedPackage cache and reparses the launcher-hidden manifests"
    ;;
  v0.26b|v0.26b-sara-launcher-entry-hide-v2cert-cachebump)
    variant="v0.26b-sara-launcher-entry-hide-v2cert-cachebump"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img"
    image_hash="599578445026fbf8d35edffc014b71e7507eba9ce2921a82d0d298465e020ff1"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.26b-sara-launcher-entry-hide-v2cert-cachebump"
    report_pattern="verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=59dfbf3e5c15f95ee15b32624dd6fd03efd38a0f35325611c63b66da473e5fca[[:space:]]+sparse_slice=59dfbf3e5c15f95ee15b32624dd6fd03efd38a0f35325611c63b66da473e5fca'
    live_verify="tools/r2-verify-v0.26b-sara-launcher-entry-hide-v2cert-cachebump.sh --read-only"
    gate_note="Sara/VoiceAssistant manifest-only launcher entry hide on top of live-verified v0.26a.2; keeps v2 signing-block carrier and bumps the VoiceAssistant package directory mtime for PackageCacher"
    ;;
  v0.26c|v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump)
    variant="v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-exact-current.sparse.img"
    image_hash="fa78ad42e8e8e367a61339d7bf28e4b94dba402bdfb02a944c317a1eda76c5e1"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump"
    report_pattern="verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=c0aaf672f208cf11d8849d1459b5eef571a1710e21d8672e62c45725c012f945[[:space:]]+sparse_slice=c0aaf672f208cf11d8849d1459b5eef571a1710e21d8672e62c45725c012f945'
    live_verify="tools/r2-verify-v0.26c-sidebar-launcher-entry-hide-v2cert-cachebump.sh --read-only"
    gate_note="Sidebar/One Step manifest-only launcher entry hide on top of live-verified v0.26b; preserves SidebarService, providers, explicit SettingActivity resolution, and sidebar windows while bumping the Sidebar package directory mtime for PackageCacher"
    ;;
  v0.27|v0.27-cloud-service-debloat)
    variant="v0.27-cloud-service-debloat"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.27-cloud-service-debloat-exact-current.sparse.img"
    image_hash="11f5c3d74d2468270e06cb929ea9482f9af761c9275a074df5a78cc55fa13cb1"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.27-cloud-service-debloat.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.27-cloud-service-debloat"
    report_pattern="verify-v0.27-cloud-service-debloat-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=e81e02caa9009b74138860f5c8c51ef66401ad863c119572d5cb97a574038bad[[:space:]]+sparse_slice=e81e02caa9009b74138860f5c8c51ef66401ad863c119572d5cb97a574038bad'
    live_verify="tools/r2-verify-v0.27-cloud-service-debloat.sh --read-only"
    gate_note="Smartisan cloud service hard-ROM debloat on top of live-verified v0.26c; final live package absence may require a separate explicit /data cleanup because com.smartisanos.cloudsync is currently an updated-system /data/app package"
    ;;
  v0.28|v0.28-wallet-handshaker-debloat)
    variant="v0.28-wallet-handshaker-debloat"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.28-wallet-handshaker-debloat-exact-current.sparse.img"
    image_hash="705c42c5b639ed9f08e8555749e6b7abaf9d281a2f7f2324e2ef29ceec561728"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.28-wallet-handshaker-debloat.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.28-wallet-handshaker-debloat"
    report_pattern="verify-v0.28-wallet-handshaker-debloat-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=334f7e32491c2a43f524d3112807c19cf6f104a20fae2d2eb9f749aee9b73daf[[:space:]]+sparse_slice=334f7e32491c2a43f524d3112807c19cf6f104a20fae2d2eb9f749aee9b73daf'
    live_verify="tools/r2-verify-v0.28-wallet-handshaker-debloat.sh --read-only-pre-clean"
    gate_note="Wallet and HandShaker hard-ROM debloat on top of live-verified v0.27; final Wallet absence may require a separate explicit /data cleanup because com.smartisanos.wallet is currently an updated-system /data/app package"
    ;;
  v0.29|v0.29-sidebar-topbar-hide)
    variant="v0.29-sidebar-topbar-hide"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.29-sidebar-topbar-hide-exact-current.sparse.img"
    image_hash="a8207ee148946057fc2d9c00780b2939c8307f7b0b88ae2b4bc304cfb39892d9"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.29-sidebar-topbar-hide.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.29-sidebar-topbar-hide"
    report_pattern="verify-v0.29-sidebar-topbar-hide-offline-image-*.txt"
    report_required_regex='topbar_slot_preserved=ok'
    live_verify="tools/r2-verify-v0.29-sidebar-topbar-hide.sh --read-only"
    gate_note="Sidebar/One Step topbar cleanup on top of live-verified v0.28; deletes the stock topbar buttons/text and removes their code bindings while preserving the blank topbar slot and Sidebar drag/status switching surfaces"
    ;;
  v0.31|v0.31-webview-stock-near-noop)
    variant="v0.31-webview-stock-near-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.31-webview-stock-near-noop-exact-current.sparse.img"
    image_hash="c187b050ced604d3ba52cee0dd36b4a8a17f9a0d1c8b4ae78b0fde0ea44384ae"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.31-webview-stock-near-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.31-webview-stock-near-noop"
    report_pattern="verify-v0.31-webview-stock-near-noop-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE'
    live_verify="tools/r2-verify-v0.31-webview-stock-near-noop.sh --read-only"
    gate_note="stock WebView provider near-noop gate on top of live-verified v0.29; keeps /product/app/webview/webview.apk byte-identical and bumps only the WebView package directory mtime for PackageCacher/WebViewUpdateService validation"
    ;;
  v0.32|v0.32-browserchrome-stock-near-noop)
    variant="v0.32-browserchrome-stock-near-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.32-browserchrome-stock-near-noop-exact-current.sparse.img"
    image_hash="7b2ce1ccdab66a303fffd54d2dff8f940851672a8a97936c51874a5c28cc9795"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.32-browserchrome-stock-near-noop"
    report_pattern="verify-v0.32-browserchrome-stock-near-noop-offline-image-*.txt"
    report_required_regex='browser_apk_bytes=stock'
    live_verify="tools/r2-verify-v0.32-browserchrome-stock-near-noop.sh --read-only"
    gate_note="stock BrowserChrome near-noop gate on top of live-verified v0.29; patches only system_b package directory mtime while keeping BrowserChrome.apk byte-identical. This is a no-op gate before any BrowserChrome behavior replacement."
    ;;
  v0.33|v0.33-system-b-grow-noop)
    variant="v0.33-system-b-grow-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.33-system-b-grow-noop.sparse.img"
    image_hash="39e39965290b68a8980df8eaa090c2440000967f2f80648dc6a7316753165767"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.33-system-b-grow-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.33-system-b-grow-noop"
    report_pattern="verify-v0.33-system-b-grow-noop-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE'
    live_verify="tools/r2-verify-v0.33-system-b-grow-noop.sh --read-only"
    gate_note="dynamic partition/footer no-content growth gate on top of live-verified v0.31; grows system_b by 128 MiB and moves the AVB footer while keeping ext4 block count, APKs, and critical files byte-identical. This does not yet make /system df larger."
    ;;
  v0.34|v0.34-system-b-ext4-grow-fec)
    variant="v0.34-system-b-ext4-grow-fec"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.34-system-b-ext4-grow-fec.sparse.img"
    image_hash="bd795e1a91e4e3d6108bb989cd03cc1511fa2487cde1bd28bb0e857148b99232"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.34-system-b-ext4-grow-fec"
    report_pattern="verify-v0.34-system-b-ext4-grow-fec-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_FEC'
    report_required_regex_extra='FEC num roots:[[:space:]]+2'
    live_verify="tools/r2-verify-v0.34-system-b-ext4-grow-fec.sh --read-only"
    gate_note="FEC-preserving ext4 capacity gate on top of live-verified v0.33; keeps system_b partition size at 3183276032 bytes, grows ext4 to 3132964864 bytes, and rebuilds the hashtree footer with Android FEC roots=2. This is the first /system df-capacity growth test and still requires explicit flash confirmation."
    ;;
  v0.35|v0.35-webview-m150-system-provider)
    variant="v0.35-webview-m150-system-provider"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.35-webview-m150-system-provider.sparse.img"
    image_hash="e3e122faec2c01e1c710e9ad4661bbfd2c072573aa0e398eeb7afb5fa57c06ed"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.35-webview-m150-system-provider.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.35-webview-m150-system-provider"
    report_pattern="verify-v0.35-webview-m150-system-provider-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V035_WEBVIEW_SYSTEM_PROVIDER'
    report_required_regex_extra='product_public_webview=absent'
    live_verify="tools/r2-verify-v0.35-webview-m150-system-provider.sh --read-only"
    gate_note="first donor-backed WebView modernization candidate on top of live-verified v0.34; installs source-built M150 stock-carrier com.android.webview under /system/app/webview, hides the old product WebView APK from scanning, keeps BrowserChrome/framework provider config unchanged, and rebuilds system_b/product_b FEC footers. High-risk provider replacement; explicit flash confirmation required."
    ;;
  v0.35.1|v0.35.1-webview-m150-browserchrome-deodex)
    variant="v0.35.1-webview-m150-browserchrome-deodex"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.35.1-webview-m150-browserchrome-deodex.sparse.img"
    image_hash="c86a1f734ebb243d279291023a2427c2c0d0cf183d99aec8e8bf6af8573e9559"
    verifier="${ROOT_DIR}/tools/r2-hardrom-build-v0.35.1-webview-m150-browserchrome-deodex.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.35.1-webview-m150-browserchrome-deodex"
    report_pattern="verify-v0.35.1-webview-m150-browserchrome-deodex-offline-manual-*.txt"
    report_required_regex='result=PASS_MANUAL_OFFLINE_V0351_BROWSERCHROME_DEODEX'
    report_required_regex_extra='BrowserChrome/oat: File not found|BrowserChrome/oat/arm64/BrowserChrome.odex: File not found'
    live_verify="tools/r2-verify-v0.35-webview-m150-system-provider.sh --read-only && tools/r2-browser-webview-live-state-audit.sh"
    gate_note="v0.35 follow-up candidate: keeps the M150 system WebView provider and stock BrowserChrome APK unchanged, removes BrowserChrome prebuilt oat/vdex that caused renderer SIGABRT/white-page loading, bumps the BrowserChrome package directory mtime, and rebuilds system_b FEC. BrowserChrome functional repro must be repeated after flash."
    ;;
  v0.35.2|v0.35.2-webview-m150-clean-product-residue)
    variant="v0.35.2-webview-m150-clean-product-residue"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.35.2-webview-m150-clean-product-residue.sparse.img"
    image_hash="977f753dee7b84adc7218f5f0f4a8fd7b4403e8e39b24c77da013c8c6b7ec2f5"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.35.2-webview-m150-clean-product-residue"
    report_pattern="verify-v0.35.2-webview-m150-clean-product-residue-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0352_WEBVIEW_PRODUCT_RESIDUE_CLEAN'
    report_required_regex_extra='product_webview_dir=absent'
    live_verify="tools/r2-verify-v0.35.2-webview-m150-clean-product-residue.sh --read-only && tools/r2-browser-webview-live-state-audit.sh"
    gate_note="v0.35.1 follow-up candidate: keeps the M150 system WebView provider and BrowserChrome deodex fix unchanged, removes the old /product/app/webview hidden stock backup plus stale oat/vdex tree, and rebuilds product_b FEC. After flash, repeat WebView provider, stock BrowserChrome, Big Bang, and third-party embedded WebView tests."
    ;;
  v0.36.1|v0.36.1-smartisax-shell-debloat-arsc-align)
    variant="v0.36.1-smartisax-shell-debloat-arsc-align"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.36.1-smartisax-shell-debloat-arsc-align.sparse.img"
    image_hash="1dc67299b86a4dde63dc44d2620ce1fe6b6421790bdec082fb12c4c32cc83c03"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.36-smartisax-shell-debloat.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.36.1-smartisax-shell-debloat-arsc-align"
    report_pattern="verify-v0.36.1-smartisax-shell-debloat-arsc-align-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V036_SMARTISAX_SHELL_DEBLOAT'
    report_required_regex_extra='smartisax_resources_arsc_layout=ok|removed_paths=ok count=19'
    live_verify="VARIANT=v0.36.1-smartisax-shell-debloat-arsc-align tools/r2-verify-v0.36-smartisax-shell-debloat.sh --read-only && tools/r2-browser-webview-live-state-audit.sh"
    gate_note="v0.36 follow-up: keeps the same Smartisax browser/Home system shell and user-selected debloat set, but fixes the target R+ PackageManager parse failure by storing and 4-byte aligning Smartisax resources.arsc. After flash, verify Smartisax PackageManager registration, resolver surfaces, stock BrowserChrome, Big Bang, and WebView."
    ;;
  v0.37a|v0.37a-textboom-live-system-base)
    variant="v0.37a-textboom-live-system-base"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.37a-textboom-live-system-base.sparse.img"
    image_hash="537774d5c54358c893c51d2d8c68e6ab93a6340ddf6b8faba9aba0630cb65bfa"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.37a-textboom-live-system-base.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.37a-textboom-live-system-base"
    report_pattern="verify-v0.37a-textboom-live-system-base-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V037A_TEXTBOOM_LIVE_SYSTEM_BASE'
    report_required_regex_extra='textboom_apk_contract=ok'
    live_verify="tools/r2-verify-v0.37a-textboom-live-system-base.sh --read-only-pre-clean"
    gate_note="TextBoom OCR groundwork on top of live-verified v0.36.1: promotes the live v3.2.2 TextBoom APK byte-for-byte into /system/app/TextBoom without manifest/code/resource edits, preserving its v1/JAR signature. The active /data/app updated-system shadow is expected to remain until a separate explicitly confirmed PackageManager cleanup."
    ;;
  v0.37b|v0.37b-textboom-live-system-libs-deodex)
    variant="v0.37b-textboom-live-system-libs-deodex"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.37b-textboom-live-system-libs-deodex.sparse.img"
    image_hash="f8569f4a2a878e7a31ffb54dc352d2a4ccbd304facbd14f3d0fbec7b06a60b04"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.37b-textboom-live-system-libs-deodex.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.37b-textboom-live-system-libs-deodex"
    report_pattern="verify-v0.37b-textboom-live-system-libs-deodex-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V037B_TEXTBOOM_LIVE_SYSTEM_LIBS_DEODEX'
    report_required_regex_extra='textboom_system_libs=ok count=13'
    live_verify="tools/r2-verify-v0.37b-textboom-live-system-libs-deodex.sh --read-only-pre-repair"
    gate_note="v0.37a follow-up: keeps the live TextBoom v3.2.2 system APK unchanged, adds its 13 32-bit native libraries under /system/app/TextBoom/lib/arm, removes stale stock TextBoom oat/vdex, and rebuilds system_b FEC. The active /data/app updated-system shadow is expected to remain until a separate explicitly confirmed shadow repair."
    ;;
  v0.39|v0.39-sidebar-font-ocr-deleted)
    variant="v0.39-sidebar-font-ocr-deleted"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.39-sidebar-font-ocr-deleted.sparse.img"
    image_hash="a3672c3d32e7acedaf83051b289df86c729e91eb3e24f4e958b3fa4b42560f79"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.39-sidebar-font-ocr-deleted.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.39-sidebar-font-ocr-deleted"
    report_pattern="verify-v0.39-sidebar-font-ocr-deleted-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V039_SIDEBAR_FONT_OCR_DELETED'
    report_required_regex_extra='sidebar_font_ocr_code_deleted=ok|textboom_lib_arm_retained=ok'
    live_verify="tools/r2-verify-v0.39-sidebar-font-ocr-deleted.sh --read-only && tools/r2-browser-webview-live-state-audit.sh"
    gate_note="Sidebar/One Step font OCR code-deletion candidate on top of the live TextBoom/WebView baseline: removes BoomFontActivity/FontResultActivity manifest declarations, Sidebar open/font classes, Sidebar-local Intsig SDK copy, IdentifyFontView, METHOD_FONT_REQUEST -> FontUtils reachability, and stale type=1 tool-button mapping while preserving TextBoom v3.2.2, M150 WebView, BrowserChrome, Smartisax, and Sidebar service/window contracts."
    ;;
  v0.40|v0.40-textboom-ppocr-noop-adapter)
    variant="v0.40-textboom-ppocr-noop-adapter"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.40-textboom-ppocr-noop-adapter.sparse.img"
    image_hash="e1dd20fb38d7e8e49b7e111d8a92c59e1142a1bd6fe992cb1fb752a51e54ab7b"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.40-textboom-ppocr-noop-adapter.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.40-textboom-ppocr-noop-adapter"
    report_pattern="verify-v0.40-textboom-ppocr-noop-adapter-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V040_TEXTBOOM_PPOCR_NOOP_ADAPTER'
    report_required_regex_extra='textboom_ppocr_noop_adapter_semantics=ok|textboom_lib_arm_retained=ok'
    live_verify="tools/r2-verify-v0.40-textboom-ppocr-noop-adapter.sh --read-only"
    gate_note="TextBoom PP-OCR integration package/cache gate on top of live-verified v0.39: switches BoomOcrActivity and BoomAccessOcrActivity from CsOcr to LocalPpOcrApi no-op while keeping legacy CsOcr/com.intsig present and preserving Sidebar/WebView/Smartisax."
    ;;
  v0.41|v0.41-textboom-ppocr-runtime-adapter)
    variant="v0.41-textboom-ppocr-runtime-adapter"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.41-textboom-ppocr-runtime-adapter.sparse.img"
    image_hash="f65fd372c8ac4642d8ed0ead7abe8535f904f740a6020b19019590ef3eacbce4"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.41-textboom-ppocr-runtime-adapter.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.41-textboom-ppocr-runtime-adapter"
    report_pattern="verify-v0.41-textboom-ppocr-runtime-adapter-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V041_TEXTBOOM_PPOCR_RUNTIME_ADAPTER'
    report_required_regex_extra='textboom_ppocr_runtime_adapter_semantics=ok|textboom_runtime_libs_in_image=ok count=4'
    live_verify="tools/r2-verify-v0.41-textboom-ppocr-runtime-adapter.sh --read-only"
    gate_note="TextBoom real local OCR runtime gate on top of live-proven v0.39: switches image OCR entry points to LocalPpOcrApi backed by official PP-OCRv6 small ONNX models, onnxruntime-android 1.21.1, and OpenCV 4.9.0 while still retaining legacy CsOcr/com.intsig/ocr_key until live OCR quality and stability pass."
    ;;
  v0.41.1|v0.41.1-textboom-ppocr-runtime-arm32-libs)
    variant="v0.41.1-textboom-ppocr-runtime-arm32-libs"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.41.1-textboom-ppocr-runtime-arm32-libs.sparse.img"
    image_hash="1517f5acc76554b8537938daf99938ad6d17916088c4e8e73c787fc1007eee58"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.41.1-textboom-ppocr-runtime-arm32-libs.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.41.1-textboom-ppocr-runtime-arm32-libs"
    report_pattern="verify-v0.41.1-textboom-ppocr-runtime-arm32-libs-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0411_TEXTBOOM_PPOCR_RUNTIME_ARM32_LIBS'
    report_required_regex_extra='arm32-libopencv_java4.so|arm32-libonnxruntime.so'
    live_verify="tools/r2-verify-v0.41.1-textboom-ppocr-runtime-arm32-libs.sh --read-only"
    gate_note="TextBoom PP-OCR runtime ABI fix on top of flashed v0.41: keeps the v0.41 TextBoom APK hash stable and adds 32-bit libonnxruntime, libonnxruntime4j_jni, and libopencv_java4 under /system/app/TextBoom/lib/arm for TextBoom's armeabi-v7a app_process32 runtime."
    ;;
  v0.42|v0.42-textboom-ppocr-preview-path)
    variant="v0.42-textboom-ppocr-preview-path"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.42-textboom-ppocr-preview-path.sparse.img"
    image_hash="8a1b8ade7eec8873f650c2257224493679f679cf3103c1bc0fadb458c7bb1722"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.42-textboom-ppocr-preview-path"
    report_pattern="verify-v0.42-textboom-ppocr-preview-path-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V042_TEXTBOOM_PPOCR_PREVIEW_PATH'
    live_verify="tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.41.1 follow-up that moves TextBoom result-page preview storage from /sdcard/.boom to TextBoom app-specific external storage while retaining PP-OCR runtime/libs."
    ;;
  v0.42.1|v0.42.1-textboom-ppocr-preview-media-path)
    variant="v0.42.1-textboom-ppocr-preview-media-path"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.42.1-textboom-ppocr-preview-media-path.sparse.img"
    image_hash="27767d12828eaf0628290a49ca7391007f7fad6d631db97f3f345c8ed40260e1"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.42.1-textboom-ppocr-preview-media-path"
    report_pattern="verify-v0.42.1-textboom-ppocr-preview-media-path-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V0421_TEXTBOOM_PPOCR_PREVIEW_MEDIA_PATH'
    live_verify="VARIANT=v0.42.1-textboom-ppocr-preview-media-path NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom RESULT_READ_ONLY=PASS_READ_ONLY_V0421_TEXTBOOM_PPOCR_PREVIEW_MEDIA_PATH tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.42 follow-up after live Android/data ENOENT: moves TextBoom result-page preview storage from /sdcard/.boom to /sdcard/Android/media/com.smartisanos.textboom/.boom while retaining the v0.41.1 PP-OCR runtime/libs."
    ;;
  v0.42.2|v0.42.2-textboom-ppocr-preview-save-before-ocr)
    variant="v0.42.2-textboom-ppocr-preview-save-before-ocr"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.42.2-textboom-ppocr-preview-save-before-ocr.sparse.img"
    image_hash="e74e76960e15eb9a608742cafdf1bbfda597b9277f922ed019c6b525f328cb40"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.42.2-textboom-ppocr-preview-save-before-ocr"
    report_pattern="verify-v0.42.2-textboom-ppocr-preview-save-before-ocr-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V0422_TEXTBOOM_PPOCR_PREVIEW_SAVE_BEFORE_OCR'
    live_verify="VARIANT=v0.42.2-textboom-ppocr-preview-save-before-ocr NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom RESULT_READ_ONLY=PASS_READ_ONLY_V0422_TEXTBOOM_PPOCR_PREVIEW_SAVE_BEFORE_OCR tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.42.1 follow-up after live Android/media ENOENT: keeps the Android/media preview path and patches BoomOcrActivity.dealSaveBitmapResult to save imageboom.jpg before LocalPpOcrApi starts PP-OCR."
    ;;
  v0.43a|v0.43a-textboom-csocr-intsig-delete)
    variant="v0.43a-textboom-csocr-intsig-delete"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.43a-textboom-csocr-intsig-delete.sparse.img"
    image_hash="5384e2964de7105db2adbf26d42ae0529af26ce4d0666b97a062578762a7f097"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.43a-textboom-csocr-intsig-delete"
    report_pattern="verify-v0.43a-textboom-csocr-intsig-delete-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V043A_TEXTBOOM_CSOCR_INTSIG_DELETE'
    report_required_regex_extra='textboom.apk_preview_path=ok|system_b_avb_fec=ok'
    live_verify="VARIANT=v0.43a-textboom-csocr-intsig-delete NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom EXPECT_LEGACY_CSOCR_REMOVED=1 EXPECT_OCR_KEY_REMOVED=1 RESULT_READ_ONLY=PASS_READ_ONLY_V043A_TEXTBOOM_CSOCR_INTSIG_DELETE tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.42.2 follow-up that keeps PP-OCR runtime and preview-save behavior while deleting TextBoom legacy CsOcr smali, TextBoom-local Intsig smali, manifest ocr_key, and the CSOCR error-log prefix."
    ;;
  v0.43b|v0.43b-textboom-csocr-intsig-delete-manifest-retained)
    variant="v0.43b-textboom-csocr-intsig-delete-manifest-retained"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.43b-textboom-csocr-intsig-delete-manifest-retained.sparse.img"
    image_hash="e88559e276cb9c4fec68f63687af90bee937dde04e05ec6a7320b6d0645e226c"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.43b-textboom-csocr-intsig-delete-manifest-retained"
    report_pattern="verify-v0.43b-textboom-csocr-intsig-delete-manifest-retained-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED'
    report_required_regex_extra='textboom.apk_preview_path=ok|system_b_avb_fec=ok'
    live_verify="VARIANT=v0.43b-textboom-csocr-intsig-delete-manifest-retained NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom EXPECT_LEGACY_CSOCR_REMOVED=1 EXPECT_OCR_KEY_REMOVED=0 TEXTBOOM_PRIMARY_CPU_ABI=arm64-v8a RESULT_READ_ONLY=PASS_READ_ONLY_V043B_TEXTBOOM_CSOCR_INTSIG_DELETE_MANIFEST_RETAINED tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.43a repair that keeps the original AndroidManifest.xml/ocr_key package parse boundary, changes only classes2.dex, and deletes TextBoom legacy CsOcr/Intsig code while preserving v0.42.2 PP-OCR preview-save behavior."
    ;;
  v0.43c|v0.43c-textboom-force-arm32-abi)
    variant="v0.43c-textboom-force-arm32-abi"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.43c-textboom-force-arm32-abi.sparse.img"
    image_hash="0b42d185cfdc187b1065be15a3b0cf897be85dd05dceac9569e03341dda9ace2"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.43c-textboom-force-arm32-abi"
    report_pattern="verify-v0.43c-textboom-force-arm32-abi-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V043C_TEXTBOOM_FORCE_ARM32_ABI'
    report_required_regex_extra='textboom.apk_preview_path=ok|system_b_avb_fec=ok|arm64-lib-dir[[:space:]]+absent'
    live_verify="VARIANT=v0.43c-textboom-force-arm32-abi NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom EXPECT_LEGACY_CSOCR_REMOVED=1 EXPECT_OCR_KEY_REMOVED=0 TEXTBOOM_ARM64_LIBS_EXPECTED=0 TEXTBOOM_PRIMARY_CPU_ABI=armeabi-v7a RESULT_READ_ONLY=PASS_READ_ONLY_V043C_TEXTBOOM_FORCE_ARM32_ABI tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.43b ABI-control gate that removes APK-internal lib/arm64-v8a entries plus /system/app/TextBoom/lib/arm64 while retaining manifest ocr_key, CsOcr/Intsig deletion, and v0.42.2 PP-OCR preview-save behavior."
    ;;
  v0.43d|v0.43d-textboom-codepath-arm32-abi)
    variant="v0.43d-textboom-codepath-arm32-abi"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.43d-textboom-codepath-arm32-abi.sparse.img"
    image_hash="c9c2d6013a933f5fcf1374bcb0c1df6940c4110d3ae138192236cf5865801bc2"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.43d-textboom-codepath-arm32-abi"
    report_pattern="verify-v0.43d-textboom-codepath-arm32-abi-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V043D_TEXTBOOM_CODEPATH_ARM32_ABI'
    report_required_regex_extra='textboom-old-public-apk[[:space:]]+absent[[:space:]]+/system/app/TextBoom/TextBoom.apk'
    live_verify="VARIANT=v0.43d-textboom-codepath-arm32-abi NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom EXPECT_LEGACY_CSOCR_REMOVED=1 EXPECT_OCR_KEY_REMOVED=0 TEXTBOOM_ARM64_LIBS_EXPECTED=0 TEXTBOOM_PRIMARY_CPU_ABI=armeabi-v7a AUTO_DISMISS_KEYGUARD=1 RESULT_READ_ONLY=PASS_READ_ONLY_V043D_TEXTBOOM_CODEPATH_ARM32_ABI tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.43b-derived ABI-control gate that moves com.smartisanos.textboom from /system/app/TextBoom to /system/app/TextBoomArm32, hides the old public TextBoom.apk behind a non-.apk held path, removes arm64 libs, and asks PackageManager to rescan the same package from a fresh system codePath."
    ;;
  v0.43e|v0.43e-textboom-codepath-arm64-runtime-repair)
    variant="v0.43e-textboom-codepath-arm64-runtime-repair"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.43e-textboom-codepath-arm64-runtime-repair.sparse.img"
    image_hash="d646db5c6462a80735327a3ba8bda2acc60b540df18f150c2d2cf70320f40863"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.42-textboom-preview-path.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.43e-textboom-codepath-arm64-runtime-repair"
    report_pattern="verify-v0.43e-textboom-codepath-arm64-runtime-repair-offline-image-*.txt"
    report_required_regex='PASS_OFFLINE_IMAGE_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR'
    report_required_regex_extra='arm64-libopencv_java4\.so[[:space:]]+sha256=41b906e5a92bdde74c448fffcf71b8927ff77c0aa2f839d9a8e431feec985cc7'
    live_verify="VARIANT=v0.43e-textboom-codepath-arm64-runtime-repair NEW_OCR_DIR=/Android/media/com.smartisanos.textboom/.boom EXPECT_LEGACY_CSOCR_REMOVED=1 EXPECT_OCR_KEY_REMOVED=0 TEXTBOOM_ARM64_LIBS_EXPECTED=1 TEXTBOOM_APK_ARM64_LIBS_EXPECTED=0 TEXTBOOM_PRIMARY_CPU_ABI=arm64-v8a AUTO_DISMISS_KEYGUARD=1 RESULT_READ_ONLY=PASS_READ_ONLY_V043E_TEXTBOOM_CODEPATH_ARM64_RUNTIME_REPAIR tools/r2-verify-v0.42-textboom-preview-path.sh --read-only"
    gate_note="v0.43d repair candidate that keeps the new /system/app/TextBoomArm32 codePath, accepts PackageManager arm64-v8a, and restores arm64 ORT/OpenCV runtime libraries under /system/app/TextBoomArm32/lib/arm64 so BOOM_IMAGE can work again."
    ;;
  v0.pm0|v0.pm0-services-jar-noop)
    variant="v0.pm0-services-jar-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.pm0-services-jar-noop.sparse.img"
    image_hash="4834d9d233e7243f61211b81b73e15fb3f293d45d80fcecbc7612bad6c4cf1c7"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.pm0-services-jar-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.pm0-services-jar-noop"
    report_pattern="pack-super-v0.pm0-services-jar-noop-*.txt"
    report_required_regex='PASS_PACK_SUPER_V0PM0_SERVICES_JAR_NOOP'
    report_required_regex_extra='system_b[[:space:]]+8306688[[:space:]]+6217336[[:space:]]+3183276032[[:space:]]+e6341016f5f453f5734916c88fa3efaa51c937f9533f58b9e36cf36a3a43440e[[:space:]]+PASS'
    live_verify="tools/r2-verify-v0.pm0-services-jar-noop.sh --read-only"
    gate_note="PackageManager services.jar no-op framework boot gate on top of live-verified v0.43e; no real PMS behavior policy yet."
    ;;
  v0.pm1|v0.pm1-pms-cache-allowlist)
    variant="v0.pm1-pms-cache-allowlist"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.pm1-pms-cache-allowlist.sparse.img"
    image_hash="dd64f8a741dc434763bf6d9518bd0ee74c33cbcf3471121056883f591fc34f52"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.pm1-pms-cache-allowlist.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.pm1-pms-cache-allowlist"
    report_pattern="verify-v0.pm1-pms-cache-allowlist-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PM1_PMS_CACHE_ALLOWLIST'
    report_required_regex_extra='parallel_package_parser_policy_call=ok|pms_neighbor_classes_byte_identical_or_jumbo_equivalent=true'
    live_verify="tools/r2-verify-v0.pm1-pms-cache-allowlist.sh --read-only"
    gate_note="first narrow PackageManager behavior policy on top of live-proven v0.pm0; only allowlisted SmartisaxShell, TextBoomArm32/TextBoom, and Sidebar boot-scan paths bypass PackageParser cache reads."
    ;;
  v0.kg1|v0.kg1-smartisax-skip-keyguard)
    variant="v0.kg1-smartisax-skip-keyguard"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.kg1-smartisax-skip-keyguard.sparse.img"
    image_hash="450c5e1e34b20a7fd66422c96e359bf949e3968a62c3f6f73db81a229706518c"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.kg1-smartisax-skip-keyguard.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.kg1-smartisax-skip-keyguard"
    report_pattern="verify-v0.kg1-smartisax-skip-keyguard-offline-image-*.txt"
    report_required_regex='result=PASS_VERIFY_V0KG1_SMARTISAX_SKIP_KEYGUARD_OFFLINE_IMAGE'
    report_required_regex_extra='system_b[[:space:]]+image=fd88c39e3716dcd7f6d018b651ec69c3e2457995afb78a6bc6c5ae5a95c513b2[[:space:]]+sparse_slice=fd88c39e3716dcd7f6d018b651ec69c3e2457995afb78a6bc6c5ae5a95c513b2'
    live_verify="tools/r2-verify-v0.kg1-smartisax-skip-keyguard.sh --read-only"
    gate_note="Smartisax skip-keyguard behavior on top of live-proven v0.pm1; services.jar only, keeps pm1 PackageManager policy, and uses stock Keyguard setKeyguardEnabled(false) so secure keyguard/SIM PIN still refuse disabling."
    ;;
  v0.usb1|v0.usb1-no-smartisan-cdrom)
    variant="v0.usb1-no-smartisan-cdrom"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.usb1-no-smartisan-cdrom.sparse.img"
    image_hash="1608da03f036a4e9d4972d7c892fd018903e603a299040e5464a1512547829bc"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.usb1-no-smartisan-cdrom.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.usb1-no-smartisan-cdrom"
    report_pattern="verify-v0.usb1-no-smartisan-cdrom-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0USB1_NO_SMARTISAN_CDROM'
    report_required_regex_extra='vendor_usb_texts=ok|sparse_vendor_b_slice=ok'
    live_verify="tools/r2-verify-v0.usb1-no-smartisan-cdrom.sh --read-only"
    gate_note="vendor_b-only USB candidate on top of live-proven v0.kg1; keeps the ISO file inert, removes mass_storage.0 from active config symlinks, and preserves ADB/MTP paths."
    ;;
  v0.usb2|v0.usb2-physical-cdrom-iso-delete)
    variant="v0.usb2-physical-cdrom-iso-delete"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.usb2-physical-cdrom-iso-delete.sparse.img"
    image_hash="239b95b7ebbb467858c40b8e40a268cb1d83be145f5e9cddd8e2dc66a78153d0"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.usb2-physical-cdrom-iso-delete.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.usb2-physical-cdrom-iso-delete"
    report_pattern="verify-v0.usb2-physical-cdrom-iso-delete-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0USB2_PHYSICAL_CDROM_ISO_DELETE'
    report_required_regex_extra='cdrom_iso_absent=ok|cdrom_payload_strings=absent|sparse_vendor_b_slice=ok'
    live_verify="tools/r2-verify-v0.usb2-physical-cdrom-iso-delete.sh --read-only"
    gate_note="vendor_b-only physical cleanup on top of live-proven v0.usb1; removes /vendor/etc/cdrom_install.iso, zeroes old ISO blocks that remain free after deletion, preserves one reassigned shared block, and keeps ADB/MTP USB text."
    ;;
  v0.wadb1|v0.wadb1-smartisax-priv-wireless-adb)
    variant="v0.wadb1-smartisax-priv-wireless-adb"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.wadb1-smartisax-priv-wireless-adb.sparse.img"
    image_hash="12e0a42afe1a39fa63948568a7bce84804052019584eaacb46b37151c6ae18cc"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.wadb1-smartisax-priv-wireless-adb.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.wadb1-smartisax-priv-wireless-adb"
    report_pattern="verify-v0.wadb1-smartisax-priv-wireless-adb-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0WADB1_SMARTISAX_PRIV_WIRELESS_ADB'
    report_required_regex_extra='smartisax_apk_semantics=ok|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.wadb1-smartisax-priv-wireless-adb.sh --read-only"
    gate_note="Smartisax priv-app promotion on top of live-proven v0.usb2; moves com.smartisax.browser from /system/app to /system/priv-app, adds privapp permissions for MANAGE_DEBUGGING/WRITE_SECURE_SETTINGS, and exposes a guarded wireless ADB control entry."
    ;;
  v0.wadb2|v0.wadb2-smartisax-wireless-adb-current-wifi)
    variant="v0.wadb2-smartisax-wireless-adb-current-wifi"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.wadb2-smartisax-wireless-adb-current-wifi.sparse.img"
    image_hash="a542b056b356112d8a5e8a5cc2ba90103d07c3f72f82ece6d9ff028cd676144a"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.wadb2-smartisax-wireless-adb-current-wifi.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.wadb2-smartisax-wireless-adb-current-wifi"
    report_pattern="verify-v0.wadb2-smartisax-wireless-adb-current-wifi-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0WADB2_SMARTISAX_WIRELESS_ADB_CURRENT_WIFI'
    report_required_regex_extra='smartisax_services_current_wifi_policy=ok|smartisax_apk_semantics=ok|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.wadb2-smartisax-wireless-adb-current-wifi.sh --read-only"
    gate_note="Wireless ADB repair on top of live-proven v0.wadb1; Smartisax sends a current-Wi-Fi sentinel and services.jar resolves it inside system_server before calling addTrustedNetwork."
    ;;
  v0.wadb2.1|v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache)
    variant="v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache.sparse.img"
    image_hash="a2c9ed0d1ff66ab14827154f7347c91c30d3701136c02279649c70ccff09f4c7"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache"
    report_pattern="verify-v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0WADB21_SMARTISAX_WIRELESS_ADB_REFLECTION_PMCACHE'
    report_required_regex_extra='smartisax_privapp_cache_bypass=ok|smartisax_apk_semantics=ok|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.wadb2.1-smartisax-wireless-adb-reflection-pmcache.sh --read-only"
    gate_note="Repair candidate on top of live-tested v0.wadb2; fixes Smartisax IAdbManager hidden-API reflection with getDeclaredMethod/setAccessible and extends PackageManager cache bypass to /system/priv-app/SmartisaxShell."
    ;;
  v0.wadb2.2|v0.wadb2.2-smartisax-wireless-adb-binder-transact)
    variant="v0.wadb2.2-smartisax-wireless-adb-binder-transact"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.wadb2.2-smartisax-wireless-adb-binder-transact.sparse.img"
    image_hash="231b064ad45804483654a3ae4d629e83952f0518c941d9de4366fa3c1a7fdb01"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.wadb2.2-smartisax-wireless-adb-binder-transact.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.wadb2.2-smartisax-wireless-adb-binder-transact"
    report_pattern="verify-v0.wadb2.2-smartisax-wireless-adb-binder-transact-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0WADB22_SMARTISAX_WIRELESS_ADB_BINDER_TRANSACT'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_privapp_cache_bypass=ok|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.wadb2.2-smartisax-wireless-adb-binder-transact.sh --read-only"
    gate_note="APK-only repair on top of v0.wadb2.1; Smartisax v0.2.3/versionCode 5 calls the adb service through raw Binder transact 4/5/10, while services.jar stays at the v0.wadb2.1 current-Wi-Fi plus priv-app cache policy."
    ;;
  v0.portal1|v0.portal1-smartisax-lan-portal-noop)
    variant="v0.portal1-smartisax-lan-portal-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal1-smartisax-lan-portal-noop.sparse.img"
    image_hash="8af6630b1911e9c697b02b4cca458f0d6609f8900046063c4372494d4a1ddd76"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal1-smartisax-lan-portal-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal1-smartisax-lan-portal-noop"
    report_pattern="verify-v0.portal1-smartisax-lan-portal-noop-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL1_SMARTISAX_LAN_PORTAL_NOOP'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_services_current_wifi_policy=ok|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal1-smartisax-lan-portal-noop.sh --read-only"
    gate_note="Smartisax v0.3.0/versionCode 6 LAN Device Portal noop on top of live-proven v0.wadb2.2; services.jar retained, portal exposes only pairing/status in this gate."
    ;;
  v0.portal2|v0.portal2-smartisax-remote-screen-control)
    variant="v0.portal2-smartisax-remote-screen-control"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal2-smartisax-remote-screen-control.sparse.img"
    image_hash="24a2955b962595509e6799d79da299b068480815e81ddffa2a221b77a71a2cbc"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal2-smartisax-remote-screen-control.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal2-smartisax-remote-screen-control"
    report_pattern="verify-v0.portal2-smartisax-remote-screen-control-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL2_SMARTISAX_REMOTE_SCREEN_CONTROL'
    report_required_regex_extra='smartisax_apk_semantics=ok|root-screencap-png|root-input-command|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal2-smartisax-remote-screen-control.sh --read-only"
    gate_note="Smartisax v0.4.0/versionCode 7 on top of live-proven v0.portal1; adds token-gated /api/screen.png PNG stream and /api/input tap/swipe control while retaining services.jar and portal pairing boundaries."
    ;;
  v0.portal2.1|v0.portal2.1-smartisax-remote-screen-control-privapi)
    variant="v0.portal2.1-smartisax-remote-screen-control-privapi"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal2.1-smartisax-remote-screen-control-privapi.sparse.img"
    image_hash="5a236cd8a63f4a2734a80efa5fbf733f8557371d97c3c0086a0a7be72279667e"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal2.1-smartisax-remote-screen-control-privapi.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal2.1-smartisax-remote-screen-control-privapi"
    report_pattern="verify-v0.portal2.1-smartisax-remote-screen-control-privapi-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL21_SMARTISAX_REMOTE_SCREEN_CONTROL_PRIVAPI'
    report_required_regex_extra='smartisax_apk_semantics=ok|privileged-surfacecontrol-png|privileged-inputmanager|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal2.1-smartisax-remote-screen-control-privapi.sh --read-only"
    gate_note="Smartisax v0.4.1/versionCode 8 repair on top of v0.portal2; replaces app-internal kp screen/input calls with privileged SurfaceControl screenshot and InputManager injection APIs plus privapp permissions."
    ;;
  v0.portal2.2|v0.portal2.2-smartisax-remote-screen-control-bufferfix)
    variant="v0.portal2.2-smartisax-remote-screen-control-bufferfix"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal2.2-smartisax-remote-screen-control-bufferfix.sparse.img"
    image_hash="ae537afb619ff50b89885a06c9bfd623900f6e518ecfa1a6ad869b7ab19b8a2f"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal2.2-smartisax-remote-screen-control-bufferfix.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal2.2-smartisax-remote-screen-control-bufferfix"
    report_pattern="verify-v0.portal2.2-smartisax-remote-screen-control-bufferfix-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL22_SMARTISAX_REMOTE_SCREEN_CONTROL_BUFFERFIX'
    report_required_regex_extra='smartisax_apk_semantics=ok|wrapHardwareBuffer|privileged-inputmanager|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal2.2-smartisax-remote-screen-control-bufferfix.sh --read-only"
    gate_note="Smartisax v0.4.2/versionCode 9 repair on top of v0.portal2.1; keeps working privileged input and converts SurfaceControl ScreenshotGraphicBuffer results to Bitmap for /api/screen.png."
    ;;
  v0.portal2.3|v0.portal2.3-smartisax-framebuffer-grant)
    variant="v0.portal2.3-smartisax-framebuffer-grant"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal2.3-smartisax-framebuffer-grant.sparse.img"
    image_hash="500b37a0e080b94dc50ae6d59c8265982998e4e6e8a3f98301e34472c347ef4b"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal2.3-smartisax-framebuffer-grant.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal2.3-smartisax-framebuffer-grant"
    report_pattern="verify-v0.portal2.3-smartisax-framebuffer-grant-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL23_SMARTISAX_FRAMEBUFFER_GRANT'
    report_required_regex_extra='smartisax_signature_permission_policy=ok|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal2.3-smartisax-framebuffer-grant.sh --read-only"
    gate_note="Narrow services.jar PackageManager policy on top of v0.portal2.2; grants only android.permission.READ_FRAME_BUFFER to com.smartisax.browser so the LAN portal SurfaceControl screenshot path can be tested without broad signature-permission bypass."
    ;;
  v0.portal3a|v0.portal3a-webrtc-capability-probe)
    variant="v0.portal3a-webrtc-capability-probe"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal3a-webrtc-capability-probe.sparse.img"
    image_hash="5f399322d4e5955edaeb4d1114b2e43384c86f45645e225c8873010fd435b820"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal3a-webrtc-capability-probe.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal3a-webrtc-capability-probe"
    report_pattern="verify-v0.portal3a-webrtc-capability-probe-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL3A_WEBRTC_CAPABILITY_PROBE'
    report_required_regex_extra='smartisax_apk_semantics=ok|/api/media/capabilities|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal3a-webrtc-capability-probe.sh --read-only"
    gate_note="Smartisax v0.5.0/versionCode 10 on top of live-proven v0.portal2.3; keeps PNG screen/input and framebuffer services.jar policy, adds token-gated /api/media/capabilities plus browser-side WebRTC/WebCodecs capability probe."
    ;;
  v0.portal3b|v0.portal3b-h264-http-stream-prototype)
    variant="v0.portal3b-h264-http-stream-prototype"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal3b-h264-http-stream-prototype.sparse.img"
    image_hash="6ca5e87676adebcfcf1cee26ad13403617bd40a7db4509bf84459adf88b22e07"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal3b-h264-http-stream-prototype.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal3b-h264-http-stream-prototype"
    report_pattern="verify-v0.portal3b-h264-http-stream-prototype-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL3B_H264_HTTP_STREAM_PROTOTYPE'
    report_required_regex_extra='smartisax_apk_semantics=ok|/api/video/h264|h264-http-prototype|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal3b-h264-http-stream-prototype.sh --read-only"
    gate_note="Smartisax v0.5.1/versionCode 11 on top of live-proven v0.portal3a; keeps PNG screen/input and framebuffer services.jar policy, adds token-gated /api/video/h264 H.264 Annex-B stream prototype."
    ;;
  v0.portal3c|v0.portal3c-h264-webcodecs-playback)
    variant="v0.portal3c-h264-webcodecs-playback"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal3c-h264-webcodecs-playback.sparse.img"
    image_hash="41f15da085dcbe272c990ccfff046931fd7adc00f31215e413a4d8267255827c"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal3c-h264-webcodecs-playback.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal3c-h264-webcodecs-playback"
    report_pattern="verify-v0.portal3c-h264-webcodecs-playback-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL3C_H264_WEBCODECS_PLAYBACK'
    report_required_regex_extra='smartisax_apk_semantics=ok|mp4-video-element|h264-mp4-browser-playback|MediaMuxer|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal3c-h264-webcodecs-playback.sh --read-only"
    gate_note="Smartisax v0.5.2/versionCode 12 on top of live-proven v0.portal3b; keeps PNG screen/input and framebuffer services.jar policy, moves the Portal page to an APK asset, adds /api/video/mp4 for direct-LAN HTTP browser playback, and keeps /api/video/h264 as raw stream plus WebCodecs diagnostic input."
    ;;
  v0.portal4a|v0.portal4a-webrtc-rtp-probe)
    variant="v0.portal4a-webrtc-rtp-probe"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal4a-webrtc-rtp-probe.sparse.img"
    image_hash="a1c24a085f604966ddd500a7cb88a26aad81697efc524fbe83d287fbb4243ae3"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal4a-webrtc-rtp-probe.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal4a-webrtc-rtp-probe"
    report_pattern="verify-v0.portal4a-webrtc-rtp-probe-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL4A_WEBRTC_RTP_PROBE'
    report_required_regex_extra='smartisax_apk_semantics=ok|/api/webrtc/offer|/api/rtp/h264|signaling-rtp-probe|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal4a-webrtc-rtp-probe.sh --read-only"
    gate_note="Smartisax v0.5.3/versionCode 13 on top of live-proven v0.portal3c; keeps MP4 browser playback, raw H.264, PNG/input, and framebuffer services.jar policy, adds WebRTC offer and H.264 RTP packetizer probe endpoints."
    ;;
  v0.portal4b|v0.portal4b-mp4-control-polish)
    variant="v0.portal4b-mp4-control-polish"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal4b-mp4-control-polish.sparse.img"
    image_hash="2a1b702184d351dc5b74b139f1b2961fb429702d7f857865a07680b3277d9fa6"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal4b-mp4-control-polish.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal4b-mp4-control-polish"
    report_pattern="verify-v0.portal4b-mp4-control-polish-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL4B_MP4_CONTROL_POLISH'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal4b-mp4-control-polish.sh --read-only"
    gate_note="Smartisax v0.5.4/versionCode 14 on top of live-proven v0.portal4a; keeps WebRTC/RTP diagnostics and polishes direct-LAN Start Live MP4 loop playback, autoplay=live, pointer control, and live metrics."
    ;;
  v0.portal4c|v0.portal4c-session-hardening)
    variant="v0.portal4c-session-hardening"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal4c-session-hardening.sparse.img"
    image_hash="66693df65d84e4ef775ff5a2e8b364aa87a4bd6cb203934fa81226bf2146f672"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal4c-session-hardening.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal4c-session-hardening"
    report_pattern="verify-v0.portal4c-session-hardening-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL4C_SESSION_HARDENING'
    report_required_regex_extra='smartisax_apk_semantics=ok|bearer-token-pair-code-rotation|rotates-after-success|Content-Security-Policy|smartisax_signature_policy_scope=read_frame_buffer_only|sparse_system_b_slice=ok'
    live_verify="tools/r2-verify-v0.portal4c-session-hardening.sh --read-only"
    gate_note="Smartisax v0.5.5/versionCode 15 on top of live-proven v0.portal4b; keeps MP4/H.264/RTP/PNG/input diagnostics and hardens pairing/session behavior with code rotation, bad-pair lockout, session metadata, local-session clear UI, and security headers."
    ;;
  v0.portal5a|v0.portal5a-native-webrtc-runtime)
    variant="v0.portal5a-native-webrtc-runtime"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5a-native-webrtc-runtime.sparse.img"
    image_hash="c6b7f1d5605ff7e69a4d785bab91a10baa1af65d48b54d9c11bd9bb43061b814"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5a-native-webrtc-runtime"
    report_pattern="verify-v0.portal5a-native-webrtc-runtime-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5A_NATIVE_WEBRTC_RUNTIME'
    report_required_regex_extra='smartisax_apk_semantics=ok|native-libwebrtc-dtls-srtp-screen|PeerConnectionFactory|libjingle_peerconnection_so|system_b_avb_fec=ok'
    live_verify="tools/r2-verify-v0.portal5a-native-webrtc-runtime.sh --read-only"
    gate_note="Smartisax v0.6.0/versionCode 17 on top of live-proven v0.portal4c; adds io.github.webrtc-sdk Android libwebrtc, native PeerConnection answer generation, ICE/DTLS/SRTP markers, and a Java screenshot-to-I420 frame pump while retaining MP4/PNG/input fallbacks."
    ;;
  v0.portal5b|v0.portal5b-native-webrtc-system-libs)
    variant="v0.portal5b-native-webrtc-system-libs"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5b-native-webrtc-system-libs.sparse.img"
    image_hash="39b7d30bb628671f82a1bd358c44d71e2b675f5cac843ba690141f1ffd567544"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5b-native-webrtc-system-libs.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5b-native-webrtc-system-libs"
    report_pattern="verify-v0.portal5b-native-webrtc-system-libs-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5B_NATIVE_WEBRTC_SYSTEM_LIBS'
    report_required_regex_extra='smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5b-native-webrtc-system-libs.sh --read-only"
    gate_note="Smartisax v0.6.0/versionCode 17 on top of v0.portal5a; repairs native libwebrtc loading by installing libjingle_peerconnection_so.so under /system/priv-app/SmartisaxShell/lib/arm64 and lib/arm while retaining APK, permissions, services.jar, and Portal behavior."
    ;;
  v0.portal5c|v0.portal5c-webrtc-software-bitmap-frames)
    variant="v0.portal5c-webrtc-software-bitmap-frames"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5c-webrtc-software-bitmap-frames.sparse.img"
    image_hash="429816c1ebf2d8e0ea3e152d6b7a7d1d19dcddc9c12049ad990eff07c19652c9"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5c-webrtc-software-bitmap-frames.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5c-webrtc-software-bitmap-frames"
    report_pattern="verify-v0.portal5c-webrtc-software-bitmap-frames-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5C_WEBRTC_SOFTWARE_BITMAP_FRAMES'
    report_required_regex_extra='smartisax_system_webrtc_libs=ok|smartisax_apk_semantics=ok'
    live_verify="tools/r2-verify-v0.portal5c-webrtc-software-bitmap-frames.sh --read-only"
    gate_note="Smartisax v0.6.1/versionCode 18 on top of v0.portal5b; keeps external libwebrtc system libraries and repairs the WebRTC screen frame pump by converting SurfaceControl HARDWARE bitmaps to readable ARGB_8888 software bitmaps before I420 conversion."
    ;;
  v0.portal5d|v0.portal5d-webrtc-bitmap-copy-frames)
    variant="v0.portal5d-webrtc-bitmap-copy-frames"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5d-webrtc-bitmap-copy-frames.sparse.img"
    image_hash="c6e1d7107bce64fa647786aa8838a3e13f5996ac105494ee14a7666be31a71be"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5d-webrtc-bitmap-copy-frames.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5d-webrtc-bitmap-copy-frames"
    report_pattern="verify-v0.portal5d-webrtc-bitmap-copy-frames-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5D_WEBRTC_BITMAP_COPY_FRAMES'
    report_required_regex_extra='smartisax_system_webrtc_libs=ok|smartisax_apk_semantics=ok'
    live_verify="tools/r2-verify-v0.portal5d-webrtc-bitmap-copy-frames.sh --read-only"
    gate_note="Smartisax v0.6.2/versionCode 19 on top of v0.portal5c; keeps external libwebrtc system libraries and repairs the WebRTC screen frame pump by using Bitmap.copy(ARGB_8888,false), the same HARDWARE bitmap conversion route already proven by PNG/MP4."
    ;;
  v0.portal5e|v0.portal5e-webrtc-h264-session-control)
    variant="v0.portal5e-webrtc-h264-session-control"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5e-webrtc-h264-session-control.sparse.img"
    image_hash="d495f67bd1a342ae9ff063e8ffaa5730f5f041cb0dae45e5e9166ccf1cfe8666"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5e-webrtc-h264-session-control.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5e-webrtc-h264-session-control"
    report_pattern="verify-v0.portal5e-webrtc-h264-session-control-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5E_WEBRTC_H264_SESSION_CONTROL'
    report_required_regex_extra='smartisax_system_webrtc_libs=ok|smartisax_apk_semantics=ok'
    live_verify="tools/r2-verify-v0.portal5e-webrtc-h264-session-control.sh --read-only"
    gate_note="Smartisax v0.6.3/versionCode 20 on top of v0.portal5d; keeps Bitmap.copy frame pump and external libwebrtc system libraries while making Portal browser WebRTC prefer H264 and adding native WebRTC session status/cleanup APIs."
    ;;
  v0.portal5f|v0.portal5f-webrtc-datachannel-input)
    variant="v0.portal5f-webrtc-datachannel-input"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5f-webrtc-datachannel-input.sparse.img"
    image_hash="b3b633b97f218a713dd09980b85a8d566914c4ac604121214e1961e2b40a93a0"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5f-webrtc-datachannel-input.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5f-webrtc-datachannel-input"
    report_pattern="verify-v0.portal5f-webrtc-datachannel-input-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5F_WEBRTC_DATACHANNEL_INPUT'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5f-webrtc-datachannel-input.sh --read-only"
    gate_note="Smartisax v0.6.4/versionCode 21 on top of v0.portal5e; removes token-gated HTTP /api/input and moves Portal remote control into the WebRTC smartisax-input RTCDataChannel while retaining default H264/session cleanup."
    ;;
  v0.portal5g|v0.portal5g-webrtc-touch-quality)
    variant="v0.portal5g-webrtc-touch-quality"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5g-webrtc-touch-quality.sparse.img"
    image_hash="cbe9d5ff93fcf1ab492dbf0a86ee3524daad72ec320f60c30a8588cb1db00cb0"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5g-webrtc-touch-quality.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5g-webrtc-touch-quality"
    report_pattern="verify-v0.portal5g-webrtc-touch-quality-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5G_WEBRTC_TOUCH_QUALITY'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5g-webrtc-touch-quality.sh --read-only"
    gate_note="Smartisax v0.6.5/versionCode 22 on top of v0.portal5f; maps transparent touch overlay events to real display coordinates over smartisax-input RTCDataChannel and raises native WebRTC frame-pump defaults to 540px portrait width at 8fps."
    ;;
  v0.portal5h|v0.portal5h-webrtc-bitrate-quality)
    variant="v0.portal5h-webrtc-bitrate-quality"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5h-webrtc-bitrate-quality.sparse.img"
    image_hash="9d193755098feb70e283b445aa741412ce35017e28b12931be42015d045a17bd"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5h-webrtc-bitrate-quality.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5h-webrtc-bitrate-quality"
    report_pattern="verify-v0.portal5h-webrtc-bitrate-quality-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5H_WEBRTC_BITRATE_QUALITY'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5h-webrtc-bitrate-quality.sh --read-only"
    gate_note="Smartisax v0.6.6/versionCode 23 on top of v0.portal5g; keeps DataChannel tap/swipe and 540x1170@8fps frame pump, removes visible legacy transport choices from the Portal UI, defaults pairing/status recovery to native WebRTC, and sets explicit H264 sender bitrate parameters at 1.2Mbps target."
    ;;
  v0.portal5i|v0.portal5i-webrtc-runtime-tuning)
    variant="v0.portal5i-webrtc-runtime-tuning"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5i-webrtc-runtime-tuning.sparse.img"
    image_hash="7461215ef7403d005be3fe3c13ec711e9129998d28f11736fd3e1474e304aaf7"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5i-webrtc-runtime-tuning.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5i-webrtc-runtime-tuning"
    report_pattern="verify-v0.portal5i-webrtc-runtime-tuning-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5I_WEBRTC_RUNTIME_TUNING'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5i-webrtc-runtime-tuning.sh --read-only"
    gate_note="Smartisax v0.6.7/versionCode 24 on top of v0.portal5h; keeps WebRTC-only Portal UI and DataChannel control, adds token-gated /api/webrtc/config, and exposes runtime width/fps/bitrate tuning with stable defaults and an upper bound of 1080p/30fps."
    ;;
  v0.portal5j|v0.portal5j-projection-texture-probe)
    variant="v0.portal5j-projection-texture-probe"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5j-projection-texture-probe.sparse.img"
    image_hash="d51213324cebd9eca4b7dec58a509618949ebc598dcefa9aff6481f2e2921f28"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5j-projection-texture-probe.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5j-projection-texture-probe"
    report_pattern="verify-v0.portal5j-projection-texture-probe-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5J_PROJECTION_TEXTURE_PROBE'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_privapp_xml=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5j-projection-texture-probe.sh --read-only"
    gate_note="Smartisax v0.6.8/versionCode 25 on top of v0.portal5i; adds MediaProjection/VirtualDisplay/SurfaceTextureHelper capture probe, exposes /api/webrtc/capture/probe, raises runtime WebRTC tuning to 1080p/60fps, and keeps Bitmap/I420 as projection-auto fallback."
    ;;
  v0.portal5j.1|v0.portal5j.1-projection-permission-grant)
    variant="v0.portal5j.1-projection-permission-grant"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5j.1-projection-permission-grant.sparse.img"
    image_hash="3a89aca9fb029cc8cddfeba78d163ad533a6578ae13b8c229e54f11daafa39bc"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5j.1-projection-permission-grant.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5j.1-projection-permission-grant"
    report_pattern="verify-v0.portal5j.1-projection-permission-grant-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5J1_PROJECTION_PERMISSION_GRANT'
    report_required_regex_extra='smartisax_projection_permission_policy=ok|smartisax_privapp_xml=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5j.1-projection-permission-grant.sh --read-only"
    gate_note="Smartisax v0.6.8/versionCode 25 on top of v0.portal5j; keeps the projection texture probe APK unchanged and repairs services.jar policy to grant CAPTURE_VIDEO_OUTPUT/MANAGE_MEDIA_PROJECTION only to com.smartisax.browser."
    ;;
  v0.portal5j.2|v0.portal5j.2-projection-binder-transact)
    variant="v0.portal5j.2-projection-binder-transact"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.portal5j.2-projection-binder-transact.sparse.img"
    image_hash="789bb849e7bc849271958b3b6dd6e01a7c707d06373f6d4d72e88564acd83b66"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.portal5j.2-projection-binder-transact.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.portal5j.2-projection-binder-transact"
    report_pattern="verify-v0.portal5j.2-projection-binder-transact-offline-image-*.txt"
    report_required_regex='result=PASS_OFFLINE_IMAGE_V0PORTAL5J2_PROJECTION_BINDER_TRANSACT'
    report_required_regex_extra='smartisax_apk_semantics=ok|smartisax_projection_permission_policy=ok|smartisax_system_webrtc_libs=ok'
    live_verify="tools/r2-verify-v0.portal5j.2-projection-binder-transact.sh --read-only"
    gate_note="Smartisax v0.6.9/versionCode 26 on top of v0.portal5j.1; keeps the Smartisax-only services.jar MediaProjection permission policy and replaces blocked IMediaProjectionManager Stub reflection with raw Binder transact token creation."
    ;;
  v0.36|v0.36-smartisax-shell-debloat)
    die "v0.36 is retired: it flashed and booted but Smartisax failed Android 11 target R+ resources.arsc alignment parsing. Use v0.36.1-smartisax-shell-debloat-arsc-align."
    ;;
  v0.6|v0.6-settings-noop)
    variant="v0.6-settings-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.6-settings-noop-exact-current.sparse.img"
    image_hash="a06c2e81862c837bef53a4dc2f67c5dea7f0acf78dc7fbbecb6ae4ece26483db"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.6-settings-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/settingssmartisan-offline"
    report_pattern="verify-settingssmartisan-offline-*.txt"
    report_required_regex='PASS'
    live_verify="tools/r2-verify-v0.6-settings-noop.sh --read-only"
    gate_note="SettingsSmartisan original-cert-preserving no-op gate before Settings behavior patches"
    ;;
  v0.25|v0.25-settings-noop|v0.25-settings-noop-on-v0.24)
    variant="v0.25-settings-noop-on-v0.24"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.25-settings-noop-on-v0.24-exact-current.sparse.img"
    image_hash="09fdd9c0ffe6184623938356ce2b837751079963c2d98990434eb708ecf69d88"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.6-settings-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/settingssmartisan-offline"
    report_pattern="verify-settingssmartisan-offline-*.txt"
    report_required_regex='system_b[[:space:]]+image=ae6870e3d1109673fea6c8857d1c00bbf2866926d772e9bebb6218be1d4e4bbb[[:space:]]+sparse_slice=ae6870e3d1109673fea6c8857d1c00bbf2866926d772e9bebb6218be1d4e4bbb'
    live_verify="SETTINGS_NOOP_VARIANT=v0.25-settings-noop-on-v0.24 tools/r2-verify-v0.6-settings-noop.sh --read-only"
    gate_note="current v0.24-baseline SettingsSmartisan original-cert-preserving no-op gate before Settings/dark-mode behavior patches"
    ;;
  v0.24|v0.24-cleaner|v0.24-cleaner-apk-only-locale-prune)
    variant="v0.24-cleaner-apk-only-locale-prune"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.24-cleaner-apk-only-locale-prune-exact-current.sparse.img"
    image_hash="d3adbd29931a9a64f39c4f0cf57646736305ff839ff518369b835e89d1436b4e"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.24-cleaner-apk-only-locale-prune"
    report_pattern="verify-v0.24-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6[[:space:]]+sparse_slice=4152f6c00d482b4d082f457831856f437b4afffccba112510ceed72d205d82c6'
    live_verify="tools/r2-verify-v0.24-cleaner-apk-only-locale-prune.sh --read-only"
    gate_note="latest combined eleven APK-only language resource-prune candidate; offline proof only until flashed and boot-verified"
    ;;
  v0.22|v0.22-all|v0.22-all-apk-only-locale-prune)
    variant="v0.22-all-apk-only-locale-prune"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.22-all-apk-only-locale-prune-exact-current.sparse.img"
    image_hash="bd1670d117b124aa70220068a031b2a608b2373fab149da5020b1a71bc312e86"
    verifier="${ROOT_DIR}/tools/r2-verify-v0.22-all-apk-only-locale-prune.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/v0.22-all-apk-only-locale-prune"
    report_pattern="verify-v0.22-all-offline-image-*.txt"
    report_required_regex='system_b[[:space:]]+image=ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316[[:space:]]+sparse_slice=ead66283f4273d1f0513d9daf3497028aaab5767a9d24041c58c61ff8e598316'
    live_verify="tools/r2-language-live-state-audit.sh"
    gate_note="combined ten APK-only language resource-prune candidate; offline proof only until flashed and boot-verified"
    ;;
  systemui-v0.24|systemui-certprobe-noop-on-v0.24)
    variant="systemui-certprobe-noop-on-v0.24"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-systemui-certprobe-noop-on-v0.24-exact-current.sparse.img"
    image_hash="0749a4f19c34fa4bc89bcf1ed9a65fe027fce32479ae9b37be7a40e7a9895bfc"
    verifier="${ROOT_DIR}/tools/r2-verify-systemui-certprobe-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/systemui-certprobe-noop-on-v0.24"
    report_pattern="verify-systemui-certprobe-noop-on-v0.24-offline-*.txt"
    report_required_regex='system_ext_b[[:space:]]+image=133655b1b88440d942d473b1f14971acf657b379540fa12ca8fd5efe9c3d8f32[[:space:]]+sparse_slice=133655b1b88440d942d473b1f14971acf657b379540fa12ca8fd5efe9c3d8f32'
    live_verify="SYSTEMUI_NOOP_VARIANT=systemui-certprobe-noop-on-v0.24 tools/r2-verify-systemui-certprobe-noop.sh --read-only"
    gate_note="current v0.24-baseline SmartisanSystemUI original-cert-readable no-op gate before native toggleDarkMode SystemUI patches"
    ;;
  systemui|systemui-certprobe-noop)
    variant="systemui-certprobe-noop"
    image="${ROOT_DIR}/hard-rom/build/super-otatrust-systemui-certprobe-noop-exact-current.sparse.img"
    image_hash="836e8e7d2377580dc6237b617471084710d6b90c649f764b5f09681fd459cc60"
    verifier="${ROOT_DIR}/tools/r2-verify-systemui-certprobe-noop.sh"
    report_dir="${ROOT_DIR}/hard-rom/inspect/systemui-certprobe-noop"
    report_pattern="verify-systemui-certprobe-noop-offline-*.txt"
    report_required_regex='PASS'
    live_verify="tools/r2-verify-systemui-certprobe-noop.sh --read-only"
    gate_note="SmartisanSystemUI no-op gate before native toggleDarkMode SystemUI patches"
    ;;
  *)
    usage >&2
    die "unknown variant: ${variant}"
    ;;
esac

rollback="${ROOT_DIR}/hard-rom/build/super-otatrust-v0.4-debloat-exact-current.sparse.img"
rollback_hash="313ec839f962a6ed5fddadc8c2180f40912b86da4c40f27f90bcb75e2fd4bfc5"

echo "# R2 live flash preflight"
echo "variant=${variant}"
echo "serial=${SERIAL}"
echo "gate=${gate_note}"
echo

echo "## local image gates"
check_hash "candidate sparse" "$image" "$image_hash"
check_hash "rollback sparse" "$rollback" "$rollback_hash"
need_executable "$verifier"
printf 'OK   %-22s %s\n' "verifier" "$verifier"
check_report "$variant" "$report_dir" "$report_pattern" "$report_required_regex"

print_device_state

echo
echo "## explicit-confirmation boundary"
cat <<EOF
This script did not flash, reboot, erase misc, or change /data.

If this is the exact variant you want to test, the required confirmation is:

  确认刷入 ${variant} B 槽

After a confirmed flash and boot, run:

  ${live_verify}

Rollback image ready:

  fastboot -s ${SERIAL} flash super ${rollback#${ROOT_DIR}/}
  fastboot -s ${SERIAL} erase misc
  fastboot -s ${SERIAL} reboot
EOF
