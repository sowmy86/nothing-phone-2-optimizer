#!/usr/bin/env bash
# Shared helpers for the Nothing Phone (2) optimizer scripts.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LISTS="$ROOT/lists"
REPORTS="$ROOT/reports"
mkdir -p "$REPORTS"
TS="$(date +%Y%m%d-%H%M%S)"

# adb must never read our stdin, otherwise it eats the rest of any `while read` loop.
adb() {
  if [ "${1:-}" = "shell" ]; then shift; command adb shell -n "$@"; else command adb "$@"; fi
}

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_adb() {
  command -v adb >/dev/null 2>&1 || die "adb not found. Install with: brew install android-platform-tools"
  local state
  state="$(adb get-state 2>/dev/null || true)"
  [ "$state" = "device" ] || die "No authorised device over adb. Enable USB debugging and accept the prompt on the phone."
}

device_model() { adb shell getprop ro.product.model | tr -d '\r'; }

# Exact-match check that a package is installed for user 0.
# Package lists are fetched once per run and matched in-process. Never pipe adb into
# `grep -q`: grep exits early, adb gets SIGPIPE, and `pipefail` turns that into a failure.
_PKG_ALL=""; _PKG_ENABLED=""
is_installed() {
  [ -n "$_PKG_ALL" ] || _PKG_ALL="$(adb shell pm list packages --user 0 2>/dev/null | tr -d '\r')"
  grep -qx "package:$1" <<<"$_PKG_ALL"
}
is_enabled() {
  [ -n "$_PKG_ENABLED" ] || _PKG_ENABLED="$(adb shell pm list packages --user 0 -e 2>/dev/null | tr -d '\r')"
  grep -qx "package:$1" <<<"$_PKG_ENABLED"
}

# Read "pkg  # comment" lists, skipping blanks and comments.
read_list() { sed -E 's/#.*//; s/[[:space:]]+$//' "$1" | grep -v '^$'; }

# Days since a YYYY-MM-DD date, portable across macOS and GNU date.
days_since() {
  local d="$1" then
  if date -j >/dev/null 2>&1; then then=$(date -j -f "%Y-%m-%d" "$d" +%s); else then=$(date -d "$d" +%s); fi
  echo $(( ( $(date +%s) - then ) / 86400 ))
}

setting_get() { adb shell settings get "$1" "$2" | tr -d '\r'; }
setting_put() { adb shell settings put "$1" "$2" "$3" >/dev/null; }
