#!/usr/bin/env bash
# Make the apps you actually live in start faster and cost less:
#  - full AOT compile (pm compile -m speed) so there is no JIT warm-up on cold start
#  - WebView gets a profile compile too (social apps open links in it)
#  - prints the in-app switches that adb cannot flip but that matter most
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
# --auto N : ignore the list and pick the N third-party apps with the most screen time this week
pick_top() {
  local n="$1" third
  third="$(adb shell pm list packages -3 | tr -d '\r' | sed 's/package://')"
  adb shell dumpsys usagestats 2>/dev/null | awk '/In-memory weekly stats/{f=1} /In-memory monthly stats/{f=0} f' \
    | grep -oE 'package=[^ ]+ totalTimeUsed="[0-9:]+"' \
    | awk -F'"' '{ split($1,a,"="); sub(/ totalTimeUsed.*/,"",a[2]); pkg=a[2];
        n=split($2,t,":"); s=0; for(i=1;i<=n;i++) s=s*60+t[i]; print s, pkg }' \
    | sort -rn | while read -r secs pkg; do if grep -qx "$pkg" <<<"$third"; then echo "$pkg"; fi; done | awk -v n="$n" 'NR<=n' || true
}
SRC="$(read_list "$LISTS/primary_apps.txt")"
if [ "${1:-}" = "--auto" ]; then
  SRC="$(pick_top "${2:-3}")"
  log "Most-used apps this week: $(echo $SRC | tr '\n' ' ')"
fi
log "Ahead-of-time compiling primary apps (a minute per large app; keep the phone plugged in)"
while read -r pkg; do
  [ -n "$pkg" ] || continue
  is_installed "$pkg" || { warn "  $pkg not installed"; continue; }
  res="$(adb shell pm compile -m speed -f "$pkg" 2>&1 | tr -d '\r' | tail -1)"
  printf '  %-30s %s  bucket=%s  bg=%s\n' "$pkg" "$res" "$(adb shell am get-standby-bucket "$pkg" | tr -d '\r')" \
    "$(adb shell cmd appops get "$pkg" RUN_ANY_IN_BACKGROUND | tr -d '\r' | grep -oE 'ignore|allow|No operations' | head -1)"
done <<<"$SRC"
adb shell pm compile -m speed-profile -f com.google.android.webview >/dev/null 2>&1 || true

cat <<'TXT'

In-app settings worth flipping (adb cannot reach these):
  X            Settings › Accessibility, display and languages › Data usage:
                 Data saver ON, Video autoplay NEVER, High-quality images OFF, High-quality video OFF
               Display: Dark mode "Lights out" (true black; the OLED turns those pixels off)
               Accessibility: Reduce motion ON
  Reddit       Settings › Autoplay: Never;  Dark mode: AMOLED;  Reduce animations ON
               Settings › Notifications: turn off "Trending" and "Recommended" (each one wakes the app)
  WhatsApp     Settings › Storage and data › Media auto-download: mobile data = none, roaming = none
               Settings › Chats › Chat backup: Wi-Fi only, back up while charging; Include videos OFF
               Settings › Storage and data › Use less data for calls ON
Restricted background mode is kept for X and Reddit: their pushes arrive through FCM without the app
running. If DMs start arriving late, lift it with:  cmd appops set <pkg> RUN_ANY_IN_BACKGROUND allow
TXT
