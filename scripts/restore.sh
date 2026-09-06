#!/usr/bin/env bash
# Undo everything: re-enable disabled packages, lift background restrictions,
# restore settings from the most recent backup, reset Doze timers.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb

log "Re-enabling packages"
(cat "$REPORTS"/disabled-*.txt 2>/dev/null || true) | sort -u | while read -r pkg; do
  [ -n "$pkg" ] || continue
  adb shell pm enable --user 0 "$pkg" >/dev/null && echo "  enabled $pkg"
done

log "Lifting background restrictions"
(cat "$REPORTS"/restricted-*.txt 2>/dev/null || true) | sort -u | while read -r a b; do
  [ -n "$a" ] || continue
  if [ "$a" = "whitelist" ]; then
    adb shell dumpsys deviceidle whitelist "+$b" >/dev/null && echo "  re-added Doze exemption $b"
  else
    adb shell cmd appops set "$a" RUN_ANY_IN_BACKGROUND allow >/dev/null
    adb shell am set-standby-bucket "$a" active >/dev/null
    echo "  unrestricted $a"
  fi
done

BACKUP="$(ls -t "$REPORTS"/settings_backup-*.txt 2>/dev/null | tail -1 || true)"   # oldest = original values
if [ -n "$BACKUP" ]; then
  log "Restoring settings from $BACKUP"
  while read -r ns key val; do
    [ "$ns" = "device_config" ] && continue
    if [ "$val" = "null" ]; then adb shell settings delete "$ns" "$key" >/dev/null; else setting_put "$ns" "$key" "$val"; fi
    printf '  %s/%s -> %s\n' "$ns" "$key" "$val"
  done < "$BACKUP"
fi

log "Resetting Doze timers"
for k in inactive_to sensing_to locating_to motion_inactive_to idle_after_inactive_to idle_pending_to max_idle_pending_to idle_to max_idle_to light_after_inactive_to light_pre_idle_to light_idle_to light_max_idle_to; do
  adb shell device_config delete device_idle "$k" >/dev/null 2>&1 || true
done
if ls "$REPORTS"/uninstalled-*.txt >/dev/null 2>&1; then
  warn "Uninstalled third-party apps cannot be restored by adb; reinstall these from the Play Store if you want them back:"
  cat "$REPORTS"/uninstalled-*.txt | sort -u | sed 's/^/  /'
fi
log "Restore complete."
