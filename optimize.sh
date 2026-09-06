#!/usr/bin/env bash
# Nothing Phone (2) Optimizer - single entry point.
#
#   ./optimize.sh              interactive menu
#   ./optimize.sh --auto       recommended optimisation, no questions asked (safe tier only)
#   ./optimize.sh --full       --auto plus evidence-based extra debloat and primary-app compile
#   ./optimize.sh --clean      list apps unused 60+ days and offer to remove them
#   ./optimize.sh --measure    battery drain since the last reset
#   ./optimize.sh --restore    undo everything
#
# Nothing here needs root. Everything except --clean is reversible with --restore.
set -euo pipefail
cd "$(dirname "$0")"
source scripts/lib.sh

banner() {
  cat <<'TXT'

  Nothing Phone (2) Optimizer
  root-free battery and speed tuning over adb
TXT
}

preflight() {
  command -v adb >/dev/null 2>&1 || die "adb is not installed.
  macOS:   brew install android-platform-tools
  Ubuntu:  sudo apt install adb
  Windows: install Platform Tools and run this from Git Bash or WSL"
  local state; state="$(adb get-state 2>/dev/null || true)"
  if [ "$state" != "device" ]; then
    cat <<'TXT'
  No phone found. On the phone:
    1. Settings > About phone > tap "Build number" 7 times
    2. Settings > System > Developer options > enable "USB debugging"
    3. Plug in with a data cable and tap "Allow" on the phone
TXT
    die "then run this again."
  fi
  local model brand device
  brand="$(adb shell getprop ro.product.brand | tr -d '\r')"
  device="$(adb shell getprop ro.product.device | tr -d '\r')"
  model="$(adb shell getprop ro.product.model | tr -d '\r')"
  log "Connected: $brand $model ($device), Android $(adb shell getprop ro.build.version.release | tr -d '\r')"
  if [ "$device" != "Pong" ]; then
    warn "This is tuned for the Nothing Phone (2) ('Pong'). Settings and background rules still apply to"
    warn "any Android phone, but the package lists are Nothing-specific and will simply be skipped."
    [ "${AUTO:-0}" = 1 ] || { read -r -p "  Continue anyway? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || exit 0; }
  fi
  local lvl; lvl="$(adb shell dumpsys battery | grep -E '^\s+level' | grep -oE '[0-9]+' | tr -d '\r')"
  [ "${lvl:-100}" -lt 20 ] && warn "Battery at ${lvl}%. Plug the phone in; the compile steps take a few minutes."
  return 0
}

quick() {
  log "Step 1/5  Snapshot before"
  scripts/00_baseline.sh before >/dev/null
  log "Step 2/5  Settings (display, radios, power, DNS)"
  scripts/01_settings.sh
  log "Step 3/5  Disable preinstalled telemetry and setup-only apps"
  scripts/02_debloat.sh "$@"
  log "Step 4/5  Restrict background for stale and heavy apps"
  scripts/03_background.sh
  log "Step 5/5  Recompile apps, trim storage"
  scripts/06_speedup.sh
  scripts/00_baseline.sh after >/dev/null
}

full() {
  quick --aggressive --unused-only 60
  log "Extra  Compile your most-used apps ahead of time"
  scripts/07_primary_apps.sh --auto 3
}

summary() {
  echo
  log "Done. What changed on the phone:"
  printf '  %-34s %s\n' "preinstalled apps disabled" "$(cat reports/disabled-*.txt 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  printf '  %-34s %s\n' "apps restricted in background" "$(adb shell cmd appops query-op RUN_ANY_IN_BACKGROUND ignore | wc -l | tr -d ' ')"
  printf '  %-34s %s\n' "settings backup" "$(ls -t reports/settings_backup-*.txt 2>/dev/null | tail -1)"
  printf '  %-34s %s\n' "refresh rate (untouched)" "peak $(setting_get system peak_refresh_rate) Hz, adaptive"
  cat <<'TXT'

  Things only you can do, in the phone's Settings:
    - Battery > Charging: set the 80% charge limit
    - Network > SIMs: turn on Wi-Fi calling and VoLTE
    - In X / Reddit / YouTube: turn video autoplay off and use the true-black dark theme

  Measure the result after a full day off the charger:  ./optimize.sh --measure
  Undo everything:                                       ./optimize.sh --restore
TXT
}

menu() {
  banner; preflight
  cat <<'TXT'

  1) Quick optimise (recommended)  settings + safe debloat + background rules + recompile
  2) Full optimise                 quick + extra debloat with usage evidence + compile your top apps
  3) Clean up                      list apps unused 60+ days and offer to uninstall them
  4) Measure                       battery drain since the last reset
  5) Restore                       undo everything this tool changed
  q) Quit
TXT
  read -r -p "  Choose: " c
  case "$c" in
    1) quick; summary;;
    2) full; summary;;
    3) clean;;
    4) scripts/08_measure.sh;;
    5) scripts/restore.sh;;
    *) exit 0;;
  esac
}

clean() {
  scripts/05_uninstall_stale.sh
  echo
  read -r -p "  Uninstall the apps listed above? They can be reinstalled from the Play Store. [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] && scripts/05_uninstall_stale.sh --yes
  return 0
}

case "${1:-}" in
  --auto)    AUTO=1; banner; preflight; quick; summary;;
  --full)    AUTO=1; banner; preflight; full; summary;;
  --clean)   banner; preflight; clean;;
  --measure) preflight; scripts/08_measure.sh "${2:-}";;
  --restore) preflight; scripts/restore.sh;;
  -h|--help) sed -n '2,11p' "$0";;
  "")        menu;;
  *)         die "unknown option $1 (try --help)";;
esac
