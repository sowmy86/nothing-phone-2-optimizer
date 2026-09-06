# Nothing Phone (2) Optimizer

One command that makes a Nothing Phone (2) faster and longer-lasting, without root, and undoes itself
on request. Works from macOS, Linux, or Windows (Git Bash / WSL) over a USB cable.

```bash
git clone https://github.com/sowmy86/nothing-phone-2-optimizer.git
cd nothing-phone-2-optimizer
./optimize.sh
```

```
  1) Quick optimise (recommended)  settings + safe debloat + background rules + recompile
  2) Full optimise                 quick + extra debloat with usage evidence + compile your top apps
  3) Clean up                      list apps unused 60+ days and offer to uninstall them
  4) Measure                       battery drain since the last reset
  5) Restore                       undo everything this tool changed
```

Non-interactive: `./optimize.sh --auto`, `--full`, `--clean`, `--measure`, `--restore`.

Before the first run, on the phone: Settings › About phone › tap *Build number* 7 times, then
Settings › System › Developer options › *USB debugging*. Plug in, tap *Allow*. You need `adb`
(`brew install android-platform-tools` on macOS, `apt install adb` on Ubuntu, Platform Tools on Windows).

Tested on Nothing Phone (2) India, Nothing OS B4.1 (Android 16). The settings and background rules
apply to any Android 14+ phone; the package lists are Nothing-specific and are skipped elsewhere.

## What it does

| Step | Script | Effect |
|------|--------|--------|
| Snapshot | `scripts/00_baseline.sh` | Dumps batterystats, packages, settings, Doze state, usage stats into `reports/` so you can measure before vs after |
| Settings | `scripts/01_settings.sh` | Screen timeout 1 min, adaptive brightness, dark theme, 0.5× animations, 300 ms long-press, Private DNS to Cloudflare, disables *mobile data always active*, Wi-Fi/BLE background scanning, enables adaptive battery + cached-app freezer, battery saver at 15 %, turns off Nothing telemetry |
| Debloat | `scripts/02_debloat.sh` | `pm disable-user` on preinstalled telemetry, ad-personalisation, setup-only and dead apps (`lists/debloat_safe.txt`). `--aggressive` adds Android Auto, hotword, YouTube Music, Essential Space, etc. |
| Background | `scripts/03_background.sh` | Puts every third-party app unused for 30+ days, plus known hogs (`lists/restrict_background.txt`), into Android's *Restricted* battery mode; removes user-added Doze exemptions |
| Report | `scripts/04_report.sh` | Markdown table of per-app mAh, memory and battery health from a snapshot |
| Uninstall | `scripts/05_uninstall_stale.sh` | Lists third-party apps unused for 60+ days (dry run). `--yes` uninstalls them. Banking, brokers, wallets, payments and 2FA are never touched (`lists/never_uninstall.txt`) |
| Primary apps | `scripts/07_primary_apps.sh` | Full AOT compile of the apps in `lists/primary_apps.txt` (faster cold start) and a checklist of the in-app battery switches that adb cannot reach |
| Measure | `scripts/08_measure.sh` | Drain in mA and %/h since the last reset plus the top consumers. `--reset` starts a clean cycle |
| Speed-up | `scripts/06_speedup.sh` | Forces the ART background dexopt now, compiles launcher and SystemUI with `speed-profile`, trims app caches, runs `fstrim`, drops cached processes once |
| Undo | `scripts/restore.sh` | Re-enables every package, lifts every restriction, restores every setting from the saved backup |

Steps 1 to 4 uninstall nothing and touch no app data. Only `05_uninstall_stale.sh --yes` removes apps, and only ones you have not opened in 60+ days. `lists/keep.txt` is a hard block-list the scripts will never act on: put your banking, 2FA and messaging apps there.

## Running pieces on their own

`optimize.sh` just sequences the scripts below; each one can be run alone and re-running is safe.
Edit `lists/keep.txt` first if there are apps you must keep receiving notifications from.

To measure the effect: reset the stats, unplug, use the phone normally for a day, then read the rate.

```bash
scripts/08_measure.sh --reset      # while still plugged in
# ... a day later ...
scripts/08_measure.sh              # average mA, %/h, top consumers
```

Reference numbers from the baseline cycle before any change: 1853 mAh over 17 h 39 m on battery, 105 mA average, about 2.6 %/h with 3 h of screen-on time. Anything under 80 mA on a similar day is a clear win.

