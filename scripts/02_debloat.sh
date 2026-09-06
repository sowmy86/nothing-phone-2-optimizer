#!/usr/bin/env bash
# Disable (not uninstall) preinstalled packages. Everything is reversible with restore.sh.
# Usage: scripts/02_debloat.sh                              # safe tier only
#        scripts/02_debloat.sh --aggressive                 # safe + every aggressive entry
#        scripts/02_debloat.sh --aggressive --unused-only 60 # aggressive entries only if usage stats
#                                                           #   prove no use for 60+ days
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
LOG="$REPORTS/disabled-$TS.txt"
TIERS=("$LISTS/debloat_safe.txt"); UNUSED_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  --aggressive) TIERS+=("$LISTS/debloat_aggressive.txt");;
  --unused-only) UNUSED_ONLY="$2"; shift;;
esac; shift; done
USAGE=""; [ "$UNUSED_ONLY" -gt 0 ] && USAGE="$(adb shell dumpsys usagestats 2>/dev/null)"
days_unused() {  # prints days since last use, "never", or "" when there is no record
  local last
  last="$(grep -E "package=$1 .*lastTimeUsed=" <<<"$USAGE" | grep -oE 'lastTimeUsed="?[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1 || true)"
  [ -n "$last" ] || return 0
  local d; d="$(days_since "$last")"; [ "$d" -gt 10000 ] && d=never; echo "$d"
}

KEEP="$(read_list "$LISTS/keep.txt")"
n=0; skipped=0
for f in "${TIERS[@]}"; do
  log "Tier: $(basename "$f")"
  while read -r pkg; do
    if grep -qx "$pkg" <<<"$KEEP"; then warn "  keep-listed, skipping $pkg"; continue; fi
    if ! is_installed "$pkg"; then skipped=$((skipped+1)); continue; fi
    if ! is_enabled "$pkg"; then continue; fi
    if [ "$UNUSED_ONLY" -gt 0 ] && [ "$f" = "$LISTS/debloat_aggressive.txt" ]; then
      d="$(days_unused "$pkg")"
      if [ -z "$d" ]; then warn "  no usage record for $pkg, leaving enabled"; continue; fi
      if [ "$d" != never ] && [ "$d" -le "$UNUSED_ONLY" ]; then echo "  used ${d}d ago, keeping $pkg"; continue; fi
      why=" (unused: $d)"
    else why=""; fi
    out="$(adb shell pm disable-user --user 0 "$pkg" 2>&1 | tr -d '\r')"
    if grep -q "disabled-user" <<<"$out"; then
      echo "$pkg" >> "$LOG"; n=$((n+1)); echo "  disabled $pkg$why"
    else
      warn "  could not disable $pkg"
    fi
  done < <(read_list "$f")
done
log "Disabled $n packages ($skipped not present on this device). Log: $LOG"
