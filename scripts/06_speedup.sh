#!/usr/bin/env bash
# Perceived-speed work that needs no settings change:
#  1. force the background ART dexopt job now (recompiles apps with their usage profiles → faster launches)
#  2. trim app caches
#  3. clear the launcher / system_server memory pressure by killing cached processes once
# Does NOT touch refresh rate: peak_refresh_rate / min_refresh_rate are left exactly as set by the user.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
before="$(adb shell df /data | tail -1 | awk '{print $4}')"

log "Running ART background dexopt (this takes several minutes; keep the phone plugged in)"
out="$(adb shell pm art dexopt-packages -r bg-dexopt 2>&1 || true)"
if grep -qiE "error|unknown|usage" <<<"$out"; then
  adb shell cmd package bg-dexopt-job >/dev/null 2>&1 || warn "bg-dexopt-job could not be forced"
fi
log "Compiling launcher and SystemUI with speed profile"
for p in com.nothing.launcher com.android.systemui; do
  adb shell pm compile -m speed-profile -f "$p" >/dev/null 2>&1 || true
done

log "Trimming app caches"
adb shell pm trim-caches 999G >/dev/null 2>&1 || true
after="$(adb shell df /data | tail -1 | awk '{print $4}')"

log "Trimming the filesystem (discard unused flash blocks; keeps write speed up)"
adb shell sm fstrim >/dev/null 2>&1 || true

log "Dropping cached background processes once"
adb shell am kill-all >/dev/null 2>&1 || true

log "Done. /data free before: $before  after: $after"
log "Refresh rate untouched: peak=$(setting_get system peak_refresh_rate) min=$(setting_get system min_refresh_rate)"
