#!/usr/bin/env bash
# Restrict background activity for apps that are stale or known battery hogs,
# and remove user-added Doze exemptions. Third-party apps are never uninstalled.
# Usage: scripts/03_background.sh [--stale-days N]   (default 30)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
STALE_DAYS=30
[ "${1:-}" = "--stale-days" ] && STALE_DAYS="$2"
LOG="$REPORTS/restricted-$TS.txt"
KEEP="$(read_list "$LISTS/keep.txt")"

restrict() {
  local pkg="$1" why="$2"
  grep -qx "$pkg" <<<"$KEEP" && { warn "  keep-listed, skipping $pkg"; return; }
  is_installed "$pkg" || return 0
  adb shell cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore >/dev/null
  adb shell am set-standby-bucket "$pkg" restricted >/dev/null
  echo "$pkg" >> "$LOG"
  printf '  restricted %-50s (%s)\n' "$pkg" "$why"
}

log "Finding third-party apps unused for > $STALE_DAYS days"
USAGE="$(adb shell dumpsys usagestats 2>/dev/null)"
STALE_FILE="$REPORTS/stale_apps-$TS.txt"
while read -r pkg; do
  last="$(grep -E "package=$pkg .*lastTimeUsed=" <<<"$USAGE" | grep -oE 'lastTimeUsed="?[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1 || true)"
  [ -n "$last" ] || continue
  d="$(days_since "$last")"
  [ "$d" -gt "$STALE_DAYS" ] && echo "$d $pkg" >> "$STALE_FILE"
done < <(adb shell pm list packages -3 | tr -d '\r' | sed 's/package://')
sort -rn -o "$STALE_FILE" "$STALE_FILE" 2>/dev/null || true
while read -r d pkg; do restrict "$pkg" "unused ${d}d"; done < "$STALE_FILE"

log "Restricting known background-heavy apps from lists/restrict_background.txt"
while read -r pkg; do restrict "$pkg" "listed"; done < <(read_list "$LISTS/restrict_background.txt")

log "Removing user-added Doze exemptions (battery optimisation = 'Not optimised')"
USER_WL="$(adb shell dumpsys deviceidle whitelist | tr -d '\r' | grep '^user,' | cut -d, -f2 || true)"
while read -r pkg; do
  [ -n "$pkg" ] || continue
  if grep -qx "$pkg" <<<"$KEEP"; then warn "  keep-listed, leaving $pkg exempt"; continue; fi
  adb shell dumpsys deviceidle whitelist "-$pkg" >/dev/null
  echo "whitelist $pkg" >> "$LOG"
  echo "  removed Doze exemption for $pkg"
done <<<"$USER_WL"

log "Done. Log: $LOG  Stale list: $STALE_FILE"
