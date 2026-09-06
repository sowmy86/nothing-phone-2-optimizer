#!/usr/bin/env bash
# Snapshot device state so before/after can be compared.
# Usage: scripts/00_baseline.sh [label]   (default label: timestamp)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
LABEL="${1:-$TS}"
OUT="$REPORTS/snapshot-$LABEL"
mkdir -p "$OUT"
log "Snapshotting $(device_model) into $OUT"

adb shell getprop                                 > "$OUT/getprop.txt"
adb shell pm list packages -f                     > "$OUT/packages_all.txt"
adb shell pm list packages -3                     > "$OUT/packages_third_party.txt"
adb shell pm list packages -s                     > "$OUT/packages_system.txt"
adb shell pm list packages -d                     > "$OUT/packages_disabled.txt"
adb shell pm list packages -U                     > "$OUT/packages_uid.txt"
adb shell dumpsys battery                         > "$OUT/battery.txt"
adb shell dumpsys batterystats --charged          > "$OUT/batterystats.txt" 2>&1 || true
adb shell settings list global                    > "$OUT/settings_global.txt"
adb shell settings list system                    > "$OUT/settings_system.txt"
adb shell settings list secure                    > "$OUT/settings_secure.txt"
adb shell dumpsys deviceidle                      > "$OUT/deviceidle.txt"
adb shell dumpsys deviceidle whitelist            > "$OUT/deviceidle_whitelist.txt"
adb shell dumpsys usagestats                      > "$OUT/usagestats.txt" 2>&1 || true
adb shell dumpsys alarm                           > "$OUT/alarms.txt"
adb shell dumpsys jobscheduler                    > "$OUT/jobscheduler.txt" 2>&1 || true
adb shell dumpsys meminfo                         > "$OUT/meminfo.txt"
adb shell cat /proc/meminfo                       > "$OUT/proc_meminfo.txt"
adb shell df -h                                   > "$OUT/storage.txt"
adb shell top -n 1 -b                             > "$OUT/top.txt" 2>&1 || true
adb shell am get-standby-bucket                   > "$OUT/standby_buckets.txt" 2>&1 || true
adb shell cmd appops query-op RUN_ANY_IN_BACKGROUND ignore > "$OUT/background_restricted.txt" 2>&1 || true
adb shell device_config list device_idle          > "$OUT/device_config_device_idle.txt" 2>&1 || true

log "Done. $(ls "$OUT" | wc -l | tr -d ' ') files captured."
echo "$OUT"
