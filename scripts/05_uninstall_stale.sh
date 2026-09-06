#!/usr/bin/env bash
# Uninstall third-party apps that have not been opened for a long time.
# DRY RUN by default. Pass --yes to actually uninstall.
# Usage: scripts/05_uninstall_stale.sh [--days N] [--yes]      (default N=60)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
DAYS=60; DO=0
while [ $# -gt 0 ]; do case "$1" in --days) DAYS="$2"; shift;; --yes) DO=1;; esac; shift; done
KEEP="$(read_list "$LISTS/keep.txt")"
PROTECT="$(read_list "$LISTS/never_uninstall.txt")"
LOG="$REPORTS/uninstalled-$TS.txt"
USAGE="$(adb shell dumpsys usagestats 2>/dev/null)"

log "Third-party apps unused for > $DAYS days ('never' = no launch in the ~2 year usage history)"
CANDIDATES=(); PROTECTED=()
while read -r pkg; do
  last="$(grep -E "package=$pkg .*lastTimeUsed=" <<<"$USAGE" | grep -oE 'lastTimeUsed="?[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1 || true)"
  [ -n "$last" ] || continue                      # no record at all: unknown, leave alone
  d="$(days_since "$last")"
  [ "$d" -gt "$DAYS" ] || continue
  [ "$d" -gt 10000 ] && d="never"
  if grep -qx "$pkg" <<<"$KEEP" || grep -qiF -f <(printf '%s\n' "$PROTECT") <<<"$pkg"; then
    PROTECTED+=("$d $pkg"); continue
  fi
  CANDIDATES+=("$d $pkg")
done < <(adb shell pm list packages -3 | tr -d '\r' | sed 's/package://')

printf '  %-6s %s\n' "days" "package"
for c in "${CANDIDATES[@]:-}"; do [ -n "$c" ] && printf '  %-6s %s\n' $c; done
if [ ${#PROTECTED[@]} -gt 0 ]; then
  warn "Stale but protected (finance/keep list), left installed:"
  for c in "${PROTECTED[@]}"; do printf '  %-6s %s\n' $c; done
fi

[ ${#CANDIDATES[@]} -gt 0 ] || { log "Nothing to remove."; exit 0; }
if [ "$DO" -ne 1 ]; then
  warn "Dry run. Re-run with --yes to uninstall ${#CANDIDATES[@]} apps. They can be reinstalled from the Play Store."
  exit 0
fi

log "Uninstalling ${#CANDIDATES[@]} apps"
for c in "${CANDIDATES[@]}"; do
  set -- $c; pkg="$2"
  out="$(adb shell pm uninstall --user 0 "$pkg" 2>&1 | tr -d '\r')"
  if grep -q Success <<<"$out"; then echo "$pkg" >> "$LOG"; echo "  removed $pkg"; else warn "  failed $pkg: $out"; fi
done
log "Done. Removed list saved to $LOG (reinstall from Play if you miss anything)."
