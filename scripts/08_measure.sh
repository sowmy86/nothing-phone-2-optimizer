#!/usr/bin/env bash
# Drain rate since the last battery-stats reset / full charge, plus the top consumers.
# Run after a day of normal use. Reset a cycle with:  scripts/08_measure.sh --reset
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
if [ "${1:-}" = "--reset" ]; then adb shell dumpsys batterystats --reset >/dev/null; log "Battery stats reset. Unplug and use the phone normally."; exit 0; fi
BS="$REPORTS/measure-$TS.txt"
adb shell dumpsys batterystats --charged > "$BS" 2>/dev/null
adb shell pm list packages -U > "$REPORTS/measure-$TS.uid" 2>/dev/null
tob="$(grep -m1 'Time on battery:' "$BS" | sed -E 's/.*battery: ([^(]*) \(.*/\1/' || true)"
dis="$(grep -m1 'Discharge:' "$BS" | grep -oE '[0-9]+ mAh' | head -1 || true)"
soff="$(grep -m1 'Screen off discharge' "$BS" | grep -oE '[0-9]+ mAh' | head -1 || true)"
son="$(grep -m1 'Screen on:' "$BS" | sed -E 's/.*Screen on: ([^(]*) \(.*/\1/' || true)"
# hours on battery
h=$(awk -v s="$tob" 'BEGIN{d=0;hh=0;m=0; if(match(s,/[0-9]+d/)){d=substr(s,RSTART,RLENGTH-1)} if(match(s,/[0-9]+h/)){hh=substr(s,RSTART,RLENGTH-1)} if(match(s,/[0-9]+m/)){m=substr(s,RSTART,RLENGTH-1)} printf "%.2f", d*24+hh+m/60}')
dmah="${dis%% *}"; smah="${soff:-0 mAh}"; smah="${smah%% *}"
echo "Time on battery : $tob   (screen on: ${son:-?})"
echo "Discharge       : ${dis:-?}  (screen-off share: ${soff:-?})"
if [ "${h:-0}" != "0.00" ] && [ -n "$dmah" ]; then
  awk -v d="$dmah" -v h="$h" -v cap=4048 'BEGIN{printf "Average drain   : %.0f mA  →  %.1f %%/h of the 4048 mAh learned capacity\n", d/h, d/h/cap*100}'
fi
echo; echo "Top 12 apps (mAh: total / foreground / background / cached):"
awk '/^[[:space:]]+UID u0a[0-9]+: [0-9.]+/ {uid=$2; sub(/^u0a/,"",uid); sub(/:$/,"",uid); fg="0"; bg="0"; ca="0";
  for(i=4;i<=NF;i++){ if($i=="fg:")fg=$(i+1); if($i=="bg:")bg=$(i+1); if($i=="cached:")ca=$(i+1) }
  printf "%s %s %s %s %s\n", uid, $3, fg, bg, ca }' "$BS" | sort -k2 -rn | awk 'NR<=12' \
| while read -r uid mah fg bg ca; do
    real=$((10000+uid)); pkg="$(tr -d '\r' < "$REPORTS/measure-$TS.uid" | awk -v u="uid:$real" '$2==u{sub(/^package:/,"",$1); print $1; exit}')"
    printf '  %7s  %7s  %7s  %7s   %s\n' "$mah" "$fg" "$bg" "$ca" "${pkg:-uid $real}"
  done
