#!/usr/bin/env bash
# Summarise a snapshot's batterystats into a Markdown report.
# Usage: scripts/04_report.sh reports/snapshot-<label>
set -eu
source "$(dirname "$0")/lib.sh"
SNAP="${1:?usage: $0 reports/snapshot-<label>}"
BS="$SNAP/batterystats.txt"
OUT="$SNAP/report.md"
[ -f "$BS" ] || die "no batterystats.txt in $SNAP"

{
  echo "# Battery report: $(basename "$SNAP")"
  echo
  echo "## Global drain (since last full charge)"
  echo '```'
  awk '/Estimated power use/{f=1} f&&/^[[:space:]]+UID/{exit} f' "$BS" | awk 'NR<=12'
  echo '```'
  echo
  echo "## Top apps by estimated mAh"
  echo
  echo "| mAh | foreground | background | cached | package |"
  echo "|----:|-----------:|-----------:|-------:|---------|"
  awk '
    /^[[:space:]]+UID u0a[0-9]+: [0-9.]+/ {
      uid=$2; sub(/^u0a/,"",uid); sub(/:$/,"",uid); mah=$3; fg="0"; bg="0"; ca="0";
      for(i=4;i<=NF;i++){ if($i=="fg:")fg=$(i+1); if($i=="bg:")bg=$(i+1); if($i=="cached:")ca=$(i+1) }
      printf "%s %s %s %s %s\n", uid, mah, fg, bg, ca }' "$BS" \
    | sort -k2 -rn | awk 'NR<=20' \
    | while read -r uid mah fg bg ca; do
        real=$((10000+uid))
        pkg="$(tr -d '\r' < "$SNAP/packages_uid.txt" | awk -v u="uid:$real" '$2==u{sub(/^package:/,"",$1); print $1; exit}')"
        printf '| %s | %s | %s | %s | %s |\n' "$mah" "$fg" "$bg" "$ca" "${pkg:-uid $real}"
      done
  echo
  echo "## Memory"
  echo '```'
  head -3 "$SNAP/proc_meminfo.txt"
  grep -E "^Swap(Total|Free)" "$SNAP/proc_meminfo.txt"
  echo '```'
  echo
  echo "## Battery health"
  echo '```'
  grep -E "Estimated battery capacity|learned battery capacity" "$BS" | sed 's/^ *//'
  echo '```'
} > "$OUT"
log "Report written to $OUT"
cat "$OUT"
