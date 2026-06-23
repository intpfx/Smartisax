# Smartisax Keyguard Skip Design

Date: 2026-06-22.

## Goal

After flashing a new hard-ROM candidate, the R2 should boot straight into the
current Smartisax Home surface when no secure lock credential is configured.
The goal is not to bypass a password, SIM PIN, or other secure keyguard state.

## Source Findings

Live state before the candidate:

```text
slot=_b
boot=1
ro.screenlock=
secure lockscreen.disabled=0
cmd lock_settings get-disabled=false
mCurrentFocus=Keyguard
mFocusedApp=com.smartisax.browser/.ShellActivity
isKeyguardShowing=true
```

Static anchors:

```text
KeyguardSmartisan/KeyguardViewMediator.doLock()
  skips showLocked() when LockPatternUtils.isLockScreenDisabled() is true
  and the SIM is not locked or missing.

KeyguardSmartisan/KeyguardViewMediator.setKeyguardEnabled(false)
  refuses to disable Keyguard when isSecure() is true.
  Otherwise it hides the current Keyguard and sets mExternallyEnabled=false.

services.jar/KeyguardServiceDelegate$1.onServiceConnected()
  replays Keyguard lifecycle state after binding KeyguardServiceWrapper.
  It already calls setKeyguardEnabled(state.enabled) when state.enabled=false.
```

## Chosen Route

Use a services.jar-only policy on top of live-proven
`v0.pm1-pms-cache-allowlist`:

```text
variant: v0.kg1-smartisax-skip-keyguard
helper: com.android.server.policy.keyguard.SmartisaxKeyguardPolicy
switch: persist.smartisax.skip_keyguard, default true
hook: KeyguardServiceDelegate$1.onServiceConnected()
behavior:
  if the policy returns true, set KeyguardState.enabled=false.
  Then let the existing stock code call KeyguardServiceWrapper.setKeyguardEnabled(false).
```

This keeps the stock Smartisan security guard in
`KeyguardViewMediator.setKeyguardEnabled(false)`: secure keyguard and SIM PIN
states still refuse disabling.

## Offline Evidence

services.jar candidate:

```text
path:
  hard-rom/build/framework/services-kg1-smartisax-skip-keyguard.jar
sha256:
  0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6
base:
  hard-rom/build/framework/services-pm1-cache-allowlist.jar
base sha256:
  84b3f17f6fae929c824310b684da5291ac3388028d0e9b054f8cab1252d38e40
changed entries:
  classes2.dex
report:
  hard-rom/inspect/v0.kg1-smartisax-skip-keyguard/services-kg1-smartisax-skip-keyguard-report.txt
```

system/super candidate:

```text
system_b:
  hard-rom/build/system-otatrust-v0.kg1-smartisax-skip-keyguard.img
system_b sha256:
  fd88c39e3716dcd7f6d018b651ec69c3e2457995afb78a6bc6c5ae5a95c513b2
super sparse:
  hard-rom/build/super-otatrust-v0.kg1-smartisax-skip-keyguard.sparse.img
super sparse sha256:
  450c5e1e34b20a7fd66422c96e359bf949e3968a62c3f6f73db81a229706518c
offline verifier:
  result=PASS_VERIFY_V0KG1_SMARTISAX_SKIP_KEYGUARD_OFFLINE_IMAGE
  hard-rom/inspect/v0.kg1-smartisax-skip-keyguard/verify-v0.kg1-smartisax-skip-keyguard-offline-image-20260622-151324.txt
```

The verifier proves:

```text
system_b AVB/FEC roots=2 OK
e2fsck OK
/system/framework/services.jar hash matches the kg1 jar
public services.art/odex/vdex absent
pm1 SmartisaxPackagePolicy retained
kg1 SmartisaxKeyguardPolicy present
KeyguardServiceDelegate$1.onServiceConnected hook present
sparse system_b slice hash equals the system_b image hash
```

## Live Status

Live PASS on B slot.

The first attempt to run live preflight with escalated USB/ADB access was
blocked by the Codex approval layer because the then-current access token
refresh failed. After authorization recovered, the normal preflight/flash/live
verification loop completed without using the sandbox as a USB workaround.

Saved evidence:

```text
postflash preflight:
  hard-rom/inspect/v0.kg1-smartisax-skip-keyguard/preflight-v0.kg1-smartisax-skip-keyguard-20260622-1533-postflash-readonly.txt
flash:
  hard-rom/inspect/v0.kg1-smartisax-skip-keyguard/flash-v0.kg1-smartisax-skip-keyguard-20260622-152721.txt
read-only verifier:
  hard-rom/inspect/v0.kg1-smartisax-skip-keyguard/verify-v0.kg1-smartisax-skip-keyguard-device-read-only-20260622-153204.txt
result:
  PASS_READ_ONLY_V0KG1_SMARTISAX_SKIP_KEYGUARD
```

Live verifier proof:

```text
sys.boot_completed=1
ro.boot.slot_suffix=_b
init.svc.bootanim=stopped
/system/framework/services.jar sha256=0f8991d4f9d7f0bf65407d62c180a8e98852135584f05cda5a57cba955fae9b6
mCurrentFocus=com.smartisax.browser/com.smartisax.browser.ShellActivity
mFocusedApp=com.smartisax.browser/.ShellActivity
isKeyguardShowing=false
root uid=0
SELinux=Enforcing
```
