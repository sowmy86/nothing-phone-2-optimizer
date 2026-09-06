#!/usr/bin/env bash
# Apply battery/performance settings. Previous values are saved to
# reports/settings_backup-<ts>.txt so restore.sh can undo them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_adb
BACKUP="$REPORTS/settings_backup-$TS.txt"
log "Applying settings to $(device_model); backup -> $BACKUP"

# namespace key value  -- reason
SETTINGS=(
  # --- Display (largest single consumer on any OLED phone) ---
  "system screen_off_timeout 60000"          # 30 min -> 1 min
  "system screen_brightness_mode 1"          # manual -> adaptive brightness
  "secure ui_night_mode 2"                   # force dark theme (OLED pixels off)

  # --- Perceived speed: halve animation durations ---
  "global window_animation_scale 0.5"
  "global transition_animation_scale 0.5"
  "global animator_duration_scale 0.5"
  "secure long_press_timeout 300"            # default 400 ms; long-press menus open sooner

  # --- Radios ---
  "global mobile_data_always_on 0"           # dev option: keeps LTE radio active while on Wi-Fi
  "global wifi_scan_always_enabled 0"        # background Wi-Fi scanning for location
  "global ble_scan_always_enabled 0"         # background BLE scanning for location

  # --- DNS: Cloudflare over TLS; faster lookups than most carrier resolvers ---
  "global private_dns_mode hostname"
  "global private_dns_specifier one.one.one.one"

  # --- Power management ---
  "global adaptive_battery_management_enabled 1"
  "global app_auto_restriction_enabled 1"    # let the system auto-restrict misbehaving apps
  "global automatic_power_save_mode 0"       # 0 = percentage based
  "global low_power_trigger_level 15"        # battery saver kicks in at 15%
  "global cached_apps_freezer enabled"       # freeze cached apps (no CPU while backgrounded)
  "global dynamic_power_savings_enabled 0"
)

for entry in "${SETTINGS[@]}"; do
  set -- $entry
  ns="$1"; key="$2"; val="$3"
  old="$(setting_get "$ns" "$key")"
  printf '%s %s %s\n' "$ns" "$key" "${old:-null}" >> "$BACKUP"
  setting_put "$ns" "$key" "$val"
  printf '  %-45s %-12s -> %s\n' "$ns/$key" "${old:-null}" "$val"
done

# Nothing OS telemetry toggle lives in a namespace that varies by build; find it.
for ns in global secure system; do
  if [ "$(setting_get $ns nt_data_collection)" = "1" ]; then
    printf '%s nt_data_collection 1\n' "$ns" >> "$BACKUP"
    setting_put "$ns" nt_data_collection 0
    printf '  %-45s %-12s -> %s\n' "$ns/nt_data_collection" 1 0
  fi
done

# --- Faster Doze: shorten the timers before the phone enters deep idle ---
# Trade-off: apps that poll (not push) may deliver notifications a little later.
DOZE=(
  "inactive_to 60000"               # screen off -> inactive after 1 min (default 30 min)
  "sensing_to 0"
  "locating_to 0"
  "motion_inactive_to 0"
  "idle_after_inactive_to 60000"
  "idle_pending_to 60000"
  "max_idle_pending_to 120000"
  "idle_to 1800000"                 # 30 min in deep idle before a maintenance window
  "max_idle_to 21600000"
  "light_after_inactive_to 15000"
  "light_pre_idle_to 60000"
  "light_idle_to 300000"
  "light_max_idle_to 900000"
)
log "Tightening Doze timers via device_config device_idle (Android 15+ allows only some flags from shell)"
ok=(); blocked=()
for entry in "${DOZE[@]}"; do
  set -- $entry
  out="$(adb shell device_config put device_idle "$1" "$2" 2>&1 || true)"
  if grep -q SecurityException <<<"$out"; then blocked+=("$1"); else ok+=("$1"); fi
done
[ ${#ok[@]} -gt 0 ] && { echo "  applied: ${ok[*]}"; printf 'device_config device_idle %s\n' "${ok[@]}" >> "$BACKUP"; }
[ ${#blocked[@]} -gt 0 ] && warn "blocked without root: ${blocked[*]}"

log "Settings applied. Some take effect after screen off/on; Doze timers apply immediately."