## Results on the reference device

Baseline drain over one discharge cycle before any change (from `batterystats`):

| Component | mAh | Share |
|-----------|----:|------:|
| CPU | 632 | 34 % |
| Screen | 443 | 24 % |
| Mobile radio | 194 | 11 % |
| Sensors | 25 | 1 % |
| **Total** | **1837** | |

What the baseline exposed:

- **One social app was 39 % of all drain** (722 mAh), including radio and sensor use while cached in the background.
- Another social app burned 51 mAh purely in the background.
- Screen timeout was set to 30 minutes with manual brightness.
- The *mobile data always active* developer option was on, keeping LTE up while on Wi-Fi.
- Two apps not opened in 3–7 weeks were exempt from Doze.
- Wi-Fi and Bluetooth background scanning were both on.
- Battery saver had been toggled on manually 58 times, with no automatic schedule.
- Battery health: learned capacity 4048 of 4700 mAh (≈ 86 % after three years).
- Memory: 262 MB free, 2.7 GB of swap in use, 140 third-party apps installed.

Applied by the scripts on the reference device:

| Action | Count |
|--------|------:|
| Settings changed | 19 |
| Preinstalled packages disabled (safe tier + aggressive with usage evidence) | 26 |
| Third-party apps uninstalled (unused 60+ days, non-finance, plus one dormant free VPN) | 23 |
| Apps moved to *Restricted* background mode | 37 remaining |
| Doze exemptions removed | 2 |

Immediately after (same charge, so no drain comparison yet):

| Metric | Before | After |
|--------|-------:|------:|
| Third-party apps | 140 | 117 |
| Free RAM (`MemFree`) | 262 MB | 2.8 GB |
| Available RAM | 4.5 GB | 6.8 GB |
| Swap in use | 2.7 GB | 1.2 GB |
| Free storage | 82 GB | 91 GB |

Refresh rate was left at adaptive 120 Hz throughout; it is not a meaningful battery lever on this panel and it is the main thing that makes the phone feel fast.

## What is not possible without root on Android 16

- Tightening most Doze timers (`device_config device_idle …`) is blocked for shell on Android 15+ ("must add flag to the allowlist"). The script applies the flags the OS still allows (the light-Doze timers) and reports the rest as blocked.
- Changing the preferred network mode (5G → LTE-only) via `settings put` no longer works; do it in **Settings › Network › SIM › Preferred network type**. Dropping 5G on a Phone (2) is worth roughly an hour of screen-on time in weak-signal areas.
- Per-app refresh-rate forcing. Nothing OS already runs adaptive 60/120 Hz; leave `peak_refresh_rate` alone.

## Making it feel snappier (without touching the display)

Done by the scripts: 0.5× animation scales, 300 ms long-press, ART `speed-profile` compile of the launcher and SystemUI, forced background dexopt for everything else, cached-app freezer, and fewer resident apps (every uninstalled or disabled app is one less process competing for the 12 GB). Keep adaptive 120 Hz on; forcing 60 Hz saves little on this LTPO panel and makes everything feel slower.

## Manual tips worth more than any script

1. **Review `scripts/05_uninstall_stale.sh` output every couple of months.** Apps you stop using accumulate background work.
2. **Charge to 80 %** (Settings › Battery › Charging › Battery protection) to slow further capacity loss.
3. **Glyph**: keep it, but turn off *Glyph progress* for apps you do not use; each active integration keeps a listener alive.
4. **Essential Space** indexes screenshots with on-device ML. Disable it (`--aggressive`) if you never open it.

## Safety

- `pm disable-user --user 0` hides a package; it is restored with `pm enable`. It does not survive a factory reset, so nothing here can brick the device.
- Android's *Restricted* mode delays push notifications for the affected apps. Do not restrict anything you need alerts from; put it in `lists/keep.txt`.
- Raw snapshots contain account IDs, location and usage history. `reports/` is git-ignored. Do not commit it.

## Layout

```
optimize.sh   the program; everything below is what it calls
scripts/      00_baseline 01_settings 02_debloat 03_background 04_report 05_uninstall_stale 06_speedup
              07_primary_apps 08_measure restore lib
lists/     keep.txt debloat_safe.txt debloat_aggressive.txt restrict_background.txt never_uninstall.txt primary_apps.txt
reports/   (git-ignored) snapshots, settings backups, disabled/restricted logs
```

## License

MIT
